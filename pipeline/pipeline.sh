#!/usr/bin/env bash
################################################################################
# Photogrammetry Pipeline (COLMAP + OpenMVS)
# Simple, reliable, sequential execution
#
# Caching logic: A stage runs IFF:
#   1. Any output is missing, OR
#   2. Input hash has changed (quick hash of input paths, sizes, mtimes)
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGES_DIR="${SCRIPT_DIR}/stages"

################################################################################
# Parse arguments at global scope
################################################################################

# Early exit for --help and --print-vars
for arg in "$@"; do
    case "$arg" in
        -h|--help)
            "${SCRIPT_DIR}/discover.sh" --print-help
            exit 0
            ;;
        --print-vars)
            "${SCRIPT_DIR}/discover.sh" --print-vars-shell
            exit 0
            ;;
        --dry-run)
            DRY_RUN=1
            ;;
    esac
done

WORK_DIR="${1:-.}"
shift || true

IMAGES_DIR="${WORK_DIR}/images"
PIPELINE_DIR="${WORK_DIR}/pipeline"

# Parse options
VERBOSE=0
FORCE_STAGES=""
SKIP_STAGES=""
DRY_RUN=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        -v|--verbose) VERBOSE=1; shift ;;
        --dry-run) DRY_RUN=1; shift ;;
        --force) FORCE_STAGES="$2"; shift 2 ;;
        --skip) SKIP_STAGES="$2"; shift 2 ;;
        *) shift ;;
    esac
done

# Validate WORK_DIR before creating PIPELINE_DIR
if [[ ! -d "$WORK_DIR" ]]; then
    echo "Directory not found: $WORK_DIR" >&2
    exit 1
fi
mkdir -p "$PIPELINE_DIR"

################################################################################
# Main pipeline logic (all output teed to log file)
################################################################################

