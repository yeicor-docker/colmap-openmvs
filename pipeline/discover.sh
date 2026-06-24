#!/usr/bin/env bash
################################################################################
# Tool Discovery System - Maps env vars to COLMAP/OpenMVS tool help text
# Dynamically generates YAML documentation from installed tools and stage files.
# Each environment variable links directly to the --help output of the command
# it configures.
# Usage: ./discover.sh [--print-help | --print-vars-shell | --help]
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGES_DIR="${SCRIPT_DIR}/stages"
OPENMVS_BIN_DIR="/usr/local/bin/OpenMVS"

################################################################################
# YAML safe string escaping (for single-line strings)
################################################################################

yaml_escape() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    echo "\"${str}\""
}

################################################################################
# YAML literal block scalar (preserves formatting for multi-line strings)
################################################################################

yaml_block_scalar() {
    local str="$1"
    local indent="${2:-6}"
    local indent_str
    printf -v indent_str '%*s' "$indent" ''

    if [[ -z "$str" ]]; then
        echo "~"
        return
    fi

    if [[ "$str" == *$'\n'* ]]; then
        echo "|"
        while IFS= read -r line; do
            echo "${indent_str}${line}"
        done <<< "$str"
    else
        yaml_escape "$str"
    fi
}

################################################################################
# Discover environment variables from stage files (source of truth)
################################################################################

# Find all stage files across common/ and all pipeline directories
find_stage_files() {
    find "$STAGES_DIR" -maxdepth 2 -name "*.stage.sh" -type f 2>/dev/null | sort -u || true
}

# Auto-discover available pipelines from subdirectories (excluding common/ and lib/)
discover_pipelines() {
    find "$STAGES_DIR" -mindepth 1 -maxdepth 1 -type d ! -name "common" ! -name "lib" -printf "%f\n" 2>/dev/null | sort || true
}

discover_env_vars_from_stages() {
    [[ -d "$STAGES_DIR" ]] || return 0
    while IFS= read -r stage_file; do
        grep -h -oP '\$\{[A-Z_][A-Z0-9_]*(:-[^}]*)?\}' "$stage_file" | \
            sed -E 's/\$\{([A-Z_][A-Z0-9_]*)(:-[^}]*)?\}/\1/g' | sort -u | \
            while read -r var; do
                [[ "$var" =~ IMAGES_DIR|WORK_DIR ]] && continue  # Skip core path variables
                echo "$var"
            done
    done < <(find_stage_files) || true
}

################################################################################
# Discover COLMAP tools
################################################################################

discover_colmap_tools() {
    command -v colmap &>/dev/null || return 1
    colmap --help 2>&1 | awk '
        /^[[:space:]]{2,}[a-z_]+/ {
            gsub(/^[[:space:]]+/, "")
            cmd = $1
            if (cmd !~ /^(help|options|usage|colmap)$/) {
                print cmd
            }
        }
    ' | sort -u
}

################################################################################
# Discover OpenMVS tools
################################################################################

discover_openmvs_tools() {
    [[ -d "$OPENMVS_BIN_DIR" ]] || return 1
    find "$OPENMVS_BIN_DIR" -maxdepth 1 -type f -executable 2>/dev/null | \
        xargs -I {} basename {} | grep -v '^\.' | sort -u || true
}

################################################################################
# Track and clean .log files created during tool runs
################################################################################

LOG_SNAPSHOT_BEFORE=""
LOG_SNAPSHOT_AFTER=""

snapshot_logs_before() {
    LOG_SNAPSHOT_BEFORE="$(mktemp)"
    find . -maxdepth 1 -type f -name "*.log" -printf "%f\n" | sort > "$LOG_SNAPSHOT_BEFORE"
}

snapshot_logs_after() {
    LOG_SNAPSHOT_AFTER="$(mktemp)"
    find . -maxdepth 1 -type f -name "*.log" -printf "%f\n" | sort > "$LOG_SNAPSHOT_AFTER"
}

cleanup_new_logs() {
    local dry_run="${1:-false}"

    [[ -f "$LOG_SNAPSHOT_BEFORE" && -f "$LOG_SNAPSHOT_AFTER" ]] || return 0

    comm -13 "$LOG_SNAPSHOT_BEFORE" "$LOG_SNAPSHOT_AFTER" | while read -r file; do
        [[ -z "$file" ]] && continue

        if [[ "$dry_run" == "true" ]]; then
            echo "[DRY-RUN] Would remove: $file"
        else
            echo "Removing: $file"
            rm -f -- "$file"
        fi
    done

    rm -f "$LOG_SNAPSHOT_BEFORE" "$LOG_SNAPSHOT_AFTER"
    LOG_SNAPSHOT_BEFORE=""
    LOG_SNAPSHOT_AFTER=""
}

################################################################################
# Run OpenMVS tool with automatic log cleanup
################################################################################

