include(cmake/SystemLink.cmake)
include(cmake/LibFuzzer.cmake)
include(CMakeDependentOption)
include(CheckCXXCompilerFlag)


macro(Test2_supports_sanitizers)
  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND NOT WIN32)
    set(SUPPORTS_UBSAN ON)
  else()
    set(SUPPORTS_UBSAN OFF)
  endif()

  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND WIN32)
    set(SUPPORTS_ASAN OFF)
  else()
    set(SUPPORTS_ASAN ON)
  endif()
endmacro()

macro(Test2_setup_options)
  option(Test2_ENABLE_HARDENING "Enable hardening" ON)
  option(Test2_ENABLE_COVERAGE "Enable coverage reporting" OFF)
  cmake_dependent_option(
    Test2_ENABLE_GLOBAL_HARDENING
    "Attempt to push hardening options to built dependencies"
    ON
    Test2_ENABLE_HARDENING
    OFF)

  Test2_supports_sanitizers()

  if(NOT PROJECT_IS_TOP_LEVEL OR Test2_PACKAGING_MAINTAINER_MODE)
    option(Test2_ENABLE_IPO "Enable IPO/LTO" OFF)
    option(Test2_WARNINGS_AS_ERRORS "Treat Warnings As Errors" OFF)
    option(Test2_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(Test2_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" OFF)
    option(Test2_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(Test2_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" OFF)
    option(Test2_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(Test2_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(Test2_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(Test2_ENABLE_CLANG_TIDY "Enable clang-tidy" OFF)
    option(Test2_ENABLE_CPPCHECK "Enable cpp-check analysis" OFF)
    option(Test2_ENABLE_PCH "Enable precompiled headers" OFF)
    option(Test2_ENABLE_CACHE "Enable ccache" OFF)
  else()
    option(Test2_ENABLE_IPO "Enable IPO/LTO" ON)
    option(Test2_WARNINGS_AS_ERRORS "Treat Warnings As Errors" ON)
    option(Test2_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(Test2_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" ${SUPPORTS_ASAN})
    option(Test2_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(Test2_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" ${SUPPORTS_UBSAN})
    option(Test2_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(Test2_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(Test2_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(Test2_ENABLE_CLANG_TIDY "Enable clang-tidy" ON)
    option(Test2_ENABLE_CPPCHECK "Enable cpp-check analysis" ON)
    option(Test2_ENABLE_PCH "Enable precompiled headers" OFF)
    option(Test2_ENABLE_CACHE "Enable ccache" ON)
  endif()

  if(NOT PROJECT_IS_TOP_LEVEL)
    mark_as_advanced(
      Test2_ENABLE_IPO
      Test2_WARNINGS_AS_ERRORS
      Test2_ENABLE_USER_LINKER
      Test2_ENABLE_SANITIZER_ADDRESS
      Test2_ENABLE_SANITIZER_LEAK
      Test2_ENABLE_SANITIZER_UNDEFINED
      Test2_ENABLE_SANITIZER_THREAD
      Test2_ENABLE_SANITIZER_MEMORY
      Test2_ENABLE_UNITY_BUILD
      Test2_ENABLE_CLANG_TIDY
      Test2_ENABLE_CPPCHECK
      Test2_ENABLE_COVERAGE
      Test2_ENABLE_PCH
      Test2_ENABLE_CACHE)
  endif()

  Test2_check_libfuzzer_support(LIBFUZZER_SUPPORTED)
  if(LIBFUZZER_SUPPORTED AND (Test2_ENABLE_SANITIZER_ADDRESS OR Test2_ENABLE_SANITIZER_THREAD OR Test2_ENABLE_SANITIZER_UNDEFINED))
    set(DEFAULT_FUZZER ON)
  else()
    set(DEFAULT_FUZZER OFF)
  endif()

  option(Test2_BUILD_FUZZ_TESTS "Enable fuzz testing executable" ${DEFAULT_FUZZER})

endmacro()

macro(Test2_global_options)
  if(Test2_ENABLE_IPO)
    include(cmake/InterproceduralOptimization.cmake)
    Test2_enable_ipo()
  endif()

  Test2_supports_sanitizers()

  if(Test2_ENABLE_HARDENING AND Test2_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR Test2_ENABLE_SANITIZER_UNDEFINED
       OR Test2_ENABLE_SANITIZER_ADDRESS
       OR Test2_ENABLE_SANITIZER_THREAD
       OR Test2_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    message("${Test2_ENABLE_HARDENING} ${ENABLE_UBSAN_MINIMAL_RUNTIME} ${Test2_ENABLE_SANITIZER_UNDEFINED}")
    Test2_enable_hardening(Test2_options ON ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()
endmacro()

macro(Test2_local_options)
  if(PROJECT_IS_TOP_LEVEL)
    include(cmake/StandardProjectSettings.cmake)
  endif()

  add_library(Test2_warnings INTERFACE)
  add_library(Test2_options INTERFACE)

  include(cmake/CompilerWarnings.cmake)
  Test2_set_project_warnings(
    Test2_warnings
    ${Test2_WARNINGS_AS_ERRORS}
    ""
    ""
    ""
    "")

  if(Test2_ENABLE_USER_LINKER)
    include(cmake/Linker.cmake)
    Test2_configure_linker(Test2_options)
  endif()

  include(cmake/Sanitizers.cmake)
  Test2_enable_sanitizers(
    Test2_options
    ${Test2_ENABLE_SANITIZER_ADDRESS}
    ${Test2_ENABLE_SANITIZER_LEAK}
    ${Test2_ENABLE_SANITIZER_UNDEFINED}
    ${Test2_ENABLE_SANITIZER_THREAD}
    ${Test2_ENABLE_SANITIZER_MEMORY})

  set_target_properties(Test2_options PROPERTIES UNITY_BUILD ${Test2_ENABLE_UNITY_BUILD})

  if(Test2_ENABLE_PCH)
    target_precompile_headers(
      Test2_options
      INTERFACE
      <vector>
      <string>
      <utility>)
  endif()

  if(Test2_ENABLE_CACHE)
    include(cmake/Cache.cmake)
    Test2_enable_cache()
  endif()

  include(cmake/StaticAnalyzers.cmake)
  if(Test2_ENABLE_CLANG_TIDY)
    Test2_enable_clang_tidy(Test2_options ${Test2_WARNINGS_AS_ERRORS})
  endif()

  if(Test2_ENABLE_CPPCHECK)
    Test2_enable_cppcheck(${Test2_WARNINGS_AS_ERRORS} "" # override cppcheck options
    )
  endif()

  if(Test2_ENABLE_COVERAGE)
    include(cmake/Tests.cmake)
    Test2_enable_coverage(Test2_options)
  endif()

  if(Test2_WARNINGS_AS_ERRORS)
    check_cxx_compiler_flag("-Wl,--fatal-warnings" LINKER_FATAL_WARNINGS)
    if(LINKER_FATAL_WARNINGS)
      # This is not working consistently, so disabling for now
      # target_link_options(Test2_options INTERFACE -Wl,--fatal-warnings)
    endif()
  endif()

  if(Test2_ENABLE_HARDENING AND NOT Test2_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR Test2_ENABLE_SANITIZER_UNDEFINED
       OR Test2_ENABLE_SANITIZER_ADDRESS
       OR Test2_ENABLE_SANITIZER_THREAD
       OR Test2_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    Test2_enable_hardening(Test2_options OFF ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()

endmacro()