main() {
    # GitHub-style group annotations for machine-parseable log output
    log_group() {
        local params="$1"
        local title="$2"
        echo "::group ${params}::$title"
    }
    log_endgroup() {
        echo "::endgroup::"
    }

    # Logging functions (output to stdout, which gets teed to log file)
    log()     { echo "[$(date '+%H:%M:%S')] • $*"; }
    log_ok()  { echo "[$(date '+%H:%M:%S')] ✓ $*"; }
    log_err() { echo "[$(date '+%H:%M:%S')] ✗ $*" >&2; }
    log_dbg() { [[ $VERBOSE == 1 ]] && echo "[$(date '+%H:%M:%S')] ▸ $*" || true; }

    # Quick hash of a file or directory (paths + sizes + mtimes for change detection)
    hash_path() {
        local target="$1"
        if [[ ! -e "$target" ]]; then
            echo "missing"
            return
        fi
        if [[ -d "$target" ]]; then
            (cd "$target" && find . -type f -exec stat -c '%n %s %Y' {} + 2>/dev/null | sort | md5sum) 2>/dev/null | cut -d' ' -f1
        else
            stat -c '%n %s %Y' "$target" 2>/dev/null | md5sum | cut -d' ' -f1
        fi
    }

    # Compute and store hash for a stage's inputs and outputs
    stage_hash_path() {
        echo "${PIPELINE_DIR}/stage_${1}.hash"
    }

    stage_log_path() {
        echo "${PIPELINE_DIR}/stage_${1}.log"
    }

    stage_get_hash() {
        local hashfile=$(stage_hash_path "$1")
        [[ -f "$hashfile" ]] && cat "$hashfile" || echo ""
    }

    stage_save_hash() {
        local hashfile=$(stage_hash_path "$1")
        echo "$2" > "$hashfile"
    }

    stage_compute_hash() {
        local stage="$1"
        shift
        local all_paths=("$@")
        local combined=""
        for p in "${all_paths[@]}"; do
            [[ -n "$p" ]] && combined="${combined}$(hash_path "$p")"
        done
        echo "$combined" | md5sum | cut -d' ' -f1
    }

    is_skipped() {
        local stage=$1
        echo ",$SKIP_STAGES," | grep -qF ",$stage," && return 0 || true
        return 1
    }

    is_forced() {
        local stage=$1
        echo ",$FORCE_STAGES," | grep -qF ",$stage," && return 0 || true
        return 1
    }

    outputs_stale() {
        local stage="$1"
        local inputs_str="$2"
        local outputs_str="$3"

        local inputs=()
        for inp in $inputs_str; do
            [[ -n "$inp" ]] && inputs+=("$inp")
        done

        local outputs=()
        for out in $outputs_str; do
            [[ -n "$out" ]] && outputs+=("$out")
        done

        # Check if any output is missing
        for out in "${outputs[@]}"; do
            if [[ ! -e "$out" ]]; then
                echo "output_missing:$out"
                return 0
            fi
        done

        # Only hash inputs to check if we need to re-run
        # Outputs are hashed and saved after successful run
        local current_hash=$(stage_compute_hash "$stage" "${inputs[@]}")
        local stored_hash=$(stage_get_hash "$stage")

        if [[ -z "$stored_hash" ]] || [[ "$current_hash" != "$stored_hash" ]]; then
            echo "hash_changed:stored=${stored_hash:-none},current=$current_hash"
            return 0
        fi
        return 1
    }

    cleanup_openmvs_logs() {
        local openmvs_dir="${WORK_DIR}/openmvs"
        [[ -d "$openmvs_dir" ]] || return 0
        find "$openmvs_dir" -type f -name "*.log" -delete 2>/dev/null || true
    }

    run_stage() {
        if [[ $VERBOSE == 1 ]]; then
            (set -x; run_stage_function)
        else
            run_stage_function
        fi
    }

    if [[ ! -d "$WORK_DIR/images" ]]; then
        log_err "No images/ directory in: $WORK_DIR"
        exit 1
    fi

    rm -rf "${WORK_DIR}/pipeline/stages" 2>/dev/null || true

    log_group "file=pipeline.sh,section=config" "Config"
    log_dbg "Work directory: $WORK_DIR (images: $WORK_DIR/images)"
    [[ $VERBOSE == 1 ]] && log "VERBOSE mode"

    CONFIG_FILE="${WORK_DIR}/config.sh"
    if [[ -f "$CONFIG_FILE" ]]; then
        log_dbg "Loading config: $CONFIG_FILE"
        if ! source "$CONFIG_FILE"; then
            log_err "Failed to load config: $CONFIG_FILE"
            exit 1
        fi
    fi
    log_endgroup

    log_group "file=pipeline.sh,section=tools" "Tool Discovery"
    log_dbg "Discovering config..."
    eval "$(${SCRIPT_DIR}/discover.sh --print-vars-shell)" || { log_err "Failed to discover tools"; exit 1; }
    log_dbg "Found ${#stages[@]} stages"
    log_endgroup

    ############################################################################
    # Execute stages
    ############################################################################

    if [[ ${#stages[@]} -eq 0 ]]; then
        log_err "No stages found in $STAGES_DIR"
        exit 1
    fi

    # Now handle stale reasons inside the group for each stage
    stage_count=0
    
    for stage_file in "${stages[@]}"; do
        stage_name=$(basename "$stage_file" .stage.sh)
        ((stage_count++))

        unset DEPENDENCIES INPUTS OUTPUTS DISPLAY_NAME run_stage_function
        if ! source "$stage_file"; then
            log_err "Failed to load stage file: $stage_file"
            exit 1
        fi

        # Determine status first, then open group
        stage_status="run"
        skip_stage=0
        cache_stage=0
        stale_reason=""

        if is_forced "$stage_name"; then
            stage_status="forced"
        elif is_skipped "$stage_name"; then
            stage_status="skipped"
            skip_stage=1
        elif stale_reason=$(outputs_stale "$stage_name" "${INPUTS[*]:-}" "${OUTPUTS[*]:-}"); then
            # outputs_stale returns 0 (true) if stale/has reason, 1 (false) if fresh
            stage_status="run"
        else
            stage_status="cached"
            cache_stage=1
        fi

        # Open group and log inside it with type and count
        local display_name="${DISPLAY_NAME:-$stage_name}"
        log_group "file=${stage_file},type=stage,status=${stage_status},count=${stage_count}/${#stages[@]}" "$display_name"

        if [[ $skip_stage == 1 ]]; then
            log "Stage $stage_name: skipped (--skip)"
            log_endgroup
            continue
        elif [[ $cache_stage == 1 ]]; then
            # Replay cached stage output
            stage_log=$(stage_log_path "$stage_name")
            if [[ -f "$stage_log" ]]; then
                cat "$stage_log"
            else
                log "Stage $stage_name: cached (hash unchanged) [no log to replay]"
            fi
            log_endgroup
            continue
        fi

        # Check if dry-run mode - skip execution but show debug message in verbose mode
        if [[ ${DRY_RUN:-0} == 1 ]]; then
            log "Stage $stage_name: skipped due to --dry-run"
            log_endgroup
            continue
        fi

        # Running stage - capture output to log file with live display
        stage_log=$(stage_log_path "$stage_name")
        if [[ "$stage_status" == "forced" ]]; then
            log "Stage $stage_name: forced (--force)"
        else
            log "Stage $stage_name: will run (${stale_reason:-missing/stale outputs})"
        fi

        # Run stage with live output and save to log file using tee
        # This shows output live while capturing it to the stage log file
        # Use a subshell with set +e to capture exit code properly
        (
            set +e
            run_stage "$stage_name" 2>&1
            echo $? > "${stage_log}.exit_code"
        ) | tee "$stage_log"
        # Verify log file was created
        if [[ ! -f "$stage_log" ]]; then
            log_err "Failed to create stage log: $stage_log"
        fi
        exit_code=$(cat "${stage_log}.exit_code" 2>/dev/null || echo "1")
        rm -f "${stage_log}.exit_code"

        if [[ $exit_code -ne 0 ]]; then
            log_err "$stage_name (exit code: $exit_code)"
            if [[ $VERBOSE == 1 ]]; then
                log_err "Check log for details"
            else
                log_err "See ${PIPELINE_DIR}/stage_${stage_name}.log for details"
            fi
            rm -f "$stage_log"
            exit 1
        fi

        missing=0
        for out in "${OUTPUTS[@]:-}"; do
            if [[ ! -e "$out" ]]; then
                log_err "$stage_name: output missing: $out"
                missing=1
            fi
        done

        if [[ $missing == 1 ]]; then
            rm -f "$stage_log"
            exit 1
        fi

        # Save hash of inputs only (matches what outputs_stale checks)
        current_hash=$(stage_compute_hash "$stage_name" "${INPUTS[@]:-}")
        stage_save_hash "$stage_name" "$current_hash"

        cleanup_openmvs_logs

        log_ok "$stage_name"
        log_endgroup
    done
}

################################################################################
# Discover stages and print remaining groups early
################################################################################

readarray -t stages < <(find "${STAGES_DIR}" -name "*.stage.sh" | sort)

declare -a stage_display_names
for stage_file in "${stages[@]}"; do
    stage_name=$(basename "$stage_file" .stage.sh)
    display_name=$(grep -m1 '^DISPLAY_NAME=' "$stage_file" 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "")
    display_name="${display_name:-$stage_name}"
    stage_display_names+=("$display_name")
done

echo -n "::remaining_groups::Config,Tool Discovery"
for display_name in "${stage_display_names[@]}"; do
    echo -n ",$display_name"
done
echo ""

# Run main, capture exit code
set +e
main
exit_code=$?
set -e
exit $exit_code
