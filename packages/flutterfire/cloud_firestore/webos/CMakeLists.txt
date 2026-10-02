cmake_minimum_required(VERSION 3.10)
set(PROJECT_NAME "firebase_firestore_webos")
project(${PROJECT_NAME} LANGUAGES CXX)

# This value is used when generating builds using this plugin, so it must
# not be changed
set(PLUGIN_NAME "firebase_firestore_webos_plugin")

add_library(${PLUGIN_NAME} SHARED
  "firebase_firestore_webos_plugin.cc"
  "messages.g.cc"
)

apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET default)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

# Stub headers that fill gaps in the installed Firebase C++ SDK headers in the
# WebOS NDK sysroot. These stubs live inside the plugin package and are
# searched BEFORE the sysroot so they shadow the missing files
# (firestore_errors.h, geo_point.h, timestamp.h are absent from the sysroot).
target_include_directories(${PLUGIN_NAME} BEFORE PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}/stubs"
)

# Public API headers (plugin's own public include dir)
target_include_directories(${PLUGIN_NAME} PUBLIC
  "${CMAKE_CURRENT_SOURCE_DIR}/include"
)
target_include_directories(${PLUGIN_NAME} PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}"
)

target_link_libraries(${PLUGIN_NAME} PRIVATE 
  flutter
  firebase_app
  firebase_firestore
  firebase_core_webos_plugin
  atomic
)

# List of absolute paths to libraries that should be bundled with the plugin
set(firebase_firestore_webos_bundled_libraries
  ""
  PARENT_SCOPE
)
