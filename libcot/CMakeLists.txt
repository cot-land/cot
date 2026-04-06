#===----------------------------------------------------------------------===#
# libcot — COT compiler passes (Sema, CIR→LLVM lowering, pipeline)
#
# Produces: libCOT.a
# Exports:  COT target (depends on CIR + MLIR)
# Install:  lib/libCOT.a, include/COT/*.h
#
# Reference: Flang FIRTransforms/FIRCodeGen CMakeLists.txt
#===----------------------------------------------------------------------===#

add_library(COT STATIC
  # Compiler-as-library API
  lib/Compiler.cpp
  # Configurable pass pipeline with extension points
  lib/Pipeline.cpp
  # C API
  c-api/COTCApi.cpp
  # CIR → CIR transformation passes
  lib/Transforms/SemanticAnalysis.cpp
  lib/Transforms/GenericSpecializer.cpp
  # CIR → LLVM lowering
  lib/CIRToLLVM.cpp
  lib/ArithmeticPatterns.cpp
  lib/BitwisePatterns.cpp
  lib/MemoryPatterns.cpp
  lib/ControlFlowPatterns.cpp
  lib/WitnessTablePatterns.cpp
)

# Include directories
target_include_directories(COT PUBLIC
  $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
  $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/c-api>
  $<INSTALL_INTERFACE:include>
)

# libac headers needed by Compiler.cpp (frontend dispatch)
target_include_directories(COT PRIVATE
  ${CMAKE_CURRENT_SOURCE_DIR}/../libac
)

# CIR dialect (CMake target — transitive includes propagate)
target_link_libraries(COT PUBLIC
  CIR
  MLIRIR
  MLIRSupport
  MLIRPass
  MLIRParser
  MLIRAsmParser
  MLIRLLVMDialect
  MLIRLLVMCommonConversion
  MLIRFuncDialect
  MLIRFuncToLLVM
  MLIRTargetLLVMIRExport
  MLIRBuiltinToLLVMIRTranslation
  MLIRLLVMToLLVMIRTranslation
)

#===----------------------------------------------------------------------===#
# Install
#===----------------------------------------------------------------------===#

install(TARGETS COT EXPORT COTTargets
  ARCHIVE DESTINATION lib)

install(DIRECTORY include/COT
  DESTINATION include
  FILES_MATCHING PATTERN "*.h")

# C API header
install(FILES c-api/COTCApi.h
  DESTINATION include/cot-c
  RENAME COT.h)
