cmake_minimum_required(VERSION 3.20.0)
project(libcir LANGUAGES CXX C)

set(CMAKE_CXX_STANDARD 17 CACHE STRING "")

find_package(MLIR REQUIRED CONFIG)

list(APPEND CMAKE_MODULE_PATH "${MLIR_CMAKE_DIR}")
list(APPEND CMAKE_MODULE_PATH "${LLVM_CMAKE_DIR}")

include(TableGen)
include(AddLLVM)
include(AddMLIR)
include(HandleLLVMOptions)

include_directories(${LLVM_INCLUDE_DIRS})
include_directories(${MLIR_INCLUDE_DIRS})
include_directories(${PROJECT_SOURCE_DIR}/include)
include_directories(${PROJECT_BINARY_DIR}/include)

add_definitions(${LLVM_DEFINITIONS})

# Generate dialect + op declarations/definitions from TableGen
set(LLVM_TARGET_DEFINITIONS include/CIR/CIRDialect.td)
mlir_tablegen(include/CIR/CIRDialect.h.inc -gen-dialect-decls)
mlir_tablegen(include/CIR/CIRDialect.cpp.inc -gen-dialect-defs)
add_public_tablegen_target(CIRDialectIncGen)

set(LLVM_TARGET_DEFINITIONS include/CIR/CIRTypes.td)
mlir_tablegen(include/CIR/CIRTypes.h.inc -gen-typedef-decls)
mlir_tablegen(include/CIR/CIRTypes.cpp.inc -gen-typedef-defs)
add_public_tablegen_target(CIRTypesIncGen)

set(LLVM_TARGET_DEFINITIONS include/CIR/CIROps.td)
mlir_tablegen(include/CIR/CIROps.h.inc -gen-op-decls)
mlir_tablegen(include/CIR/CIROps.cpp.inc -gen-op-defs)
mlir_tablegen(include/CIR/CIREnums.h.inc -gen-enum-decls)
mlir_tablegen(include/CIR/CIREnums.cpp.inc -gen-enum-defs)
add_public_tablegen_target(CIROpsIncGen)

# libcir static library
add_library(CIR STATIC
  lib/CIRDialect.cpp
  c-api/CIRCApi.cpp
)

include_directories(${PROJECT_SOURCE_DIR}/c-api)

target_include_directories(CIR PUBLIC
  ${PROJECT_SOURCE_DIR}/include
  ${PROJECT_BINARY_DIR}/include
)

add_dependencies(CIR CIRDialectIncGen CIRTypesIncGen CIROpsIncGen)

target_link_libraries(CIR PUBLIC
  MLIRIR
  MLIRSupport
  MLIRFuncDialect
  MLIRCastInterfaces
)