run_openmvs_tool() {
    snapshot_logs_before
    "$@"
    snapshot_logs_after
    cleanup_new_logs
}

################################################################################
# Get help text for a tool
################################################################################

get_tool_help() {
    local tool="$1" tool_path="${2:-}"
    if [[ -z "$tool_path" ]]; then
        colmap "$tool" --help 2>&1 | grep -v 'option_manager.cc' || echo ""
    else
        run_openmvs_tool "$tool_path" --help 2>&1 | grep -v '\[App' || echo ""
    fi
}

################################################################################
# Find environment variables used for a tool in stage files
# Only matches _ARGS variables (the actual tool-argument env vars). The special
# selector variables (COLMAP_MAPPER, COLMAP_MATCHER) are handled separately.
################################################################################

find_env_vars_for_tool() {
    local tool_name="$1"
    local check_file
    check_file="$(grep -rlF -- "$tool_name" "$STAGES_DIR" --include="*.stage.sh" 2>/dev/null || true)"
    [[ -z "$check_file" ]] && return 0
    local -a check_files
    mapfile -t check_files <<< "$check_file"
    grep -h -oP '\$\{[A-Z_][A-Z0-9_]*_ARGS\}' "${check_files[@]}" 2>/dev/null | \
        sed 's/[${}]//g' | sort -u || true
}

################################################################################
# Custom help text for env vars that don't map to a tool --help
# These are selector variables (e.g. COLMAP_MAPPER, COLMAP_MATCHER) that choose
# which subcommand to run rather than passing arguments to one.
################################################################################

# Single source of truth for all custom (non-ARGS) environment variables.
# Outputs tab-separated lines: NAME<tab>DESCRIPTION
# Use get_custom_var_names() / get_custom_var_help() to extract specific fields.
get_custom_vars() {
    local pipelines
    pipelines=$(discover_pipelines 2>/dev/null | tr '\n' ', ' | sed 's/,$//' | sed 's/,/, /g') || true
    cat <<-EOF
COLMAP_MAPPER	Selects COLMAP mapper algorithm. Options: mapper (alias), global_mapper (default, recommended), hierarchical_mapper. When using global_mapper, the pipeline automatically runs view_graph_calibrator on a copy of the database to improve focal length priors. See COLMAP_SKIP_VIEW_GRAPH_CALIBRATOR.
COLMAP_MATCHER	Selects COLMAP feature matcher. Options: exhaustive_matcher, sequential_matcher, spatial_matcher, transitive_matcher, vocab_tree_matcher (default).
COLMAP_SKIP_VIEW_GRAPH_CALIBRATOR	If set to 1, skip the view_graph_calibrator step even when using global_mapper. By default (0), view_graph_calibrator is run before global_mapper to calibrate intrinsics from the view graph.
EXTRACT_KEYFRAMES_REMOVE_VIDEOS	If set to true, deletes video files from videos/ after successful keyframe extraction.
PIPELINE	Selects the SfM pipeline to use. Auto-discovered from subdirectories in stages/ (excludes common/ and lib/). Available: ${pipelines:-none}. Default: colmap-openmvs-sparse.
EOF
}

get_custom_var_names() {
    get_custom_vars | cut -f1
}

get_custom_var_help() {
    local var="$1"
    awk -F'\t' -v var="$var" '$1 == var { sub(/^[^\t]+\t/, ""); print; found=1 } END { exit !found }' <(get_custom_vars)
}

################################################################################
# Build the env-var → tool-command mapping from auto-discovered tools and
# stage-file associations.  Returns lines:  <VAR> <type> <tool>
# where <type> is "colmap" or "openmvs".
################################################################################

build_env_var_command_mapping() {
    local colmap_tools openmvs_tools
    colmap_tools=$(discover_colmap_tools 2>/dev/null || true)
    openmvs_tools=$(discover_openmvs_tools 2>/dev/null || true)

    while IFS= read -r tool; do
        [[ -z "$tool" ]] && continue
        local env_vars
        env_vars=$(find_env_vars_for_tool "$tool")
        [[ -z "$env_vars" ]] && continue
        while IFS= read -r var; do
            [[ -z "$var" ]] && continue
            echo "$var colmap $tool"
        done <<< "$env_vars"
    done <<< "$colmap_tools"

    while IFS= read -r tool; do
        [[ -z "$tool" ]] && continue
        local env_vars
        env_vars=$(find_env_vars_for_tool "$tool")
        [[ -z "$env_vars" ]] && continue
        while IFS= read -r var; do
            [[ -z "$var" ]] && continue
            echo "$var openmvs $tool"
        done <<< "$env_vars"
    done <<< "$openmvs_tools"
}

################################################################################
# Generate YAML: environment variables → command help text
################################################################################

