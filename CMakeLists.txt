cmake_minimum_required(VERSION 3.10)
project(swordigo C)

set(CMAKE_C_STANDARD 11)
option(USE_GLES2 "unused — Swordigo is GLES1" OFF)

find_package(PkgConfig REQUIRED)
pkg_check_modules(SDL2 REQUIRED sdl2)
pkg_check_modules(OPENAL REQUIRED openal)
pkg_check_modules(MPG123 REQUIRED libmpg123)

add_executable(swordigo-nextos-v108
  src/main.c
  src/imports.c
  src/jni_fake.c
  src/music_player.c
  src/util.c
  src/error.c
  src/so_util.c
  src/pthread_bridge.c
)

target_include_directories(swordigo-nextos-v108 PRIVATE
  ${SDL2_INCLUDE_DIRS}
  ${OPENAL_INCLUDE_DIRS}
  ${MPG123_INCLUDE_DIRS}
  src
)

target_link_libraries(swordigo-nextos-v108 PRIVATE
  ${SDL2_LIBRARIES}
  ${OPENAL_LIBRARIES}
  ${MPG123_LIBRARIES}
  GLESv1_CM
  EGL
  z
  m
  dl
  pthread
)

target_compile_options(swordigo-nextos-v108 PRIVATE
  ${SDL2_CFLAGS_OTHER}
  -Wall -Wextra -Wno-unused-parameter
)
