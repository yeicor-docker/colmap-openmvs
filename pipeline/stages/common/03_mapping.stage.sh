#!/usr/bin/env bash
DISPLAY_NAME="COLMAP Mapping"
DEPENDENCIES=("02_feature_matching")
INPUTS=("${WORK_DIR}/colmap/.feature_matching.done")
OUTPUTS=("${WORK_DIR}/colmap/sparse/0/cameras.bin")

run_stage_function() {
    cd "${WORK_DIR}/colmap"
    mkdir -p sparse

    local mapper="${COLMAP_MAPPER:-global_mapper}"

    if [[ "$mapper" == "global_mapper" ]] && [[ "${COLMAP_SKIP_VIEW_GRAPH_CALIBRATOR:-0}" != "1" ]]; then
        # Calibrate intrinsics from the view graph to improve global mapper
        # results when less than 50% of cameras have prior focal lengths.
        # See https://colmap.github.io/faq.html#improve-global-mapper-results
        #
        # view_graph_calibrator modifies the database in-place, so we work
        # on a copy to preserve the original for other mappers.
        log "Calibrating view graph intrinsics for global mapper..."
        cp database.db database_global.db
        colmap view_graph_calibrator \
            --database_path database_global.db \
            ${COLMAP_VIEW_GRAPH_CALIBRATOR_ARGS}
        colmap global_mapper \
            --image_path "${IMAGES_DIR}" \
            --database_path database_global.db \
            --output_path sparse \
            ${COLMAP_MAPPER_ARGS}
    else
        colmap ${mapper} \
            --image_path "${IMAGES_DIR}" \
            --database_path database.db \
            --output_path sparse \
            ${COLMAP_MAPPER_ARGS}
    fi
}
