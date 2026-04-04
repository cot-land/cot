cmake_minimum_required(VERSION 3.20)
project(COT VERSION 0.4.0 LANGUAGES CXX C)

set(CMAKE_CXX_STANDARD 17 CACHE STRING "")
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

#===----------------------------------------------------------------------===#
# Find MLIR/LLVM from system (Homebrew)
#===----------------------------------------------------------------------===#

find_package(MLIR REQUIRED CONFIG)
find_package(LLVM REQUIRED CONFIG)

message(STATUS "Using MLIRConfig.cmake in: ${MLIR_DIR}")
message(STATUS "Using LLVMConfig.cmake in: ${LLVM_DIR}")

list(APPEND CMAKE_MODULE_PATH "${MLIR_CMAKE_DIR}")
list(APPEND CMAKE_MODULE_PATH "${LLVM_CMAKE_DIR}")

include(TableGen)
include(AddLLVM)
include(AddMLIR)
include(HandleLLVMOptions)

include_directories(${LLVM_INCLUDE_DIRS})
include_directories(${MLIR_INCLUDE_DIRS})
add_definitions(${LLVM_DEFINITIONS})

#===----------------------------------------------------------------------===#
# Subdirectories — build order matters
#===----------------------------------------------------------------------===#

# CIR dialect (TableGen + static library)
add_subdirectory(libcir)

# COT compiler passes (depends on CIR)
add_subdirectory(libcot)

# CLI driver (depends on COT, CIR, libac, libzc, libtc)
add_subdirectory(cot)

#===----------------------------------------------------------------------===#
# Install — CMake config files for find_package(CIR) / find_package(COT)
#===----------------------------------------------------------------------===#

include(CMakePackageConfigHelpers)

# CIR config
configure_package_config_file(
  "${CMAKE_CURRENT_SOURCE_DIR}/cmake/CIRConfig.cmake.in"
  "${CMAKE_CURRENT_BINARY_DIR}/cmake/CIRConfig.cmake"
  INSTALL_DESTINATION lib/cmake/cir)

write_basic_package_version_file(
  "${CMAKE_CURRENT_BINARY_DIR}/cmake/CIRConfigVersion.cmake"
  VERSION ${PROJECT_VERSION}
  COMPATIBILITY SameMajorVersion)

install(FILES
  "${CMAKE_CURRENT_BINARY_DIR}/cmake/CIRConfig.cmake"
  "${CMAKE_CURRENT_BINARY_DIR}/cmake/CIRConfigVersion.cmake"
  DESTINATION lib/cmake/cir)

install(EXPORT CIRTargets
  NAMESPACE CIR::
  DESTINATION lib/cmake/cir)

# COT config
configure_package_config_file(
  "${CMAKE_CURRENT_SOURCE_DIR}/cmake/COTConfig.cmake.in"
  "${CMAKE_CURRENT_BINARY_DIR}/cmake/COTConfig.cmake"
  INSTALL_DESTINATION lib/cmake/cot)

write_basic_package_version_file(
  "${CMAKE_CURRENT_BINARY_DIR}/cmake/COTConfigVersion.cmake"
  VERSION ${PROJECT_VERSION}
  COMPATIBILITY SameMajorVersion)

install(FILES
  "${CMAKE_CURRENT_BINARY_DIR}/cmake/COTConfig.cmake"
  "${CMAKE_CURRENT_BINARY_DIR}/cmake/COTConfigVersion.cmake"
  DESTINATION lib/cmake/cot)

install(EXPORT COTTargets
  NAMESPACE COT::
  DESTINATION lib/cmake/cot)
