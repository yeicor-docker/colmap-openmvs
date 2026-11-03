#!/usr/bin/env bash
DISPLAY_NAME="COLMAP Undistortion"
DEPENDENCIES=("03_mapping")
INPUTS=("${WORK_DIR}/colmap/sparse")
OUTPUTS=()
while IFS= read -r component; do
    OUTPUTS+=("$(component_output_dir "${WORK_DIR}/colmap/dense" "$component")/images")
done < <(component_ids)

run_stage_function() {
    cd "${WORK_DIR}/colmap"
    mkdir -p dense

    local components=()
    mapfile -t components < <(component_ids)
    local total=${#components[@]}
    if [[ $total -eq 0 ]]; then
        log_err "No COLMAP sparse components found in sparse/"
        return 1
    fi

    local i component output_dir
    for i in "${!components[@]}"; do
        component="${components[$i]}"
        log_component_header "$component" "$((i + 1))" "$total"
        output_dir=$(component_output_dir "${WORK_DIR}/colmap/dense" "$component")
        colmap image_undistorter \
            --image_path "${IMAGES_DIR}" \
            --input_path "sparse/${component}" \
            --output_path "$output_dir" \
            --output_type COLMAP \
            ${COLMAP_IMAGE_UNDISTORTER_ARGS}
    done
}
