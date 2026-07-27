cmake_minimum_required(VERSION 3.14)

set(PROJECT_NAME "scommconnector")
project(${PROJECT_NAME} LANGUAGES CXX)

add_subdirectory(
  "${CMAKE_CURRENT_SOURCE_DIR}/../src"
  "${CMAKE_CURRENT_BINARY_DIR}/shared"
)

set(scommconnector_bundled_libraries
  $<TARGET_FILE:datachannel>
  PARENT_SCOPE
)

# Flutter's Windows INSTALL step runs cmake_install.cmake with
# CMAKE_INSTALL_PREFIX=$<TARGET_FILE_DIR:...> (unevaluated). Nested mbedtls /
# libdatachannel install() rules then fail with MSB3073. Neutralize those scripts
# before INSTALL; DLL copy still happens via scommconnector_bundled_libraries.
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/_scomm_noop_install.cmake"
  "# Install rules disabled for Flutter host-app bundling.\n")
add_custom_target(scomm_neutralize_install ALL
  COMMAND "${CMAKE_COMMAND}" -E copy_if_different
    "${CMAKE_CURRENT_BINARY_DIR}/_scomm_noop_install.cmake"
    "${CMAKE_CURRENT_BINARY_DIR}/shared/cmake_install.cmake"
  COMMAND "${CMAKE_COMMAND}" -E copy_if_different
    "${CMAKE_CURRENT_BINARY_DIR}/_scomm_noop_install.cmake"
    "${CMAKE_CURRENT_BINARY_DIR}/cmake_install.cmake"
  COMMENT "Neutralizing scommconnector third-party CMake install rules"
)
