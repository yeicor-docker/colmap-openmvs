#!/usr/bin/env bash
DISPLAY_NAME="Sparse Mesh"
DEPENDENCIES=()
FILE_DEPENDENCIES=("${WORK_DIR}/openmvs/scene.mvs")
INPUTS=("${WORK_DIR}/openmvs/scene.mvs")
OUTPUTS=("${WORK_DIR}/openmvs/scene_mesh.ply")

run_stage_function() {
    cd "${WORK_DIR}/openmvs"
    ReconstructMesh scene.mvs -o scene_mesh.ply ${OPENMVS_RECONSTRUCT_MESH_SPARSE_ARGS}
}
