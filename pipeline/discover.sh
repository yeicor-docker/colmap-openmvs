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

discover_env_vars_from_stages() {
    [[ -d "$STAGES_DIR" ]] || return 0
    while IFS= read -r stage_file; do
        grep -h -oP '\$\{[A-Z_][A-Z0-9_]*(:-[^}]*)?\}' "$stage_file" | \
            sed -E 's/\$\{([A-Z_][A-Z0-9_]*)(:-[^}]*)?\}/\1/g' | sort -u | \
            while read -r var; do
                [[ "$var" =~ IMAGES_DIR|WORK_DIR ]] && continue  # Skip core path variables
                echo "$var"
            done
    done < <(find "$STAGES_DIR" -maxdepth 1 -name "*.stage.sh" | sort) || true
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
    check_file="$(grep -lF -- "$tool_name" "$STAGES_DIR"/*.stage.sh 2>/dev/null || true)"
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

get_custom_var_help() {
    local var="$1"
    case "$var" in
        COLMAP_MAPPER)
            echo "Selects COLMAP mapper algorithm. Options: mapper (alias), global_mapper (default, recommended)."
            ;;
        COLMAP_MATCHER)
            echo "Selects COLMAP feature matcher. Options: exhaustive_matcher, sequential_matcher, spatial_matcher, transitive_matcher, vocab_tree_matcher (default)."
            ;;
        *)
            return 1
            ;;
    esac
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
    [[ -z "$all_vars" ]] && return 0

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

    # Custom selector variables (no tool --help to query)
    var_to_type["COLMAP_MAPPER"]="custom"
    var_to_type["COLMAP_MATCHER"]="custom"

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
    [[ -z "$all_env_vars" ]] && return 0

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
