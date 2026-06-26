#!/usr/bin/env bash
DISPLAY_NAME="COLMAP Patch Match Stereo"
DEPENDENCIES=("04_undistortion")
FILE_DEPENDENCIES=("${WORK_DIR}/colmap/dense/images")
INPUTS=("${WORK_DIR}/colmap/dense")
OUTPUTS=("${WORK_DIR}/colmap/dense/.patch_match_stereo.done")

run_stage_function() {
    cd "${WORK_DIR}/colmap"
    colmap patch_match_stereo \
        --workspace_path dense \
        --workspace_format COLMAP \
        --PatchMatchStereo.geom_consistency true \
        ${COLMAP_PATCH_MATCH_STEREO_ARGS}
    touch dense/.patch_match_stereo.done
}
