#!/usr/bin/env bash
DISPLAY_NAME="COLMAP Mesher (Poisson / Delaunay)"
DEPENDENCIES=("06_stereo_fusion")
FILE_DEPENDENCIES=("${WORK_DIR}/colmap/dense/fused.ply")
INPUTS=("${WORK_DIR}/colmap/dense/fused.ply")

_mesher="${COLMAP_MESHER:-poisson_mesher}"
if [[ "$_mesher" == "delaunay_mesher" ]]; then
    OUTPUTS=("${WORK_DIR}/colmap/dense/meshed-delaunay.ply" "${WORK_DIR}/colmap/dense/meshed.ply")
else
    OUTPUTS=("${WORK_DIR}/colmap/dense/meshed-poisson.ply" "${WORK_DIR}/colmap/dense/meshed.ply")
fi
unset _mesher

run_stage_function() {
    cd "${WORK_DIR}/colmap"
    local mesher="${COLMAP_MESHER:-poisson_mesher}"
    if [[ "$mesher" == "delaunay_mesher" ]]; then
        colmap delaunay_mesher \
            --input_path dense \
            --output_path dense/meshed-delaunay.ply \
            ${COLMAP_DELAUNAY_MESHER_ARGS}
        ln -sf meshed-delaunay.ply dense/meshed.ply
    else
        colmap poisson_mesher \
            --input_path dense/fused.ply \
            --output_path dense/meshed-poisson.ply \
            ${COLMAP_POISSON_MESHER_ARGS}
        ln -sf meshed-poisson.ply dense/meshed.ply
    fi
}
