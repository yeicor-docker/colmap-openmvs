# Copy upstream port files except portfile.cmake
file(COPY "${VCPKG_ROOT_DIR}/ports/suitesparse-config/" DESTINATION "${CMAKE_CURRENT_LIST_DIR}" PATTERN "portfile.cmake" EXCLUDE)

# Patch upstream portfile.cmake (support and optimize for more platforms, not just native at build time)
# https://github.com/OpenMathLib/OpenBLAS#support-for-multiple-targets-in-a-single-library
file(READ "${VCPKG_ROOT_DIR}/ports/suitesparse-config/portfile.cmake" upstream_content)
string(REPLACE "-DSUITESPARSE_DEMOS=OFF" "-DSUITESPARSE_DEMOS=OFF -DCMAKE_EXE_LINKER_FLAGS=\"-lm\" -DCMAKE_SHARED_LINKER_FLAGS=\"-lm\"" upstream_content "${upstream_content}")
file(WRITE "${CMAKE_CURRENT_LIST_DIR}/portfile_upstream_patched.cmake" "${upstream_content}")

# Include the upstream portfile.cmake
include("${CMAKE_CURRENT_LIST_DIR}/portfile_upstream_patched.cmake")