generate_help_yaml() {
    echo "---"
    echo "environment_variables:"

    local all_vars
    all_vars=$(discover_env_vars_from_stages)

    # Build the auto-discovered mapping (tool → env-var associations from stages)
    declare -A var_to_type  # "colmap" or "openmvs"
    declare -A var_to_tool

    local mapping
    mapping=$(build_env_var_command_mapping)
    while IFS=' ' read -r var type tool; do
        [[ -z "$var" ]] && continue
        var_to_type["$var"]="$type"
        var_to_tool["$var"]="$tool"
    done <<< "$mapping"

    # Custom selector/flag variables (no tool --help to query)
    while IFS= read -r _custom_var; do
        [[ -z "$_custom_var" ]] && continue
        var_to_type["$_custom_var"]="custom"
    done < <(get_custom_var_names)

    # Merge auto-discovered vars with registered custom vars so all appear in output
    # even if not referenced in any stage file (e.g. PIPELINE)
    if [[ -n "$all_vars" ]]; then
        while IFS= read -r var; do
            [[ -z "$var" ]] && continue
            var_to_type["$var"]="${var_to_type[$var]:-}"
        done <<< "$all_vars"
        all_vars=$(printf '%s\n' "${!var_to_type[@]}")
    elif [[ ${#var_to_type[@]} -gt 0 ]]; then
        all_vars=$(printf '%s\n' "${!var_to_type[@]}")
    else
        return 0
    fi

    # Cache help text per unique (type,tool) pair so shared commands
    # (e.g. ReconstructMesh for sparse/dense variants) are queried once.
    declare -A help_cache

    while IFS= read -r var; do
        [[ -z "$var" ]] && continue

        local type="${var_to_type[$var]:-}"
        [[ -z "$type" ]] && continue

        local help_text=""

        if [[ "$type" == "custom" ]]; then
            help_text=$(get_custom_var_help "$var") || true
        else
            local tool="${var_to_tool[$var]}"
            local cache_key="${type}:${tool}"
            if [[ -n "${help_cache[$cache_key]:-}" ]]; then
                help_text="${help_cache[$cache_key]}"
            else
                if [[ "$type" == "colmap" ]]; then
                    help_text=$(get_tool_help "$tool")
                else
                    help_text=$(get_tool_help "$tool" "${OPENMVS_BIN_DIR}/${tool}")
                fi
                help_cache[$cache_key]="$help_text"
            fi
        fi

        [[ -z "$help_text" ]] && continue

        echo "  $var:"
        echo -n "    help: "
        yaml_block_scalar "$help_text" 6
    done <<< "$all_vars"
}

################################################################################
# Generate shell-compatible variable exports
################################################################################

generate_vars_shell() {
    local all_env_vars
    all_env_vars=$(discover_env_vars_from_stages)

    # Always include custom selector/flag variables even if not in stage files
    # Always include custom selector/flag variables even if not in stage files
    # (sourced from get_custom_var_names to avoid duplication)
    local custom_vars
    custom_vars=$(get_custom_var_names)

    # Merge and deduplicate
    if [[ -n "$all_env_vars" ]]; then
        all_env_vars=$(printf '%s\n%s' "$all_env_vars" "$custom_vars" | sort -u)
    else
        all_env_vars="$custom_vars"
    fi

    echo "$all_env_vars" | while read -r var; do
        [[ -z "$var" ]] && continue
        echo "export $var=\"\${${var}:-}\""
    done
}

################################################################################
# Main
################################################################################

case "${1:-help}" in
    --print-help)
        generate_help_yaml
        ;;
    --print-vars-shell)
        generate_vars_shell
        ;;
    --help|-h)
        cat << 'HELP_TEXT'
Tool Discovery System
Usage: discover.sh [--print-help | --print-vars-shell | --help]

MODES:
  --print-help           Generate YAML documentation for all configurable
                         environment variables and their associated tool
                         help text (copied verbatim, not parsed)

  --print-vars-shell     Generate shell-compatible export statements
                         (for sourcing in bash scripts)

  --help, -h             Show this help message

FEATURES:
  - Auto-discovers COLMAP tools by running 'colmap --help'
  - Auto-discovers OpenMVS tools by scanning /usr/local/bin/OpenMVS
  - Auto-discovers available SfM pipelines from stages/ subdirectories
  - Maps each environment variable to the tool it configures via stage-file
    association (only outputs help for vars that have a corresponding tool)
  - Copies tool --help output verbatim without parsing
  - Deduplicates help queries: shared commands (sparse/dense) queried once
  - Discovers environment variables from stage files automatically
  - Generates clean, machine-readable YAML output

EXAMPLES:
  # View all configurable variables with their tool help text
  ./discover.sh --print-help

  # Source environment variables with defaults
  eval "$(./discover.sh --print-vars-shell)"

HELP_TEXT
        ;;
    *)
        "$0" --help
        ;;
esac
