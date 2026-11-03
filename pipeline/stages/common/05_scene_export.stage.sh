#!/usr/bin/env bash
DISPLAY_NAME="COLMAP to OpenMVS Export"
DEPENDENCIES=("04_undistortion")
INPUTS=("${WORK_DIR}/colmap/dense")
OUTPUTS=()
while IFS= read -r component; do
    OUTPUTS+=("$(component_output_dir "${WORK_DIR}/openmvs" "$component")/scene.mvs")
done < <(component_ids)

run_stage_function() {
    cd "${WORK_DIR}"
    mkdir -p openmvs

    local components=()
    mapfile -t components < <(component_ids)
    local total=${#components[@]}
    if [[ $total -eq 0 ]]; then
        log_err "No COLMAP sparse components found in sparse/"
        return 1
    fi

    local i component dense_dir output_dir
    for i in "${!components[@]}"; do
        component="${components[$i]}"
        log_component_header "$component" "$((i + 1))" "$total"
        dense_dir=$(component_output_dir "${WORK_DIR}/colmap/dense" "$component")
        output_dir=$(component_output_dir "${WORK_DIR}/openmvs" "$component")
        mkdir -p "$output_dir"
        InterfaceCOLMAP \
            -i "$dense_dir" \
            -o "${output_dir}/scene.mvs" \
            ${OPENMVS_INTERFACE_COLMAP_ARGS}
    done
}
