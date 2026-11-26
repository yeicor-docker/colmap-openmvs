#!/usr/bin/env bash
DISPLAY_NAME="COLMAP Patch Match Stereo"
DEPENDENCIES=("04_undistortion")
FILE_DEPENDENCIES=()
INPUTS=()
OUTPUTS=()
while IFS= read -r component; do
    dense_dir=$(component_output_dir "${WORK_DIR}/colmap/dense" "$component")
    FILE_DEPENDENCIES+=("${dense_dir}/images")
    INPUTS+=("${dense_dir}/images" "${dense_dir}/sparse")
    OUTPUTS+=("${dense_dir}/.patch_match_stereo.done")
done < <(active_component_ids)

run_stage_function() {
    cd "${WORK_DIR}/colmap"
    local components=()
    mapfile -t components < <(active_component_ids)
    local total=${#components[@]}

    _patch_match_component() {
        local dense_dir="$1"
        colmap patch_match_stereo \
            --workspace_path "$dense_dir" \
            --workspace_format COLMAP \
            --PatchMatchStereo.geom_consistency true \
            ${COLMAP_PATCH_MATCH_STEREO_ARGS}
        touch "${dense_dir}/.patch_match_stereo.done"
    }

    local i component dense_dir
    for i in "${!components[@]}"; do
        component="${components[$i]}"
        dense_dir=$(component_output_dir "${WORK_DIR}/colmap/dense" "$component")
        run_component "$component" "$component" "$((i + 1))" "$total" "$dense_dir" \
            _patch_match_component "$dense_dir" || return 1
    done
    require_component_success "$total"
}
