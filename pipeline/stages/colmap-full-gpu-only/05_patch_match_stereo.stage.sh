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
done < <(component_ids)

run_stage_function() {
    cd "${WORK_DIR}/colmap"
    local components=()
    mapfile -t components < <(component_ids)
    local total=${#components[@]}
    local i component dense_dir
    for i in "${!components[@]}"; do
        component="${components[$i]}"
        log_component_header "$component" "$((i + 1))" "$total"
        dense_dir=$(component_output_dir "${WORK_DIR}/colmap/dense" "$component")
        colmap patch_match_stereo \
            --workspace_path "$dense_dir" \
            --workspace_format COLMAP \
            --PatchMatchStereo.geom_consistency true \
            ${COLMAP_PATCH_MATCH_STEREO_ARGS}
        touch "${dense_dir}/.patch_match_stereo.done"
    done
}
