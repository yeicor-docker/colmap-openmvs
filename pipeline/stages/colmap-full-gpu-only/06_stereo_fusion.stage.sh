#!/usr/bin/env bash
DISPLAY_NAME="COLMAP Stereo Fusion"
DEPENDENCIES=("05_patch_match_stereo")
FILE_DEPENDENCIES=("${WORK_DIR}/colmap/dense/stereo/depth_maps")
INPUTS=("${WORK_DIR}/colmap/dense/.patch_match_stereo.done")
OUTPUTS=("${WORK_DIR}/colmap/dense/fused.ply")

run_stage_function() {
    cd "${WORK_DIR}/colmap"
    colmap stereo_fusion \
        --workspace_path dense \
        --workspace_format COLMAP \
        --input_type geometric \
        --output_path dense/fused.ply \
        ${COLMAP_STEREO_FUSION_ARGS}
}
