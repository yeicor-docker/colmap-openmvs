#!/usr/bin/env bash
DISPLAY_NAME="COLMAP Feature Matching"
DEPENDENCIES=("01_colmap_feature_extraction")
INPUTS=("${WORK_DIR}/colmap/.feature_extraction.done" "${WORK_DIR}/colmap/database.db")
OUTPUTS=("${WORK_DIR}/colmap/.feature_matching.done")  # It cannot be database.db as it is also an input

run_stage_function() {
    cd "${WORK_DIR}/colmap"
    colmap ${COLMAP_MATCHER:-vocab_tree_matcher} \
        --database_path database.db \
        ${COLMAP_MATCHER_ARGS}
    touch .feature_matching.done
}
