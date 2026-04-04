#===----------------------------------------------------------------------===#
# libcir — CIR MLIR dialect (TableGen + static library)
#
# Produces: libCIR.a
# Exports:  CIR target (with transitive MLIR deps)
# Install:  lib/libCIR.a, include/CIR/*.h, include/CIR/*.inc
#
# Reference: Flang FIR dialect CMakeLists.txt
#===----------------------------------------------------------------------===#

# TableGen include path — so CIRTypes.td can find CIR/CIRDialect.td
set(LLVM_TABLEGEN_FLAGS "-I${CMAKE_CURRENT_SOURCE_DIR}/include")

# Ensure output directory exists for generated .inc files
file(MAKE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/include/CIR")

# TableGen — generate dialect, type, and op declarations from .td files
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

# Static library
add_library(CIR STATIC
  lib/CIRDialect.cpp
  c-api/CIRCApi.cpp
)

add_dependencies(CIR CIRDialectIncGen CIRTypesIncGen CIROpsIncGen)

# Include directories — use generator expressions for build/install tree
target_include_directories(CIR PUBLIC
  $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
  $<BUILD_INTERFACE:${CMAKE_CURRENT_BINARY_DIR}/include>
  $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/c-api>
  $<INSTALL_INTERFACE:include>
)

# MLIR dependencies (PUBLIC so downstream targets inherit them)
target_link_libraries(CIR PUBLIC
  MLIRIR
  MLIRSupport
  MLIRFuncDialect
  MLIRCastInterfaces
  MLIRControlFlowInterfaces
  MLIRSideEffectInterfaces
  MLIRInferTypeOpInterface
)

#===----------------------------------------------------------------------===#
# Install
#===----------------------------------------------------------------------===#

install(TARGETS CIR EXPORT CIRTargets
  ARCHIVE DESTINATION lib)

# Source headers
install(DIRECTORY include/CIR
  DESTINATION include
  FILES_MATCHING PATTERN "*.h" PATTERN "*.td")

# Generated .inc headers
install(DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/include/CIR
  DESTINATION include
  FILES_MATCHING PATTERN "*.inc")

# C API header
install(FILES c-api/CIRCApi.h
  DESTINATION include/cir-c
  RENAME CIR.h)
