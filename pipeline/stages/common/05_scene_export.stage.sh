#!/usr/bin/env bash
DISPLAY_NAME="COLMAP to OpenMVS Export"
DEPENDENCIES=("04_undistortion")
INPUTS=("${WORK_DIR}/colmap/dense")
OUTPUTS=()
while IFS= read -r component; do
    OUTPUTS+=("$(component_output_dir "${WORK_DIR}/openmvs" "$component")/scene.mvs")
done < <(active_component_ids)

run_stage_function() {
    cd "${WORK_DIR}"
    mkdir -p openmvs

    local components=()
    mapfile -t components < <(active_component_ids)
    local total=${#components[@]}

    local i component dense_dir output_dir
    for i in "${!components[@]}"; do
        component="${components[$i]}"
        dense_dir=$(component_output_dir "${WORK_DIR}/colmap/dense" "$component")
        output_dir=$(component_output_dir "${WORK_DIR}/openmvs" "$component")
        mkdir -p "$output_dir"
        local camera_args=""
        if is_true "${SINGLE_CAMERA:-0}" && ! echo " ${OPENMVS_INTERFACE_COLMAP_ARGS:-} " | grep -qE -- '--common-intrinsics([[:space:]=]|$)'; then
            camera_args="--common-intrinsics 1"
        fi
        run_component "$component" "$component" "$((i + 1))" "$total" "${WORK_DIR}" \
            InterfaceCOLMAP \
                -i "$dense_dir" \
                -o "${output_dir}/scene.mvs" \
                ${camera_args} \
                ${OPENMVS_INTERFACE_COLMAP_ARGS} || return 1
    done
    require_component_success "$total"
}
