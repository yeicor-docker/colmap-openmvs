#!/usr/bin/env bash
DISPLAY_NAME="COLMAP Stereo Fusion"
DEPENDENCIES=("05_patch_match_stereo")
FILE_DEPENDENCIES=()
INPUTS=()
OUTPUTS=()
while IFS= read -r component; do
    dense_dir=$(component_output_dir "${WORK_DIR}/colmap/dense" "$component")
    FILE_DEPENDENCIES+=("${dense_dir}/stereo/depth_maps")
    INPUTS+=("${dense_dir}/.patch_match_stereo.done")
    OUTPUTS+=("${dense_dir}/fused.ply")
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
        colmap stereo_fusion \
            --workspace_path "$dense_dir" \
            --workspace_format COLMAP \
            --input_type geometric \
            --output_path "${dense_dir}/fused.ply" \
            ${COLMAP_STEREO_FUSION_ARGS}
    done
}
