#!/usr/bin/env bash
DISPLAY_NAME="COLMAP Feature Extraction"
DEPENDENCIES=()
INPUTS=("${IMAGES_DIR}")
OUTPUTS=("${WORK_DIR}/colmap/.feature_extraction.done")

run_stage_function() {
    cd "${WORK_DIR}"
    mkdir -p colmap && cd colmap
    local camera_args=""
    if is_true "${SINGLE_CAMERA:-0}" && ! echo " ${COLMAP_FEATURE_EXTRACTOR_ARGS:-} " | grep -qE -- '--?ImageReader[._]single_camera([[:space:]=]|$)'; then
        camera_args="--ImageReader.single_camera 1"
    fi
    colmap feature_extractor \
        --image_path "${IMAGES_DIR}" \
        --database_path database.db \
        ${camera_args} \
        ${COLMAP_FEATURE_EXTRACTOR_ARGS}
    touch .feature_extraction.done
}
