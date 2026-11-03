#!/usr/bin/env bash
DISPLAY_NAME="Dense Texture"
DEPENDENCIES=("11_dense_refine")
FILE_DEPENDENCIES=()
INPUTS=()
OUTPUTS=()
while IFS= read -r scene_dir; do
    FILE_DEPENDENCIES+=("${scene_dir}/scene_dense.mvs")
    INPUTS+=("${scene_dir}/scene_dense.mvs" "${scene_dir}/scene_dense_mesh_refined.ply")
    OUTPUTS+=("${scene_dir}/scene_dense_mesh_refined_textured.ply")
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
            TextureMesh -i scene_dense.mvs -m scene_dense_mesh_refined.ply -o scene_dense_mesh_refined_textured.ply ${OPENMVS_TEXTURE_MESH_ARGS}
        )
    done
}
