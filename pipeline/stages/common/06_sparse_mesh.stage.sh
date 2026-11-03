#!/usr/bin/env bash
DISPLAY_NAME="Sparse Mesh"
DEPENDENCIES=()
FILE_DEPENDENCIES=()
INPUTS=()
OUTPUTS=()
while IFS= read -r scene_dir; do
    FILE_DEPENDENCIES+=("${scene_dir}/scene.mvs")
    INPUTS+=("${scene_dir}/scene.mvs")
    OUTPUTS+=("${scene_dir}/scene_mesh.ply")
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
            ReconstructMesh scene.mvs -o scene_mesh.ply ${OPENMVS_RECONSTRUCT_MESH_ARGS}
        )
    done
}
