# Shared native build for all Flutter FFI platforms.
# Target: datachannel
#   Android/Linux (shared) → libdatachannel.so
#   Windows (shared)       → datachannel.dll
#   Apple (static)         → libdatachannel.a (via tool/build_libdatachannel_apple.sh)

cmake_minimum_required(VERSION 3.13)
project(scommconnector_native LANGUAGES C CXX)

# Allow target_link_libraries / target_link_options on targets from add_subdirectory
# (required when patching the libdatachannel target from this file on Android).
if(POLICY CMP0079)
  cmake_policy(SET CMP0079 NEW)
endif()

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

include(FetchContent)

option(SCOMM_BUILD_SHARED "Build libdatachannel as a shared library" ON)

set(SCOMM_NATIVE_ROOT "${CMAKE_CURRENT_SOURCE_DIR}")
set(SCOMM_PKG_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/..")
set(LIBDATACHANNEL_SRC "${SCOMM_PKG_ROOT}/third_party/libdatachannel")
set(MBEDTLS_SRC "${SCOMM_PKG_ROOT}/third_party/mbedtls")

# --- Mbed TLS (project-local or FetchContent) ---
if(NOT EXISTS "${MBEDTLS_SRC}/CMakeLists.txt")
  message(STATUS "third_party/mbedtls missing — fetching Mbed TLS v3.6.2")
  FetchContent_Declare(
    mbedtls_fetch
    GIT_REPOSITORY https://github.com/Mbed-TLS/mbedtls.git
    GIT_TAG v3.6.2
    GIT_SHALLOW TRUE
    GIT_SUBMODULES "framework"
    GIT_PROGRESS TRUE
  )
  FetchContent_GetProperties(mbedtls_fetch)
  if(NOT mbedtls_fetch_POPULATED)
    FetchContent_Populate(mbedtls_fetch)
  endif()
  set(MBEDTLS_SRC "${mbedtls_fetch_SOURCE_DIR}")
endif()

if(NOT EXISTS "${LIBDATACHANNEL_SRC}/CMakeLists.txt")
  message(FATAL_ERROR
    "third_party/libdatachannel is missing. Run:\n"
    "  git submodule update --init --recursive")
endif()

set(ENABLE_PROGRAMS OFF CACHE BOOL "" FORCE)
set(ENABLE_TESTING OFF CACHE BOOL "" FORCE)
set(MBEDTLS_FATAL_WARNINGS OFF CACHE BOOL "" FORCE)
# Flutter desktop sets CMAKE_INSTALL_PREFIX to $<TARGET_FILE_DIR:...>, which
# third-party install() rules treat as a literal path and fail. We only need
# the built shared library via bundled_libraries — neutralize vendored install.
set(INSTALL_MBEDTLS_HEADERS OFF CACHE BOOL "" FORCE)
set(DISABLE_PACKAGE_CONFIG_AND_INSTALL ON CACHE BOOL "" FORCE)
add_subdirectory("${MBEDTLS_SRC}" "${CMAKE_CURRENT_BINARY_DIR}/mbedtls")

foreach(_mbed_tgt IN ITEMS mbedcrypto mbedx509 mbedtls)
  if(TARGET ${_mbed_tgt})
    target_compile_definitions(${_mbed_tgt} PUBLIC
      MBEDTLS_USER_CONFIG_FILE="scomm_mbedtls_user_config.h"
    )
    target_include_directories(${_mbed_tgt} PUBLIC "${SCOMM_NATIVE_ROOT}")
  endif()
endforeach()

if(NOT TARGET MbedTLS::MbedTLS)
  add_library(MbedTLS::MbedTLS INTERFACE IMPORTED GLOBAL)
  target_link_libraries(MbedTLS::MbedTLS INTERFACE mbedtls mbedx509 mbedcrypto)
  target_include_directories(MbedTLS::MbedTLS INTERFACE "${MBEDTLS_SRC}/include")
endif()

# --- libdatachannel (data channels only) ---
set(NO_MEDIA ON CACHE BOOL "" FORCE)
set(NO_WEBSOCKET ON CACHE BOOL "" FORCE)
set(NO_EXAMPLES ON CACHE BOOL "" FORCE)
set(NO_TESTS ON CACHE BOOL "" FORCE)
set(USE_MBEDTLS ON CACHE BOOL "" FORCE)
set(BUILD_SHARED_DEPS_LIBS OFF CACHE BOOL "" FORCE)
set(BUILD_SHARED_LIBS ${SCOMM_BUILD_SHARED} CACHE BOOL "" FORCE)

add_subdirectory(
  "${LIBDATACHANNEL_SRC}"
  "${CMAKE_CURRENT_BINARY_DIR}/libdatachannel"
)

# CMake regenerates cmake_install.cmake during the generate phase, so overwrite
# vendored install scripts on every build (before Flutter's INSTALL step).
set(_scomm_empty_install "${SCOMM_NATIVE_ROOT}/empty_install.cmake")
add_custom_target(scomm_neuter_native_install ALL
  COMMAND "${CMAKE_COMMAND}" -E copy_if_different
    "${_scomm_empty_install}"
    "${CMAKE_CURRENT_BINARY_DIR}/mbedtls/cmake_install.cmake"
  COMMAND "${CMAKE_COMMAND}" -E copy_if_different
    "${_scomm_empty_install}"
    "${CMAKE_CURRENT_BINARY_DIR}/libdatachannel/cmake_install.cmake"
  COMMENT "Disable mbedtls/libdatachannel install rules for Flutter bundling"
  VERBATIM
)

if(NOT TARGET datachannel)
  message(FATAL_ERROR "libdatachannel did not create target 'datachannel'")
endif()

set_target_properties(datachannel PROPERTIES OUTPUT_NAME "datachannel")
add_dependencies(scomm_neuter_native_install datachannel)

if(ANDROID)
  # Android 15 16 KB page size
  target_link_options(datachannel PRIVATE "-Wl,-z,max-page-size=16384")
endif()

message(STATUS "scommconnector: datachannel ready (shared=${SCOMM_BUILD_SHARED}, Mbed TLS)")
