#!/usr/bin/env bash
DISPLAY_NAME="Dense Refine"
DEPENDENCIES=("10_dense_mesh")
FILE_DEPENDENCIES=("${WORK_DIR}/openmvs/scene_dense.mvs")
INPUTS=("${WORK_DIR}/openmvs/scene_dense.mvs" "${WORK_DIR}/openmvs/scene_dense_mesh.ply")
OUTPUTS=("${WORK_DIR}/openmvs/scene_dense_mesh_refined.ply")

run_stage_function() {
    cd "${WORK_DIR}/openmvs"
    RefineMesh -i scene_dense.mvs -m scene_dense_mesh.ply -o scene_dense_mesh_refined.ply ${OPENMVS_REFINE_MESH_DENSE_ARGS}
}
