cmake_minimum_required(VERSION 3.20.0)
project(libcot LANGUAGES CXX C)

set(CMAKE_CXX_STANDARD 17 CACHE STRING "")

find_package(MLIR REQUIRED CONFIG)

list(APPEND CMAKE_MODULE_PATH "${MLIR_CMAKE_DIR}")
list(APPEND CMAKE_MODULE_PATH "${LLVM_CMAKE_DIR}")

include(AddLLVM)
include(AddMLIR)
include(HandleLLVMOptions)

include_directories(${LLVM_INCLUDE_DIRS})
include_directories(${MLIR_INCLUDE_DIRS})
include_directories(${PROJECT_SOURCE_DIR}/include)

# libcir headers (CIROps.h, generated .inc files)
include_directories(${PROJECT_SOURCE_DIR}/../libcir/include)
include_directories(${PROJECT_SOURCE_DIR}/../libcir/build/include)

add_definitions(${LLVM_DEFINITIONS})

# libcot static library — compiler passes
add_library(COT STATIC
  lib/CIRToLLVM.cpp
)

target_include_directories(COT PUBLIC
  ${PROJECT_SOURCE_DIR}/include
)

target_link_libraries(COT PUBLIC
  MLIRIR
  MLIRSupport
  MLIRPass
  MLIRLLVMDialect
  MLIRLLVMCommonConversion
  MLIRFuncDialect
)
