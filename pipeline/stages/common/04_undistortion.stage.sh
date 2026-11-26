#!/usr/bin/env bash
DISPLAY_NAME="COLMAP Undistortion"
DEPENDENCIES=("03_mapping")
INPUTS=("${WORK_DIR}/colmap/sparse")
OUTPUTS=()
while IFS= read -r component; do
    OUTPUTS+=("$(component_output_dir "${WORK_DIR}/colmap/dense" "$component")/images")
done < <(active_component_ids)

run_stage_function() {
    cd "${WORK_DIR}/colmap"
    mkdir -p dense

    local components=()
    mapfile -t components < <(active_component_ids)
    local total=${#components[@]}

    local i component output_dir
    for i in "${!components[@]}"; do
        component="${components[$i]}"
        output_dir=$(component_output_dir "${WORK_DIR}/colmap/dense" "$component")
        run_component "$component" "$component" "$((i + 1))" "$total" "${WORK_DIR}/colmap" \
            colmap image_undistorter \
                --image_path "${IMAGES_DIR}" \
                --input_path "sparse/${component}" \
                --output_path "$output_dir" \
                --output_type COLMAP \
                ${COLMAP_IMAGE_UNDISTORTER_ARGS} || return 1
    done
    require_component_success "$total"
}
