# Helper functions to setup compiler settings
# Various snippets were borrowed from 'googletest/cmake/internal_utils.cmake'

include(CheckCCompilerFlag)
include(CMakeParseArguments)

string(TOLOWER "${CMAKE_C_COMPILER_ID}" CMAKE_C_COMPILER_ID_LOWER)

# Detect Intel compiler
string(REGEX MATCH "intel" CMAKE_COMPILER_IS_INTEL "${CMAKE_C_COMPILER_ID_LOWER}")

# Detect Clang compiler; for the moment, just treat as gcc
string(REGEX MATCH "clang" CMAKE_COMPILER_IS_CLANG "${CMAKE_C_COMPILER_ID_LOWER}")
if (CMAKE_COMPILER_IS_CLANG)
    set(CMAKE_COMPILER_IS_GNUCC TRUE)
endif()

## Helper functions

macro(_bench_add_if_not_present var flag)
    if (NOT "${${var}}" MATCHES "(^| )${flag}($| )")
        set(${var} "${${var}} ${flag}")
    endif()
endmacro()

macro(bench_add_flag)
    set(arg_options)
    set(arg_single)
    set(arg_multi FLAGS LANGUAGES CONFIGURATIONS)
    cmake_parse_arguments(ARG "${arg_options}" "${arg_single}" "${arg_multi}" ${ARGN})

    if (NOT ARG_LANGUAGES)
        set(ARG_LANGUAGES C CXX)
    endif()
    if (ARG_CONFIGURATIONS)
        set(ALL_CFGS 0)
    else()
        set(ALL_CFGS 1)
    endif()

    foreach(FLAG ${ARG_FLAGS})
        foreach(LANG ${ARG_LANGUAGES})
            string(TOUPPER "${LANG}" LANG_UPPER)
            if (ALL_CFGS)
                set(FLAG_VAR "CMAKE_${LANG_UPPER}_FLAGS")
                _bench_add_if_not_present(${FLAG_VAR} ${FLAG})
            else()
                foreach(CONFIG ${ARG_CONFIGURATIONS})
                    string(TOUPPER "${CONFIG}" CONFIG_UPPER)
                    set(FLAG_VAR "CMAKE_${LANG_UPPER}_FLAGS_${CONFIG_UPPER}")
                    _bench_add_if_not_present(${FLAG_VAR} ${FLAG})
                endforeach()
            endif()
        endforeach()
    endforeach()
endmacro()

macro(bench_replace_flag)
    set(arg_options)
    set(arg_single REGEX REPLACE)
    set(arg_multi LANGUAGES CONFIGURATIONS)
    cmake_parse_arguments(ARG "${arg_options}" "${arg_single}" "${arg_multi}" ${ARGN})

    if (NOT ARG_LANGUAGES)
        set(ARG_LANGUAGES C CXX)
    endif()
    if (NOT ARG_CONFIGURATIONS)
        set(ARG_CONFIGURATIONS ${CMAKE_BUILD_TYPE} ${CMAKE_CONFIGURATION_TYPES})
    endif()
    list(REMOVE_DUPLICATES ARG_CONFIGURATIONS)

    foreach(LANG ${ARG_LANGUAGES})
        string(TOUPPER "${LANG}" LANG_UPPER)

        set(FLAG_VAR "CMAKE_${LANG_UPPER}_FLAGS")
        string(REGEX REPLACE "${ARG_REGEX}" "${ARG_REPLACE}"
               ${FLAG_VAR} "${${FLAG_VAR}}")

        foreach(CONFIG ${ARG_CONFIGURATIONS})
            string(TOUPPER "${CONFIG}" CONFIG_UPPER)

            set(FLAG_VAR "CMAKE_${LANG_UPPER}_FLAGS_${CONFIG_UPPER}")
            string(REGEX REPLACE "${ARG_REGEX}" "${ARG_REPLACE}"
                   ${FLAG_VAR} "${${FLAG_VAR}}")
        endforeach()
    endforeach()
endmacro()

#------------------------------------------------------------------------------

