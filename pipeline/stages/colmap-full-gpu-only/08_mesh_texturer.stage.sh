#!/usr/bin/env bash
DISPLAY_NAME="COLMAP Mesh Texturer"
DEPENDENCIES=("07_mesher")
FILE_DEPENDENCIES=()
INPUTS=()
OUTPUTS=()
while IFS= read -r component; do
    dense_dir=$(component_output_dir "${WORK_DIR}/colmap/dense" "$component")
    FILE_DEPENDENCIES+=("${dense_dir}/meshed.ply")
    INPUTS+=("${dense_dir}/meshed.ply")
    OUTPUTS+=("${dense_dir}/textured")
done < <(active_component_ids)

run_stage_function() {
    cd "${WORK_DIR}/colmap"
    local components=()
    mapfile -t components < <(active_component_ids)
    local total=${#components[@]}
    local i component dense_dir
    for i in "${!components[@]}"; do
        component="${components[$i]}"
        dense_dir=$(component_output_dir "${WORK_DIR}/colmap/dense" "$component")
        run_component "$component" "$component" "$((i + 1))" "$total" "$dense_dir" \
            colmap mesh_texturer \
                --workspace_path "$dense_dir" \
                --input_path "${dense_dir}/meshed.ply" \
                --output_path "${dense_dir}/textured" \
                ${COLMAP_MESH_TEXTURER_ARGS} || return 1
    done
    require_component_success "$total"
}
