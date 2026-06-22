#!/usr/bin/env bash
DISPLAY_NAME="Dense Mesh"
DEPENDENCIES=("09_densify")
FILE_DEPENDENCIES=("${WORK_DIR}/openmvs/scene_dense.mvs")
INPUTS=("${WORK_DIR}/openmvs/scene_dense.mvs")
OUTPUTS=("${WORK_DIR}/openmvs/scene_dense_mesh.ply")

run_stage_function() {
    cd "${WORK_DIR}/openmvs"
    ReconstructMesh scene_dense.mvs -o scene_dense_mesh.ply ${OPENMVS_RECONSTRUCT_MESH_DENSE_ARGS}
}
