#!/usr/bin/env bash
DISPLAY_NAME="Extract Keyframes from Videos"
DEPENDENCIES=()
INPUTS=("${WORK_DIR}/videos")
OUTPUTS=("${IMAGES_DIR}/.keyframes_extracted.done")

run_stage_function() {
    local videos_dir="${WORK_DIR}/videos"
    if [[ ! -d "$videos_dir" ]]; then
        log "videos/ directory not found, nothing to extract"
        touch "${IMAGES_DIR}/.keyframes_extracted.done"
        return 0
    fi

    # Collect video files (exclude directories)
    local video_files=()
    while IFS= read -r -d '' f; do
        video_files+=("$f")
    done < <(find "$videos_dir" -maxdepth 1 -type f -print0 2>/dev/null || true)

    if [[ ${#video_files[@]} -eq 0 ]]; then
        log "videos/ directory is empty, nothing to extract"
        return 0
    fi

    mkdir -p "${IMAGES_DIR}"

    local video
    for video in "${video_files[@]}"; do
        local basename
        basename=$(basename "$video")
        local video_name="${basename%.*}"

        # Check if frames for this video already exist and are up-to-date
        local video_mtime
        video_mtime=$(stat -c '%Y' "$video")
        local oldest_frame_mtime=9999999999
        local has_frames=0
        for f in "${IMAGES_DIR}/${video_name}_frame_"*; do
            if [[ -f "$f" ]]; then
                has_frames=1
                local mtime
                mtime=$(stat -c '%Y' "$f")
                (( mtime < oldest_frame_mtime )) && oldest_frame_mtime=$mtime
            fi
        done

        if [[ $has_frames -eq 1 ]] && [[ $oldest_frame_mtime -ge $video_mtime ]]; then
            log "⚠ Warning: Frames already up-to-date for: $basename (video unchanged), skipping extraction"
            continue
        fi

        # Extract frames to a temporary directory unique to this video
        local temp_dir="${WORK_DIR}/tmp/keyframes/${video_name}"
        rm -rf "$temp_dir"
        mkdir -p "$temp_dir"

        log "Extracting keyframes from: $basename"
        # Auto-detect detector type only if not overridden via EXTRACT_KEYFRAMES_ARGS
        if ! echo " ${EXTRACT_KEYFRAMES_ARGS:-} " | grep -qE '[-]{1,2}t[ =]|detector-type[ =]'; then
            local detector_type="SIFTGPU"
            if ! command -v nvidia-smi &>/dev/null; then
                detector_type="SIFT"
            fi
            EXTRACT_KEYFRAMES_ARGS="-t ${detector_type} ${EXTRACT_KEYFRAMES_ARGS}"
        fi
        ExtractKeyframes \
            -i "$video" \
            -d "$temp_dir" \
            ${EXTRACT_KEYFRAMES_ARGS}

        # Rename and convert extracted frames (removes temp files)
        local frame_idx=1
        set +x 2>/dev/null  # Suppress verbose tracing inside per-frame loop
        while IFS= read -r -d '' frame; do
            local ext="${frame##*.}"
            local ext_lower
            ext_lower=$(echo "$ext" | tr '[:upper:]' '[:lower:]')

            # Pad frame index to 4 digits for consistent sorting
            local dest_name="${video_name}_frame_$(printf '%06d' $frame_idx)"

            if [[ "$ext_lower" == "jxl" ]]; then
                # JXL is not supported by COLMAP → convert to JPEG
                log "  converting: ${dest_name}.jpg"
                djxl "$frame" "${IMAGES_DIR}/${dest_name}.jpg" >/dev/null 2>&1 || {
                    log_err "  failed to convert: $frame"
                    return 1
                }
            else
                # Copy non-JXL formats as-is with renamed filename
                log "  copying: ${dest_name}.${ext}"
                cp "$frame" "${IMAGES_DIR}/${dest_name}.${ext}"
            fi

            ((frame_idx++))
        done < <(find "$temp_dir" -type f -print0 | sort -z)
        set -x 2>/dev/null  # Re-enable verbose tracing

        # Cleanup temporary extraction directory
        rm -rf "$temp_dir"

        log "  → extracted $((frame_idx-1)) frames from: $basename"
    done

    if [[ "${EXTRACT_KEYFRAMES_REMOVE_VIDEOS:-false}" == "true" ]]; then
        log "Removing processed video files from: $videos_dir"
        rm -f "${video_files[@]}"
    fi

    touch "${IMAGES_DIR}/.keyframes_extracted.done"
}
