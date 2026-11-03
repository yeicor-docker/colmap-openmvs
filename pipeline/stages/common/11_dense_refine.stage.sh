#!/usr/bin/env bash
DISPLAY_NAME="Dense Refine"
DEPENDENCIES=("10_dense_mesh")
FILE_DEPENDENCIES=()
INPUTS=()
OUTPUTS=()
while IFS= read -r scene_dir; do
    FILE_DEPENDENCIES+=("${scene_dir}/scene_dense.mvs")
    INPUTS+=("${scene_dir}/scene_dense.mvs" "${scene_dir}/scene_dense_mesh.ply")
    OUTPUTS+=("${scene_dir}/scene_dense_mesh_refined.ply")
done < <(openmvs_scene_dirs)

run_stage_function() {
    local scene_dirs=()
    mapfile -t scene_dirs < <(openmvs_scene_dirs)
    local total=${#scene_dirs[@]}
    local i scene_dir
    for i in "${!scene_dirs[@]}"; do
        scene_dir="${scene_dirs[$i]}"
        log_component_header "$(basename "$scene_dir")" "$((i + 1))" "$total"
        (
            cd "$scene_dir"
            RefineMesh -i scene_dense.mvs -m scene_dense_mesh.ply -o scene_dense_mesh_refined.ply ${OPENMVS_REFINE_MESH_ARGS}
        )
    done
}
