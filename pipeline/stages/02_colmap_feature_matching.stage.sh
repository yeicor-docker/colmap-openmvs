#!/usr/bin/env bash
DISPLAY_NAME="COLMAP Feature Matching"
DEPENDENCIES=("01_colmap_feature_extraction")
INPUTS=("${WORK_DIR}/colmap/database.db")
OUTPUTS=("${WORK_DIR}/colmap/database.db.matches")

run_stage_function() {
    cd "${WORK_DIR}/colmap"
    colmap ${COLMAP_MATCHER:-vocab_tree_matcher} \
        --database_path database.db \
        ${COLMAP_MATCHER_ARGS}
    touch database.db.matches
}
