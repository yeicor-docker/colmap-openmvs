#!/usr/bin/env bash
DISPLAY_NAME="OpenMVS SfM (CreateStructure)"
DEPENDENCIES=()
FILE_DEPENDENCIES=("${IMAGES_DIR}")
INPUTS=("${IMAGES_DIR}")
OUTPUTS=("${WORK_DIR}/openmvs/scene.sfm" "${WORK_DIR}/openmvs/scene.mvs")

run_stage_function() {
    cd "${WORK_DIR}"
    mkdir -p openmvs && cd openmvs
    # Auto-detect detector type only if not overridden via OPENMVS_CREATE_STRUCTURE_ARGS
    if ! echo " ${OPENMVS_CREATE_STRUCTURE_ARGS:-} " | grep -qE '[-]{1,2}t[ =]|detector-type[ =]'; then
        local detector_type="SIFTGPU"
        if ! command -v nvidia-smi &>/dev/null; then
            detector_type="SIFT"
        fi
        OPENMVS_CREATE_STRUCTURE_ARGS="-t ${detector_type} ${OPENMVS_CREATE_STRUCTURE_ARGS}"
    fi
    CreateStructure \
        -s "${IMAGES_DIR}" \
        -o scene.sfm \
        --export-mvs scene.mvs \
        --extract-colors 1 \
        ${OPENMVS_CREATE_STRUCTURE_ARGS}
}
