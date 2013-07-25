# Helper functions for creating build targets.

macro(bench_targets_init)
    set(BENCH_ALL_SOURCES "")
    enable_testing()
endmacro()

function(bench_enable_cpplint)
    include(FindPythonInterp)
    if (NOT PYTHONINTERP_FOUND)
        message(STATUS "Python not found; 'cpplint' target will not be available")
        return()
    endif()

    set(CPPLINT_FILTER
        "-build/header_guard"
        "-build/include"
        "-legal/copyright"
        "-readability/casting"
    )

    set(CPPLINT_PATH "${bench_SOURCE_DIR}/third_party/cpplint.py")

    set(CPPLINT_ARGS "")
    if (CPPLINT_FILTER)
        string(REPLACE ";" "," CPPLINT_FILTER "${CPPLINT_FILTER}")
        set(CPPLINT_ARGS "${CPPLINT_ARGS}--filter=${CPPLINT_FILTER}")
    endif()
    if (MSVC)
        set(CPPLINT_ARGS "${CPPLINT_ARGS} --output=vs7")
    endif()

    add_custom_target(cpplint
        COMMAND ${PYTHON_EXECUTABLE} ${CPPLINT_PATH} ${CPPLINT_ARGS} ${BENCH_ALL_SOURCES}
        VERBATIM
    )
endfunction()

macro(bench_library name)
    add_library(${name} ${ARGN})
    foreach(SRC ${ARGN})
        get_filename_component(SRC_ABS "${SRC}" ABSOLUTE)
        list(APPEND BENCH_ALL_SOURCES ${SRC_ABS})
    endforeach()
endmacro()

macro(bench_executable name)
    add_executable(${name} ${ARGN})
    foreach(SRC ${ARGN})
        get_filename_component(SRC_ABS "${SRC}" ABSOLUTE)
        list(APPEND BENCH_ALL_SOURCES ${SRC_ABS})
    endforeach()
endmacro()

macro(_bench_gtest name nomain)
    bench_executable(${name} ${ARGN})
    target_link_libraries(${name} gtest)
    if (NOT ${nomain})
        target_link_libraries(${name} gtest_main)
    endif()

    # Based on 'CMake/share/Modules/FindGTest.cmake'
    # TODO: this regex-based approach is slow
    # -> we also want target to run without CTest, so errors visible directly
    foreach(SRC ${ARGN})
        file(READ "${SRC}" SRC_CONTENTS)
        string(REGEX MATCHALL "TEST_?F?\\(([A-Za-z_0-9 ,]+)\\)" FOUND_TESTS ${SRC_CONTENTS})
        foreach(TEST ${FOUND_TESTS})
            string(REGEX REPLACE ".*\\( *([A-Za-z_0-9]+), *([A-Za-z_0-9]+) *\\).*" "\\1.\\2" TEST_NAME ${TEST})
            add_test(${TEST_NAME} ${name} --gtest_filter=${TEST_NAME})
        endforeach()
    endforeach()
endmacro()

macro(bench_gtest name)
    _bench_gtest(${name} 0 ${ARGN})
endmacro()

macro(bench_gtest_nomain name)
    _bench_gtest(${name} 1 ${ARGN})
endmacro()
