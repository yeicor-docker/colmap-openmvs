#!/usr/bin/env bash
################################################################################
# Tool Discovery System - Auto-discovers COLMAP and OpenMVS tools
# Dynamically generates YAML configuration from installed tools and stage files
# Usage: ./discover.sh [--print-help | --print-vars-shell | --help]
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGES_DIR="${SCRIPT_DIR}/stages"
OPENMVS_BIN_DIR="/usr/local/bin/OpenMVS"

################################################################################
# YAML safe string escaping
################################################################################

yaml_escape() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    echo "\"${str}\""
}

################################################################################
# Discover environment variables from stage files
################################################################################

discover_env_vars_from_stages() {
    [[ -d "$STAGES_DIR" ]] || return 0
    for stage_file in $(ls "$STAGES_DIR"/*.stage.sh 2>/dev/null | sort); do
        grep -h -oP '\$\{[A-Z_][A-Z0-9_]*(:-[^}]*)?\}' "$stage_file" | \
            sed -E 's/\$\{([A-Z_][A-Z0-9_]*)(:-[^}]*)?\}/\1/g' | sort -u | \
            while read -r var; do
                [[ "$var" =~ IMAGES_DIR|WORK_DIR ]] && continue  # Skip core path variables
                echo "$var"
            done
    done || true
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
# Get help text for a tool
################################################################################

get_tool_help() {
    local tool="$1" tool_path="${2:-}"
    if [[ -z "$tool_path" ]]; then
        colmap "$tool" --help 2>&1 | grep -v 'option_manager.cc' || echo ""
    else
        "$tool_path" --help 2>&1 | grep -v '\[App' || echo ""
    fi
}

################################################################################
# Find environment variables used for a tool in stage files
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
# Output a single tool entry in YAML format
################################################################################

output_tool_entry() {
    local tool="$1" tool_path="${2:-}"
    local help_text tool_env_vars

    help_text=$(get_tool_help "$tool" "$tool_path" 2>/dev/null || echo "")
    tool_env_vars=$(find_env_vars_for_tool "$tool")

    echo "    $tool:"
    echo "      help: $(yaml_escape "$help_text")"

    if [[ -n "$tool_env_vars" ]]; then
        echo "      environment_variables:"
        echo "$tool_env_vars" | while read -r var; do
            [[ -z "$var" ]] && continue
            echo "        - $var"
        done
    else
        echo "      environment_variables: []"
    fi
}

################################################################################
# Generate YAML help from discovered tools
################################################################################

generate_help_yaml() {
    cat << 'YAML_START'
---
tools:
  colmap:
YAML_START

    local colmap_tools
    colmap_tools=$(discover_colmap_tools 2>/dev/null || true)

    while IFS= read -r tool; do
        [[ -z "$tool" ]] && continue
        output_tool_entry "$tool"
    done <<< "$colmap_tools"

    echo "  openmvs:"

    local openmvs_tools
    openmvs_tools=$(discover_openmvs_tools 2>/dev/null || true)

    while IFS= read -r tool; do
        [[ -z "$tool" ]] && continue
        output_tool_entry "$tool" "$OPENMVS_BIN_DIR/$tool"
    done <<< "$openmvs_tools"
}

################################################################################
# Generate YAML variables configuration
################################################################################

generate_vars_yaml() {
    cat << 'VARS_START'
environment_variables:
VARS_START

    local all_env_vars
    all_env_vars=$(discover_env_vars_from_stages)

    echo "$all_env_vars" | while read -r var; do
        [[ -z "$var" ]] && continue
        echo "  $var:"
        echo "    type: string"
    done
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
        generate_vars_yaml
        ;;
    --print-vars-shell)
        generate_vars_shell
        ;;
    --help|-h)
        cat << 'HELP_TEXT'
Tool Discovery System
Usage: discover.sh [--print-help | --print-vars-shell | --help]

MODES:
  --print-help           Generate YAML help for pipeline with auto-discovered tools
                         and their help text (copied as-is, not parsed)

  --print-vars-shell     Generate shell-compatible export statements
                         (for sourcing in bash scripts)

  --help, -h             Show this help message

FEATURES:
  - Auto-discovers COLMAP tools by running 'colmap --help'
  - Auto-discovers OpenMVS tools by scanning /usr/local/bin/OpenMVS
  - Copies tool help output verbatim without parsing
  - Discovers environment variables from stage files only
  - Links environment variables to tools based on stage file mentions
  - Generates machine-readable YAML output

EXAMPLES:
  # View auto-discovered pipeline configuration
  ./discover.sh --print-help

  # Source environment variables with defaults
  eval "$(./discover.sh --print-vars-shell)"

HELP_TEXT
        ;;
    *)
        "$0" --help
        ;;
esac
