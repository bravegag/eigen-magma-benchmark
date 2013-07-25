# Benchmark project
# Author: Giovanni Azua Garcia
#
#-------------------------------------------------------------------------------

cmake_minimum_required(VERSION 2.8 FATAL_ERROR)

project(bench CXX Fortran)

#*************************************************
# Macro definitions
#*************************************************

add_definitions(-Wno-shadow)
#add_definitions(-std=c++11)

#add_definitions(-DEIGEN_USE_MKL_ALL)
#add_definitions(-DEIGEN_USE_MAGMA_ALL)

#*************************************************
# Project source directories
#*************************************************

include_directories(
    "${bench_SOURCE_DIR}/main/cpp"
)

#*************************************************
# Third-party libraries
#*************************************************

# Setup submodularity project
list(APPEND CMAKE_MODULE_PATH "${bench_SOURCE_DIR}/cmake")

## Boost
set(Boost_USE_STATIC_LIBS    ON)
set(Boost_USE_MULTITHREADED  ON)
set(Boost_USE_STATIC_RUNTIME OFF)
set(Boost_ADDITIONAL_VERSIONS "1.50.0" "1.53.0")
find_package( Boost REQUIRED COMPONENTS filesystem graph system program_options chrono)
include_directories(${Boost_INCLUDE_DIRS})

## Eigen
include_directories($ENV{EIGEN3_INCLUDE_DIR})
message(STATUS
    "EIGEN was found:\n"
    "  EIGEN3_INCLUDE_DIRS: $ENV{EIGEN3_INCLUDE_DIR}"
)

## CUDA
find_package(CUDA)
if (CUDA_FOUND)
    include_directories(
        ${CUDA_INCLUDE_DIRS}
        ${CUDA_CUT_INCLUDE_DIR}
        ${CUDA_CUT_LIBRARIES}
    )
endif(CUDA_FOUND)

## MAGMA
find_package(MAGMA)
if (MAGMA_FOUND)
    add_definitions(-DADD_)
    add_definitions(-DMAGMA_SETAFFINITY)
    add_definitions(-DMAGMA_WITH_MKL)
    include_directories(${MAGMA_INCLUDE_DIRS})
    message(STATUS
        "MAGMA was found:\n"
        "  MAGMA_INCLUDE_DIRS: ${MAGMA_INCLUDE_DIRS}\n"
        "  MAGMA_LIBRARY_DIRS: ${MAGMA_LIBRARY_DIRS}\n"
        "  MAGMA_LIBRARIES: ${MAGMA_LIBRARIES}"
    )
else()
    message(FATAL_ERROR "MAGMA was not found, please install it first")
endif()

if (MINGW)
  set(gtest_disable_pthreads ON CACHE INTERNAL "" FORCE)
endif()

## MKL
find_package(MKL)
if (MKL_FOUND)
    include_directories(${MKL_INCLUDE_DIRS})
else()
    message (FATAL_ERROR "MKL was not found, please install it first.")
endif()

#*************************************************
# Targets
#*************************************************

include(cmake/targets.cmake)
bench_targets_init()

include(cmake/compiler_settings.cmake)
bench_config_compiler()

#*************************************************
# Benchmark executable
#*************************************************

bench_executable(benchmark
    main/cpp/benchmark_main.cc
)
target_link_libraries(benchmark
    ${Boost_LIBRARIES}
    ${CUDA_LIBRARIES}
    ${CUDA_CUBLAS_LIBRARIES}
    ${MKL_LIBRARIES}
    ${MAGMA_LIBRARIES}
)

find_library(MATH_LIBRARY m)
if (MATH_LIBRARY)
  target_link_libraries(benchmark ${MATH_LIBRARY})
endif()
