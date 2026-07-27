cmake_minimum_required(VERSION 3.16)
# Desktop/dev helper — same sources as the Flutter FFI plugin (`src/`).
project(scomm_libdatachannel LANGUAGES C CXX)
add_subdirectory(
  "${CMAKE_CURRENT_SOURCE_DIR}/../src"
  "${CMAKE_CURRENT_BINARY_DIR}/shared"
)
