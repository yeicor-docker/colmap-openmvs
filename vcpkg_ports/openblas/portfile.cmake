# Copy upstream port files except portfile.cmake
file(COPY "${VCPKG_ROOT_DIR}/ports/openblas/" DESTINATION "${CMAKE_CURRENT_LIST_DIR}" PATTERN "portfile.cmake" EXCLUDE)

# Patch upstream portfile.cmake (support and optimize for more platforms, not just native at build time)
# https://github.com/OpenMathLib/OpenBLAS#support-for-multiple-targets-in-a-single-library
file(READ "${VCPKG_ROOT_DIR}/ports/openblas/portfile.cmake" upstream_content)
set(ARCH_TARGET "P2")
if(CMAKE_HOST_PROCESSOR MATCHES "arm64|aarch64")
  set(ARCH_TARGET "ARMV8")
endif()
string(REPLACE "-DBUILD_TESTING=OFF" "-DBUILD_TESTING=OFF -DDYNAMIC_ARCH=ON -DDYNAMIC_OLDER=ON -DTARGET=${ARCH_TARGET}" upstream_content "${upstream_content}")
file(WRITE "${CMAKE_CURRENT_LIST_DIR}/portfile_upstream_patched.cmake" "${upstream_content}")

# Include the upstream portfile.cmake
include("${CMAKE_CURRENT_LIST_DIR}/portfile_upstream_patched.cmake")
