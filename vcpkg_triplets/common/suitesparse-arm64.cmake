
if(PORT MATCHES "suitesparse-")
  set(VCPKG_C_FLAGS "-Wl,--no-as-needed -lm -Wl,--as-needed")
  set(VCPKG_CXX_FLAGS "-Wl,--no-as-needed -lm -Wl,--as-needed")
  set(VCPKG_LINKER_FLAGS "-Wl,--no-as-needed -lm -Wl,--as-needed")
endif()
