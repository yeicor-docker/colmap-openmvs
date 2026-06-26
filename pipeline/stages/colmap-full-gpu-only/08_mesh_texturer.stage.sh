#!/usr/bin/env bash
DISPLAY_NAME="COLMAP Mesh Texturer"
DEPENDENCIES=("07_mesher")
FILE_DEPENDENCIES=("${WORK_DIR}/colmap/dense/meshed.ply")
INPUTS=("${WORK_DIR}/colmap/dense/meshed.ply" "${WORK_DIR}/colmap/dense")
OUTPUTS=("${WORK_DIR}/colmap/dense/textured")

run_stage_function() {
    cd "${WORK_DIR}/colmap"
    colmap mesh_texturer \
        --workspace_path dense \
        --input_path dense/meshed.ply \
        --output_path dense/textured \
        ${COLMAP_MESH_TEXTURER_ARGS}
}
