
if(PORT MATCHES "suitesparse-")
    set(VCPKG_C_FLAGS "-lm")
    set(VCPKG_CXX_FLAGS "-lm")
    set(VCPKG_LINKER_FLAGS "-lm")
endif()