macro(bench_config_compiler)
    # <inttypes.h> will only define format macros (e.g. PRId64) is this is defined.
    # http://src.chromium.org/svn/trunk/src/base/format_macros.h
    add_definitions(-D__STDC_CONSTANT_MACROS)
    add_definitions(-D__STDC_FORMAT_MACROS)
    add_definitions(-D__STDC_LIMIT_MACROS)

    if (WIN32)
        add_definitions(-DWIN32_LEAN_AND_MEAN)
        add_definitions(-D_CRT_SECURE_NO_WARNINGS)
        add_definitions(-D_SCL_SECURE_NO_WARNINGS)
        add_definitions(-DNOMINMAX)
    endif()

    if (CMAKE_COMPILER_IS_INTEL)
        bench_add_flag(FLAGS "-fasm-blocks")

        find_package(Threads)
        if (CMAKE_USE_PTHREADS_INIT)
            bench_add_flag(FLAGS "-pthread")
        endif()
    endif()

    # stricter warnings
    if (MSVC)
        # We prefer more strict warnings
        bench_replace_flag(REGEX "/W[0-9]" REPLACE "/W4")
        # C4127: conditional expression is constant [e.g. while(1)]
        bench_add_flag(FLAGS "/wd4127")
    elseif (CMAKE_COMPILER_IS_GNUCC)
        bench_add_flag(FLAGS "-Wall" "-Wextra")
        bench_add_flag(FLAGS "-Wshadow")  # -Wconversion -Wfloat-equal
        bench_add_flag(FLAGS "-Wstrict-prototypes -Wmissing-prototypes" LANGUAGES C)
        bench_add_flag(FLAGS "-Woverloaded-virtual" LANGUAGES CXX)
    elseif (CMAKE_COMPILER_IS_INTEL)
        bench_add_flag(FLAGS "-Wall" "-Wcheck")
    endif()

    # profiling/debugging
    if (MSVC)
        # always generate program database (PDB) - does not affect optimizations
        bench_add_flag(FLAGS "/Zi")
        # ... linker needs to be told to emit debug info otherwise PDB behaves like a stub.
        # http://www.wintellect.com/CS/blogs/jrobbins/archive/2009/06/19/do-pdb-files-affect-performance.aspx
        set(CMAKE_EXE_LINKER_FLAGS_RELEASE "${CMAKE_EXE_LINKER_FLAGS_RELEASE} /DEBUG /OPT:REF /OPT:ICF")

        # Run-Time Error Checks (only for debug builds)
        # http://msdn.microsoft.com/en-us/library/8wtf2dfz.aspx
        bench_add_flag(FLAGS "/RTC1" CONFIGURATIONS DEBUG)
    elseif (CMAKE_COMPILER_IS_GNUCC)
        # generate debugging information with macro definitions
        #
        # only activate on debug builds, since this may impact performance
        # (it could block optimizations and bloats the executable)
        bench_replace_flag(REGEX "-g(gdb)?([0-9])*( |$)" REPLACE "" CONFIGURATIONS DEBUG)
        bench_add_flag(FLAGS "-g3" CONFIGURATIONS DEBUG)
        if (NOT CMAKE_COMPILER_IS_CLANG)
            bench_add_flag(FLAGS "-ggdb3" CONFIGURATIONS DEBUG)
        endif()
    endif()
    if (CMAKE_COMPILER_IS_CLANG)
        # http://blog.llvm.org/2011/05/what-every-c-programmer-should-know_14.html
        # Add runtime checks to catch undefined behaviour (e.g. oversized shift),
        # which raise SIGILL (Illegal instruction).
        option(CLANG_CATCH_UNDEFINED_BEHAVIOUR "Enable runtime checks for undefined behaviour (Debug configuration)" OFF)
        if (CLANG_CATCH_UNDEFINED_BEHAVIOUR)
            bench_add_flag(FLAGS "-fcatch-undefined-behavior" CONFIGURATIONS DEBUG)
        endif()
        option(CLANG_CATCH_SIGNED_OVERFLOW "Enable runtime checks for signed overflow (Debug configuration)" OFF)
        if (CLANG_CATCH_SIGNED_OVERFLOW)
            bench_add_flag(FLAGS "-ftrapv" CONFIGURATIONS DEBUG)
        endif()

        # See http://crbug.com/110262 and https://github.com/martine/ninja/issues/174
        if (CMAKE_GENERATOR STREQUAL "Ninja")
            bench_add_flag(FLAGS "-fcolor-diagnostics")
        endif()
    endif()

    # optimization flags
    # TODO: expose these as options, so it's easier to experiment
    if(MSVC)
        # - CMake sets '/O2' (fast code) for release
        # - Whole Program Optimization (implies /LTCG)
        # - Disable Buffer Security Check - we don't have security exposure
        bench_add_flag(FLAGS "/GL" "/GS-" CONFIGURATIONS RELEASE)
        bench_add_flag(FLAGS "/fp:fast" CONFIGURATIONS RELEASE)
        if (MSVC10)
            bench_add_flag(FLAGS "/arch:AVX" CONFIGURATIONS RELEASE)
        else()
            bench_add_flag(FLAGS "/arch:SSE2" CONFIGURATIONS RELEASE)
        endif()
    elseif (CMAKE_COMPILER_IS_GNUCC)
        # Check default options:
        #   $ gcc -Q --help=target -march=native

        # - CMake sets '-O3' in release mode
        # - disable auto-vectorization
        #bench_add_flag(FLAGS "-fno-tree-vectorize" CONFIGURATIONS RELEASE)

        # http://gcc.gnu.org/ml/gcc-patches/2005-01/msg01247.html
        #bench_add_flag(FLAGS "-ftree-vectorizer-verbose=2" CONFIGURATIONS RELEASE)

        bench_add_flag(FLAGS "-mtune=native" "-march=native -fopenmp"
                           "-fomit-frame-pointer" "-funroll-loops"
                           "-ffast-math" "-funsafe-math-optimizations"
                           "-ftree-vectorizer-verbose=6" "-DEIGEN_NO_DEBUG"
                     CONFIGURATIONS RELEASE)

        bench_add_flag(FLAGS "-fopenmp" CONFIGURATIONS DEBUG)

        if (NOT CMAKE_COMPILER_IS_CLANG)
            bench_add_flag(FLAGS "-mfpmath=sse" CONFIGURATIONS RELEASE)
        endif()


        # Available with GCC 4.5 onwards:
        # http://sourceforge.net/apps/trac/mingw-w64/wiki/LTO%20and%20GCC
        option(GCC_LINK_TIME_OPTIMIZATION "Enable GCC Link Time Optimization (LTO)" ON)
        if (GCC_LINK_TIME_OPTIMIZATION)
            bench_add_flag(FLAGS "-flto" CONFIGURATIONS RELEASE)
            set(CMAKE_EXE_LINKER_FLAGS_RELEASE "${CMAKE_EXE_LINKER_FLAGS_RELEASE} -flto -fwhole-program")
            set(CMAKE_SHARED_LINKER_FLAGS_RELEASE "${CMAKE_SHARED_LINKER_FLAGS_RELEASE} -flto")
            set(CMAKE_MODULE_LINKER_FLAGS_RELEASE "${CMAKE_MODULE_LINKER_FLAGS_RELEASE} -flto")
        endif()

        # TODO: experiment whether Graphite is worthwhile for us.
        # Disable by default or test for availability, since GCC may not always be configured with support.
        option(GCC_GRAPHITE_OPTIMIZATIONS "Enable GCC Graphite auto-parallelization optimizations" OFF)
        if (GCC_GRAPHITE_OPTIMIZATIONS)
            bench_add_flag(FLAGS "-fgraphite-identity"
                               "-floop-interchange"
                               "-floop-strip-mine"
                               "-floop-block"
                               "-floop-parallelize-all"
                               "-ftree-loop-distribution"
                               "-ftree-parallelize-loops"
                         CONFIGURATIONS RELEASE)
        endif()

        # Not needed, since automatically detected via march:
        #   $ gcc -c -Q -march=native --help=target
        #
        # it seems actual instruction set is checked at runtime
        #bench_add_flag(FLAGS "-mmmx" "-m3dnow" "-msse" "-msse2" "-msse3" "-msse4"
        #                   "-msse4.1" "-msse4.2"
        #             CONFIGURATIONS RELEASE)
        #if (NOT CMAKE_COMPILER_IS_CLANG)
        #    bench_add_flag(FLAGS "-msse4a" CONFIGURATIONS RELEASE)
        #endif()
    elseif (CMAKE_COMPILER_IS_INTEL)
        # - "-fast": http://web.archiveorange.com/archive/v/5y7PkZLNOEm0OGQfunZD
        #   CMake should use 'xiar' linker, but calls 'ar'
        # - "-use-intel-optimized-headers"
        #   ld: cannot find -lipps_l, -lippvm_l, -lipps_l, -lippvm_l, -lippcore_l
        bench_add_flag(FLAGS "-align" "-finline-functions" "-malign-double" "-O3" "-no-prec-div" "-openmp" "-complex-limited-range" #"-fp-model source"
                           "-xHost" "-opt-multi-version-aggressive" "-scalar-rep" "-unroll-aggressive" "-vec-report6" #"-S" "-mtune=core2" "-xSSE4.1"
                           "-restrict" "-DEIGEN_NO_DEBUG" #"-falign-functions=16"
                     CONFIGURATIONS RELEASE)

        bench_add_flag(FLAGS "-restrict" "-O0" CONFIGURATIONS DEBUG)
    endif()

    if (CMAKE_COMPILER_IS_CLANG)
      # "-O4 enables link-time optimization; object files are stored in the LLVM
      # bitcode file format and whole program optimization is done at link time"
      #
      # Unfortunately this dobench't work yet:
      #   CMakeFiles/test_matrix.dir/test/matrix_test.cc.obj: file not recognized: File format not recognized
      #   collect2: ld returned 1 exit status
      #   clang++: error: linker (via gcc) command failed with exit code 1 (use -v to see invocation)
      #
      #bench_replace_flag(REGEX "-O([0-9s]?|fast)( |$)" REPLACE "" CONFIGURATIONS RELEASE)
      #bench_add_flag(FLAGS "-O4" CONFIGURATIONS RELEASE)
    endif()

    if (MSVC)
        if (NOT BUILD_SHARED_LIBS)
            # When Google Test is built as a shared library, it should also use
            # shared runtime libraries.  Otherwise, it may end up with multiple
            # copies of runtime library data in different modules, resulting in
            # hard-to-find crashes. When it is built as a static library, it is
            # preferable to use CRT as static libraries, as we don't have to rely
            # on CRT DLLs being available. CMake always defaults to using shared
            # CRT libraries, so we override that default here.
            bench_replace_flag(REGEX "/MD" REPLACE "/MT")
        endif()
    endif()

    # http://code.google.com/p/jrfonseca/wiki/Gprof2Dot#Which_options_should_I_pass_to_gcc_when_compiling_for_profiling?
    if (ENABLE_PROFILING)
      set(REMOVE_REGEX
          "-g(gdb)?([0-9])*"
          "-finline-functions"
          "-fomit-frame-pointer"
          "-finline-functions-called-once"
          "-foptimize-sibling-calls"
      )
      foreach(RM_RX ${REMOVE_REGEX})
          bench_replace_flag(REGEX "${RM_RX}( |$)" REPLACE "")
      endforeach()

      bench_add_flag(FLAGS
          "-g3"
          "-ggdb3"
          "-pg"
          "-fno-inline-functions"
          "-fno-omit-frame-pointer"
          "-fno-inline-functions-called-once"
          "-fno-optimize-sibling-calls"
      )
    endif()

    # CMake does not natively support Intel compiler
    # (see http://public.kitware.com/Bug/view.php?id=6929)
    # -> TODO: add script which calls ICProjConvert and sets the project properties
endmacro()

## User options
if (CMAKE_COMPILER_IS_GNUCC)
  option(ENABLE_PROFILING "Instrument executables with profiling information" OFF)
endif()
