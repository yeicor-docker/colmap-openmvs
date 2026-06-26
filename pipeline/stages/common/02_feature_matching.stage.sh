#!/usr/bin/env bash
DISPLAY_NAME="COLMAP Feature Matching"
DEPENDENCIES=("01_feature_extraction")
INPUTS=("${WORK_DIR}/colmap/.feature_extraction.done")
OUTPUTS=("${WORK_DIR}/colmap/.feature_matching.done")

run_stage_function() {
    cd "${WORK_DIR}/colmap"
    local matcher="${COLMAP_MATCHER:-vocab_tree_matcher}"
    local matcher_args=""
    case "$matcher" in
        exhaustive_matcher) matcher_args="${COLMAP_EXHAUSTIVE_MATCHER_ARGS:-}" ;;
        sequential_matcher) matcher_args="${COLMAP_SEQUENTIAL_MATCHER_ARGS:-}" ;;
        spatial_matcher)    matcher_args="${COLMAP_SPATIAL_MATCHER_ARGS:-}" ;;
        transitive_matcher) matcher_args="${COLMAP_TRANSITIVE_MATCHER_ARGS:-}" ;;
        vocab_tree_matcher) matcher_args="${COLMAP_VOCAB_TREE_MATCHER_ARGS:-}" ;;
    esac
    colmap "$matcher" \
        --database_path database.db \
        $matcher_args
    touch .feature_matching.done
}
