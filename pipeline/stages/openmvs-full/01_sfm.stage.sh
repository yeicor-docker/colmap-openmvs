#!/usr/bin/env bash
DISPLAY_NAME="OpenMVS SfM (CreateStructure)"
DEPENDENCIES=()
FILE_DEPENDENCIES=("${IMAGES_DIR}")
INPUTS=("${IMAGES_DIR}")
OUTPUTS=("${WORK_DIR}/openmvs/scene.sfm" "${WORK_DIR}/openmvs/scene.mvs")

run_stage_function() {
    cd "${WORK_DIR}"
    mkdir -p openmvs && cd openmvs
    # Auto-detect: use SIFTGPU (default) when NVIDIA GPU is available,
    # fall back to CPU-based SIFT otherwise
    local detector_type="SIFTGPU"
    if ! command -v nvidia-smi &>/dev/null; then
        detector_type="SIFT"
    fi
    CreateStructure \
        -s "${IMAGES_DIR}" \
        -o scene.sfm \
        --export-mvs scene.mvs \
        --extract-colors 1 \
        -t "${detector_type}" \
        ${OPENMVS_CREATE_STRUCTURE_ARGS}
}
