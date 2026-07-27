# Shared native build for all Flutter FFI platforms.
# Target: datachannel
#   Android/Linux (shared) → libdatachannel.so
#   Windows (shared)       → datachannel.dll
#   Apple (static)         → libdatachannel.a (via tool/build_libdatachannel_apple.sh)

cmake_minimum_required(VERSION 3.19)
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

# Flutter `git:` deps do not init submodules (pub-cache). Fall back to FetchContent.
# Keep in sync with .gitmodules pin for third_party/libdatachannel.
set(SCOMM_LIBDATACHANNEL_GIT_TAG "44d33ca70ab95e814dd9afe614adb4246479f4e2")
if(NOT EXISTS "${LIBDATACHANNEL_SRC}/CMakeLists.txt")
  message(STATUS
    "third_party/libdatachannel missing — fetching ${SCOMM_LIBDATACHANNEL_GIT_TAG} "
    "(Flutter pub git clones skip submodules)")
  FetchContent_Declare(
    libdatachannel_fetch
    GIT_REPOSITORY https://github.com/idrto/libdatachannel.git
    GIT_TAG ${SCOMM_LIBDATACHANNEL_GIT_TAG}
    GIT_SUBMODULES_RECURSE TRUE
    GIT_PROGRESS TRUE
  )
  FetchContent_GetProperties(libdatachannel_fetch)
  if(NOT libdatachannel_fetch_POPULATED)
    FetchContent_Populate(libdatachannel_fetch)
  endif()
  set(LIBDATACHANNEL_SRC "${libdatachannel_fetch_SOURCE_DIR}")
endif()

if(NOT EXISTS "${LIBDATACHANNEL_SRC}/CMakeLists.txt")
  message(FATAL_ERROR
    "libdatachannel sources not found at ${LIBDATACHANNEL_SRC}.\n"
    "For a path checkout run: git submodule update --init --recursive\n"
    "For a Flutter git dependency, ensure network access so CMake can FetchContent.")
endif()

# Keep Mbed TLS (+ everest/p256m) static so only datachannel.dll must be bundled,
# and Windows multi-config import libs stay consistent.
set(ENABLE_PROGRAMS OFF CACHE BOOL "" FORCE)
set(ENABLE_TESTING OFF CACHE BOOL "" FORCE)
set(MBEDTLS_FATAL_WARNINGS OFF CACHE BOOL "" FORCE)
set(INSTALL_MBEDTLS_HEADERS OFF CACHE BOOL "" FORCE)
set(USE_STATIC_MBEDTLS_LIBRARY ON CACHE BOOL "" FORCE)
set(USE_SHARED_MBEDTLS_LIBRARY OFF CACHE BOOL "" FORCE)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)

add_subdirectory("${MBEDTLS_SRC}" "${CMAKE_CURRENT_BINARY_DIR}/mbedtls")

foreach(_mbed_tgt IN ITEMS mbedcrypto mbedx509 mbedtls everest p256m)
  if(TARGET ${_mbed_tgt})
    target_compile_definitions(${_mbed_tgt} PUBLIC
      MBEDTLS_USER_CONFIG_FILE="scomm_mbedtls_user_config.h"
    )
    target_include_directories(${_mbed_tgt} PUBLIC "${SCOMM_NATIVE_ROOT}")
  endif()
endforeach()

# Namespaced :: targets must be IMPORTED or ALIAS. Build-order for everest/etc.
# is enforced via add_dependencies(datachannel ...) below.
if(NOT TARGET MbedTLS::MbedTLS)
  add_library(scomm_mbedtls_iface INTERFACE)
  target_link_libraries(scomm_mbedtls_iface INTERFACE mbedtls mbedx509 mbedcrypto)
  target_include_directories(scomm_mbedtls_iface INTERFACE "${MBEDTLS_SRC}/include")
  add_library(MbedTLS::MbedTLS ALIAS scomm_mbedtls_iface)
endif()

# --- libdatachannel (data channels only) ---
set(NO_MEDIA ON CACHE BOOL "" FORCE)
set(NO_WEBSOCKET ON CACHE BOOL "" FORCE)
set(NO_EXAMPLES ON CACHE BOOL "" FORCE)
set(NO_TESTS ON CACHE BOOL "" FORCE)
set(USE_MBEDTLS ON CACHE BOOL "" FORCE)
set(BUILD_SHARED_DEPS_LIBS OFF CACHE BOOL "" FORCE)
set(INSTALL_DEPS_LIBS OFF CACHE BOOL "" FORCE)
set(BUILD_SHARED_LIBS ${SCOMM_BUILD_SHARED} CACHE BOOL "" FORCE)

add_subdirectory(
  "${LIBDATACHANNEL_SRC}"
  "${CMAKE_CURRENT_BINARY_DIR}/libdatachannel"
)

if(NOT TARGET datachannel)
  message(FATAL_ERROR "libdatachannel did not create target 'datachannel'")
endif()


set_target_properties(datachannel PROPERTIES OUTPUT_NAME "datachannel")

# Ensure Mbed TLS libs build before linking datachannel on VS multi-config.
foreach(_mbed_dep IN ITEMS mbedtls mbedx509 mbedcrypto everest p256m)
  if(TARGET ${_mbed_dep})
    add_dependencies(datachannel ${_mbed_dep})
  endif()
endforeach()

if(ANDROID)
  # Android 15 16 KB page size
  target_link_options(datachannel PRIVATE "-Wl,-z,max-page-size=16384")
endif()

message(STATUS "scommconnector: datachannel ready (shared=${SCOMM_BUILD_SHARED}, Mbed TLS)")
