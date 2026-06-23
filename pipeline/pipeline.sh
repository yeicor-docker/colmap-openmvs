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
        --dry-run|--recover-logs)
            DRY_RUN=1
            ;;
    esac
done

WORK_DIR="${1:-.}"
shift || true

IMAGES_DIR="${WORK_DIR}/images"
VIDEOS_DIR="${WORK_DIR}/videos"
PIPELINE_DIR="${WORK_DIR}/pipeline"

# Parse options
VERBOSE=0
FORCE_STAGES=""
SKIP_STAGES=""
RECOVER_LOGS=0
: "${DRY_RUN:=0}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        -v|--verbose) VERBOSE=1; shift ;;
        --dry-run)    DRY_RUN=1; shift ;;
        --recover-logs) RECOVER_LOGS=1; shift ;;
        --force) FORCE_STAGES="$2"; shift 2 ;;
        --skip) SKIP_STAGES="$2"; shift 2 ;;
        *) shift ;;
    esac
done

# If recover-logs is requested, also set dry-run to skip execution
if [[ $RECOVER_LOGS == 1 ]]; then
    DRY_RUN=1
fi

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
    trap 'cleanup_openmvs_logs || true' EXIT
    # GitHub-style group annotations for machine-parseable log output
    log_group() {
        local params="$1"
        local title="$2"
        echo "::group ${params}::$title"
    }
    log_endgroup() {
        echo "::endgroup::"
    }

    # Logging functions
    log()     { echo "[$(date '+%H:%M:%S')] • $*"; }
    log_ok()  { echo "[$(date '+%H:%M:%S')] ✓ $*"; }
    log_err() { echo "[$(date '+%H:%M:%S')] ✗ $*" >&2; }

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

    dependencies_satisfied() {
        # Check stage-name dependencies (hash file existence)
        local dep
        for dep in "${DEPENDENCIES[@]:-}"; do
            [[ -z "$dep" ]] && continue
            local dep_hash
            dep_hash=$(stage_hash_path "$dep")
            [[ -f "$dep_hash" ]] || return 1
        done
        # Check file/directory dependencies (path existence)
        for dep in "${FILE_DEPENDENCIES[@]:-}"; do
            [[ -z "$dep" ]] && continue
            [[ -e "$dep" ]] || return 1
        done
        return 0
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
        local current_hash=$(stage_compute_hash "$stage" "${inputs[@]}" "$CONFIG_FILE" "$stage_file")
        local stored_hash=$(stage_get_hash "$stage")

        if [[ -z "$stored_hash" ]] || [[ "$current_hash" != "$stored_hash" ]]; then
            echo "hash_changed:stored=${stored_hash:-none},current=$current_hash"
            return 0
        fi
        return 1
    }

    # Explain cache state in clear language
    debug_cache_state() {
        local reasons=()

        # Check stage-name dependencies
        local dep
        for dep in "${DEPENDENCIES[@]:-}"; do
            [[ -z "$dep" ]] && continue
            if [[ ! -f "$(stage_hash_path "$dep")" ]]; then
                reasons+=("dependency $dep still running")
            fi
        done

        # Check file dependencies
        for dep in "${FILE_DEPENDENCIES[@]:-}"; do
            [[ -z "$dep" ]] && continue
            if [[ ! -e "$dep" ]]; then
                reasons+=("missing file: $dep")
            fi
        done

        # Check outputs
        local outputs_msg=""
        for out in "${OUTPUTS[@]}"; do
            if [[ ! -e "$out" ]]; then
                outputs_msg="$out"
            fi
        done

        # Hash info
        local combined_hash=""
        combined_hash=$(stage_compute_hash "$stage_name" "${INPUTS[@]}" "$CONFIG_FILE" "$stage_file")
        local stored_hash
        stored_hash=$(stage_get_hash "$stage_name")

        if [[ -z "$stored_hash" ]]; then
            :
        elif [[ "$stored_hash" != "$combined_hash" ]]; then
            reasons+=("inputs changed (key ${stored_hash} → ${combined_hash})")
        fi

        # Build one-line cache summary
        if [[ $cache_stage == 1 ]]; then
            log "OK"
        elif [[ -n "$outputs_msg" ]]; then
            log "missing: $outputs_msg"
        elif [[ ${#reasons[@]} -gt 0 ]]; then
            log "${reasons[*]}"
        elif [[ -z "$stored_hash" ]]; then
            log "no saved state (first run or interrupted)"
        fi
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

    if [[ ! -d "$WORK_DIR/images" ]] && [[ ! -d "$WORK_DIR/videos" ]]; then
        log_err "No images/ or videos/ directory in: $WORK_DIR"
        exit 1
    fi

    rm -rf "${WORK_DIR}/pipeline/stages" 2>/dev/null || true

    log_group "file=pipeline.sh,section=config" "Config"
    log "Work directory: $WORK_DIR"
    log "Images: $WORK_DIR/images"
    if [[ -d "$WORK_DIR/videos" ]]; then
        log "Videos: $WORK_DIR/videos"
    fi

    CONFIG_FILE="${WORK_DIR}/config.sh"
    if [[ -f "$CONFIG_FILE" ]]; then
        log "Config: $CONFIG_FILE"
        if ! source "$CONFIG_FILE"; then
            log_err "Failed to load config: $CONFIG_FILE"
            exit 1
        fi
    fi
    log_endgroup

    log_group "file=pipeline.sh,section=tools" "Tool Discovery"
    eval "$(${SCRIPT_DIR}/discover.sh --print-vars-shell)" || { log_err "Failed to discover tools"; exit 1; }
    log_endgroup

    ############################################################################
    # Execute stages
    ############################################################################

    # Print a stages overview before starting
    local pipeline="${SFM_PIPELINE:-colmap-openmvs-sparse}"
    local pipeline_dir="${STAGES_DIR}/${pipeline}"
    readarray -t stages < <(find "${pipeline_dir}" -maxdepth 1 -name "*.stage.sh" | sort)
    if [[ ${#stages[@]} -eq 0 ]]; then
        log_err "No stages found in ${pipeline_dir}"
        exit 1
    fi
    log "Pipeline: ${#stages[@]} stages loaded (SFM_PIPELINE=${pipeline})"

    stage_count=0

    for stage_file in "${stages[@]}"; do
        stage_name=$(basename "$stage_file" .stage.sh)
        ((stage_count++))

        unset DEPENDENCIES INPUTS OUTPUTS FILE_DEPENDENCIES DISPLAY_NAME run_stage_function
        if ! source "$stage_file"; then
            log_err "Failed to load stage file: $stage_file"
            exit 1
        fi

        # Determine status
        stage_status="run"
        skip_stage=0
        cache_stage=0
        stale_reason=""

        if is_forced "$stage_name"; then
            stage_status="forced"
        elif is_skipped "$stage_name"; then
            stage_status="skipped"
            skip_stage=1
        elif ! dependencies_satisfied; then
            stale_reason="dependency_missing"
            stage_status="run"
        elif stale_reason=$(outputs_stale "$stage_name" "${INPUTS[*]:-}" "${OUTPUTS[*]:-}"); then
            stage_status="run"
        else
            stage_status="cached"
            cache_stage=1
        fi

        # Open stage group
        local display_name="${DISPLAY_NAME:-$stage_name}"
        log_group "file=${stage_file},type=stage,status=${stage_status},count=${stage_count}/${#stages[@]}" "$display_name"
        debug_cache_state

        # Handle special modes
        if [[ $skip_stage == 1 ]]; then
            log "  skipped (--skip)"
            log_endgroup
            continue
        elif [[ $cache_stage == 1 ]]; then
            stage_log=$(stage_log_path "$stage_name")
            if [[ -f "$stage_log" ]]; then
                cat "$stage_log"
            fi
            log_endgroup
            continue
        elif [[ $RECOVER_LOGS == 1 ]]; then
            stage_log=$(stage_log_path "$stage_name")
            if [[ -f "$stage_log" ]]; then
                log "  previous run log:"
                cat "$stage_log"
            else
                log "  no previous log to recover"
            fi
            log_endgroup
            continue
        elif [[ ${DRY_RUN:-0} == 1 ]]; then
            log "  skipped (--dry-run)"
            log_endgroup
            continue
        fi

        # Execute stage
        stage_log=$(stage_log_path "$stage_name")
        if [[ "$stage_status" == "forced" ]]; then
            log "  forced (--force)"
        else
            log "  ${stale_reason:-missing/stale outputs}"
        fi

        (
            run_stage "$stage_name" 2>&1
        ) | tee "$stage_log"
        exit_code=${PIPESTATUS[0]}

        if [[ ! -f "$stage_log" ]]; then
            log_err "Failed to create stage log: $stage_log"
        fi

        if [[ $exit_code -ne 0 ]]; then
            log_err "$stage_name (exit code: $exit_code)"
            log_err "See $stage_log for details"
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
            log_err "See $stage_log for details"
            exit 1
        fi

        # Save hash and complete
        current_hash=$(stage_compute_hash "$stage_name" "${INPUTS[@]:-}" "$CONFIG_FILE" "$stage_file")
        stage_save_hash "$stage_name" "$current_hash"

        cleanup_openmvs_logs

        log_ok "$stage_name"
        log_endgroup
    done

    # Pipeline complete
    echo ""
    log "Pipeline complete"
}

################################################################################
# Discover stages and print remaining groups early
################################################################################

echo -n "::remaining_groups::Config,Tool Discovery"
STAGES_DIR="${STAGES_DIR:-$SCRIPT_DIR/stages}"
PIPELINE="${SFM_PIPELINE:-colmap-openmvs-sparse}"
while IFS= read -r stage_file; do
    display_name=$(grep -m1 '^DISPLAY_NAME=' "$stage_file" 2>/dev/null | cut -d= -f2 | tr -d '"' || basename "$stage_file" .stage.sh)
    echo -n ",$display_name"
done < <(find "${STAGES_DIR}/${PIPELINE}" -maxdepth 1 -name "*.stage.sh" | sort 2>/dev/null)
echo ""

# Run main; keep set -e active so failures inside main are not silently swallowed.
# Capture exit code without disabling errexit by using the ||  pattern.
exit_code=0
main || exit_code=$?
exit $exit_code
