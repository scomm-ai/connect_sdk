cmake_minimum_required(VERSION 3.10)

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
