# ===========================================================================
# CMakeLists.txt — Build configuration for the onenm_bridge JNI library.
#
# Links onenm_bridge.cpp against prebuilt llama.cpp shared libraries
# located in jniLibs/<ABI>/. Currently only arm64-v8a is shipped.
#
# IMPORTED_NO_SONAME TRUE is set on all imported targets to prevent CMake
# from embedding the host build-machine's absolute paths into the .so.
# ===========================================================================

cmake_minimum_required(VERSION 3.22.1)
project(onenm)

# The JNI shared library that Kotlin loads via System.loadLibrary().
add_library(onenm_bridge SHARED onenm_bridge.cpp)

# llama.cpp public headers (llama.h, ggml.h, etc.)
include_directories(
        ${CMAKE_CURRENT_SOURCE_DIR}/llama
)

# ---------- Prebuilt llama.cpp libraries ----------
set(LIB_PATH ${CMAKE_SOURCE_DIR}/../jniLibs/${ANDROID_ABI})

add_library(llama SHARED IMPORTED)
set_target_properties(llama PROPERTIES
        IMPORTED_LOCATION ${LIB_PATH}/libllama.so
        IMPORTED_NO_SONAME TRUE)

add_library(ggml SHARED IMPORTED)
set_target_properties(ggml PROPERTIES
        IMPORTED_LOCATION ${LIB_PATH}/libggml.so
        IMPORTED_NO_SONAME TRUE)

add_library(ggml-base SHARED IMPORTED)
set_target_properties(ggml-base PROPERTIES
        IMPORTED_LOCATION ${LIB_PATH}/libggml-base.so
        IMPORTED_NO_SONAME TRUE)

add_library(ggml-cpu SHARED IMPORTED)
set_target_properties(ggml-cpu PROPERTIES
        IMPORTED_LOCATION ${LIB_PATH}/libggml-cpu-android_armv8.2_1.so
        IMPORTED_NO_SONAME TRUE)

add_library(omp SHARED IMPORTED)
set_target_properties(omp PROPERTIES
        IMPORTED_LOCATION ${LIB_PATH}/libomp.so
        IMPORTED_NO_SONAME TRUE)

find_library(log-lib log)

target_link_libraries(
        onenm_bridge
        llama
        ggml
        ggml-base
        ggml-cpu
        omp
        ${log-lib}
)