#!/usr/bin/env bash
DISPLAY_NAME="Densify"
DEPENDENCIES=()
FILE_DEPENDENCIES=()
INPUTS=()
OUTPUTS=()
while IFS= read -r scene_dir; do
    FILE_DEPENDENCIES+=("${scene_dir}/scene.mvs")
    INPUTS+=("${scene_dir}/scene.mvs")
    OUTPUTS+=("${scene_dir}/scene_dense.mvs")
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
            DensifyPointCloud scene.mvs -o scene_dense.mvs ${OPENMVS_DENSIFY_POINT_CLOUD_ARGS}
        )
    done
}
