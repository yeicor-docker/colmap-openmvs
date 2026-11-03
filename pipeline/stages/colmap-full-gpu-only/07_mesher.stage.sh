#!/usr/bin/env bash
DISPLAY_NAME="COLMAP Mesher (Poisson / Delaunay)"
DEPENDENCIES=("06_stereo_fusion")
FILE_DEPENDENCIES=()
INPUTS=()
OUTPUTS=()
_mesher="${COLMAP_MESHER:-poisson_mesher}"
while IFS= read -r component; do
    dense_dir=$(component_output_dir "${WORK_DIR}/colmap/dense" "$component")
    FILE_DEPENDENCIES+=("${dense_dir}/fused.ply")
    INPUTS+=("${dense_dir}/fused.ply")
    if [[ "$_mesher" == "delaunay_mesher" ]]; then
        OUTPUTS+=("${dense_dir}/meshed-delaunay.ply" "${dense_dir}/meshed.ply")
    else
        OUTPUTS+=("${dense_dir}/meshed-poisson.ply" "${dense_dir}/meshed.ply")
    fi
done < <(component_ids)
unset _mesher

run_stage_function() {
    cd "${WORK_DIR}/colmap"
    local mesher="${COLMAP_MESHER:-poisson_mesher}"
    local components=()
    mapfile -t components < <(component_ids)
    local total=${#components[@]}
    local i component dense_dir
    for i in "${!components[@]}"; do
        component="${components[$i]}"
        log_component_header "$component" "$((i + 1))" "$total"
        dense_dir=$(component_output_dir "${WORK_DIR}/colmap/dense" "$component")
        if [[ "$mesher" == "delaunay_mesher" ]]; then
            colmap delaunay_mesher \
                --input_path "$dense_dir" \
                --output_path "${dense_dir}/meshed-delaunay.ply" \
                ${COLMAP_DELAUNAY_MESHER_ARGS}
            ln -sf meshed-delaunay.ply "${dense_dir}/meshed.ply"
        else
            colmap poisson_mesher \
                --input_path "${dense_dir}/fused.ply" \
                --output_path "${dense_dir}/meshed-poisson.ply" \
                ${COLMAP_POISSON_MESHER_ARGS}
            ln -sf meshed-poisson.ply "${dense_dir}/meshed.ply"
        fi
    done
}
