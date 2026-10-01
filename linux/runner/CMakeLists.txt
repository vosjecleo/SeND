cmake_minimum_required(VERSION 3.13)
project(runner LANGUAGES C CXX)
pkg_check_modules(WAYLAND REQUIRED IMPORTED_TARGET wayland-client)
find_program(WAYLAND_SCANNER wayland-scanner REQUIRED)
set(IDLE_PROTOCOL "${CMAKE_CURRENT_SOURCE_DIR}/ext-idle-notify-v1.xml")
add_custom_command(OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/ext-idle-notify-v1-client-protocol.h"
  COMMAND ${WAYLAND_SCANNER} client-header ${IDLE_PROTOCOL} "${CMAKE_CURRENT_BINARY_DIR}/ext-idle-notify-v1-client-protocol.h"
  DEPENDS ${IDLE_PROTOCOL})
add_custom_command(OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/ext-idle-notify-v1-protocol.c"
  COMMAND ${WAYLAND_SCANNER} private-code ${IDLE_PROTOCOL} "${CMAKE_CURRENT_BINARY_DIR}/ext-idle-notify-v1-protocol.c"
  DEPENDS ${IDLE_PROTOCOL})

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME}
  "main.cc"
  "my_application.cc"
  "desktop_idle.cc"
  "${CMAKE_CURRENT_BINARY_DIR}/ext-idle-notify-v1-client-protocol.h"
  "${CMAKE_CURRENT_BINARY_DIR}/ext-idle-notify-v1-protocol.c"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Add preprocessor definitions for the application ID.
add_definitions(-DAPPLICATION_ID="${APPLICATION_ID}")

# Add dependency libraries. Add any application-specific dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::GTK)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::WAYLAND ${CMAKE_DL_LIBS})
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_CURRENT_BINARY_DIR}")

target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")
