# Resolve and import prebuilt libdatachannel for scommconnector.
# Layout: ${SCOMM_PREBUILT_ROOT}/<triple>/<libfile>
# Triples: windows-x86_64, linux-x86_64, linux-aarch64,
#          android-arm64-v8a, android-x86_64,
#          macos-arm64, macos-x86_64, ios-arm64

if(NOT DEFINED SCOMM_PKG_ROOT)
  message(FATAL_ERROR "ScommPrebuilt.cmake expects SCOMM_PKG_ROOT")
endif()

if(DEFINED ENV{SCOMM_PREBUILT_ROOT} AND NOT "$ENV{SCOMM_PREBUILT_ROOT}" STREQUAL "")
  set(SCOMM_PREBUILT_ROOT "$ENV{SCOMM_PREBUILT_ROOT}" CACHE PATH "Prebuilt native root" FORCE)
elseif(NOT DEFINED SCOMM_PREBUILT_ROOT)
  set(SCOMM_PREBUILT_ROOT "${SCOMM_PKG_ROOT}/native/prebuilt" CACHE PATH "Prebuilt native root")
endif()

option(SCOMM_FORCE_SOURCE "Compile libdatachannel from source even if prebuilts exist" OFF)
if(DEFINED ENV{SCOMM_FORCE_SOURCE})
  if(NOT "$ENV{SCOMM_FORCE_SOURCE}" STREQUAL "" AND NOT "$ENV{SCOMM_FORCE_SOURCE}" STREQUAL "0")
    set(SCOMM_FORCE_SOURCE ON)
  endif()
endif()

set(SCOMM_USING_PREBUILT FALSE)
set(SCOMM_PREBUILT_TRIPLE "")
set(SCOMM_PREBUILT_FILE "")

if(SCOMM_FORCE_SOURCE)
  message(STATUS "scommconnector: SCOMM_FORCE_SOURCE=ON — building from source")
  return()
endif()

if(WIN32 AND NOT ANDROID AND NOT IOS)
  set(SCOMM_PREBUILT_TRIPLE "windows-x86_64")
  set(SCOMM_PREBUILT_FILE "datachannel.dll")
elseif(ANDROID)
  if(NOT ANDROID_ABI)
    message(STATUS "scommconnector: ANDROID_ABI unset — cannot select prebuilt")
    return()
  endif()
  set(SCOMM_PREBUILT_TRIPLE "android-${ANDROID_ABI}")
  set(SCOMM_PREBUILT_FILE "libdatachannel.so")
elseif(APPLE)
  if(CMAKE_SYSTEM_NAME STREQUAL "iOS" OR IOS)
    set(SCOMM_PREBUILT_TRIPLE "ios-arm64")
  elseif(CMAKE_OSX_ARCHITECTURES MATCHES "arm64")
    set(SCOMM_PREBUILT_TRIPLE "macos-arm64")
  elseif(CMAKE_OSX_ARCHITECTURES MATCHES "x86_64")
    set(SCOMM_PREBUILT_TRIPLE "macos-x86_64")
  elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "arm64|aarch64")
    set(SCOMM_PREBUILT_TRIPLE "macos-arm64")
  else()
    set(SCOMM_PREBUILT_TRIPLE "macos-x86_64")
  endif()
  set(SCOMM_PREBUILT_FILE "libdatachannel.a")
elseif(UNIX)
  if(CMAKE_SYSTEM_PROCESSOR MATCHES "aarch64|arm64")
    set(SCOMM_PREBUILT_TRIPLE "linux-aarch64")
  else()
    set(SCOMM_PREBUILT_TRIPLE "linux-x86_64")
  endif()
  set(SCOMM_PREBUILT_FILE "libdatachannel.so")
else()
  return()
endif()

set(_scomm_prebuilt_path
  "${SCOMM_PREBUILT_ROOT}/${SCOMM_PREBUILT_TRIPLE}/${SCOMM_PREBUILT_FILE}")

if(NOT EXISTS "${_scomm_prebuilt_path}")
  message(STATUS
    "scommconnector: no prebuilt at ${_scomm_prebuilt_path} — building from source")
  return()
endif()

message(STATUS "scommconnector: using prebuilt ${_scomm_prebuilt_path}")

if(SCOMM_PREBUILT_FILE MATCHES "\\.a$")
  add_library(datachannel STATIC IMPORTED GLOBAL)
else()
  add_library(datachannel SHARED IMPORTED GLOBAL)
endif()

set_target_properties(datachannel PROPERTIES
  IMPORTED_LOCATION "${_scomm_prebuilt_path}"
  OUTPUT_NAME "datachannel"
)

# Host apps may depend on this target name (install neuter ordering).
add_custom_target(scomm_neuter_native_install ALL
  COMMENT "scommconnector prebuilt: third-party install neuter not required"
)

set(SCOMM_USING_PREBUILT TRUE)
