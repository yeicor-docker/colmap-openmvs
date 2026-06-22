#!/usr/bin/env bash
DISPLAY_NAME="Dense Texture"
DEPENDENCIES=("11_dense_refine")
FILE_DEPENDENCIES=("${WORK_DIR}/openmvs/scene_dense.mvs")
INPUTS=("${WORK_DIR}/openmvs/scene_dense.mvs" "${WORK_DIR}/openmvs/scene_dense_mesh_refined.ply")
OUTPUTS=("${WORK_DIR}/openmvs/scene_dense_mesh_refined_textured.ply")

run_stage_function() {
    cd "${WORK_DIR}/openmvs"
    TextureMesh -i scene_dense.mvs -m scene_dense_mesh_refined.ply -o scene_dense_mesh_refined_textured.ply ${OPENMVS_TEXTURE_MESH_DENSE_ARGS}
}
