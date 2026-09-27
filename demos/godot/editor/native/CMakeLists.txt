cmake_minimum_required(VERSION 3.22)
project(papng_gif LANGUAGES C CXX)
include(FetchContent)
set(GODOTCPP_BUILD_PROFILE "${CMAKE_CURRENT_SOURCE_DIR}/build-profile.json" CACHE FILEPATH "" FORCE)
FetchContent_Declare(godot_cpp
    URL https://codeload.github.com/godotengine/godot-cpp/tar.gz/refs/tags/godot-4.4-stable
    URL_HASH SHA256=472c6e7f3f7a9d576f21e2c57d16390b46d238f98e69a47d84730e943f5c5506
    DOWNLOAD_EXTRACT_TIMESTAMP TRUE)
FetchContent_MakeAvailable(godot_cpp)
add_library(giflib STATIC giflib/dgif_lib.c giflib/gifalloc.c giflib/gif_err.c giflib/openbsd-reallocarray.c)
set_target_properties(giflib PROPERTIES POSITION_INDEPENDENT_CODE ON C_VISIBILITY_PRESET hidden)
target_include_directories(giflib PUBLIC giflib)
add_library(papng_gif SHARED gif_decoder.cpp png_encoder.cpp)
target_link_libraries(papng_gif PRIVATE giflib godot-cpp::template_release)
set_target_properties(papng_gif PROPERTIES CXX_STANDARD 17 CXX_VISIBILITY_PRESET hidden
    VISIBILITY_INLINES_HIDDEN ON PREFIX "" OUTPUT_NAME "papng_gif"
    LIBRARY_OUTPUT_DIRECTORY "${PAPNG_OUTPUT_DIR}" RUNTIME_OUTPUT_DIRECTORY "${PAPNG_OUTPUT_DIR}")
foreach(config DEBUG RELEASE RELWITHDEBINFO MINSIZEREL)
    set_target_properties(papng_gif PROPERTIES LIBRARY_OUTPUT_DIRECTORY_${config} "${PAPNG_OUTPUT_DIR}"
        RUNTIME_OUTPUT_DIRECTORY_${config} "${PAPNG_OUTPUT_DIR}")
endforeach()
if(ANDROID)
    set_target_properties(papng_gif PROPERTIES PREFIX "lib")
endif()
if(MINGW)
    target_link_options(papng_gif PRIVATE -static -static-libgcc -static-libstdc++)
elseif(UNIX AND NOT ANDROID AND NOT APPLE)
    target_link_options(papng_gif PRIVATE -static-libgcc -static-libstdc++)
endif()
