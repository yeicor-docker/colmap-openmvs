#!/usr/bin/env bash
DISPLAY_NAME="Densify"
DEPENDENCIES=()
FILE_DEPENDENCIES=("${WORK_DIR}/openmvs/scene.mvs")
INPUTS=("${WORK_DIR}/openmvs/scene.mvs")
OUTPUTS=("${WORK_DIR}/openmvs/scene_dense.mvs")

run_stage_function() {
    cd "${WORK_DIR}/openmvs"
    DensifyPointCloud scene.mvs -o scene_dense.mvs ${OPENMVS_DENSIFY_POINT_CLOUD_ARGS}
}
