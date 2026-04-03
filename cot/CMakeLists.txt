cmake_minimum_required(VERSION 3.20.0)
project(cot-driver LANGUAGES CXX C)

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
include_directories(${PROJECT_SOURCE_DIR}/../libcir/include)
include_directories(${PROJECT_SOURCE_DIR}/../libcir/build/include)
include_directories(${PROJECT_SOURCE_DIR}/../libac)

link_directories(${LLVM_BUILD_LIBRARY_DIR})
add_definitions(${LLVM_DEFINITIONS})

add_executable(cot
  main.cpp
  ../libac/scanner.cpp
  ../libac/parser.cpp
  ../libac/codegen.cpp
)

target_link_libraries(cot PRIVATE
  # libcir
  ${PROJECT_SOURCE_DIR}/../libcir/build/libCIR.a

  # MLIR core
  MLIRIR MLIRSupport MLIRDialect MLIRPass MLIRFuncDialect
  MLIRParser MLIRAsmParser MLIRBytecodeReader MLIRBytecodeWriter MLIRBytecodeOpInterface

  # MLIR LLVM lowering
  MLIRLLVMDialect MLIRLLVMCommonConversion MLIRFuncToLLVM MLIRArithToLLVM
  MLIRTargetLLVMIRExport MLIRBuiltinToLLVMIRTranslation MLIRLLVMToLLVMIRTranslation

  # MLIR C API
  MLIRCAPIIR

  # LLVM core
  LLVMCore LLVMSupport LLVMDemangle LLVMTarget LLVMMCParser LLVMMC LLVMTargetParser

  # LLVM ARM64
  LLVMAArch64CodeGen LLVMAArch64Desc LLVMAArch64Info LLVMAArch64AsmParser LLVMAArch64Utils

  # LLVM codegen
  LLVMCodeGen LLVMCodeGenTypes LLVMScalarOpts LLVMAnalysis LLVMTransformUtils
  LLVMInstCombine LLVMipo LLVMBitWriter LLVMObjCARCOpts LLVMAggressiveInstCombine
  LLVMCoroutines LLVMVectorize LLVMGlobalISel LLVMSelectionDAG LLVMAsmPrinter
  LLVMCFGuard LLVMBinaryFormat LLVMObject LLVMIRReader LLVMBitReader LLVMAsmParser
  LLVMProfileData LLVMInstrumentation LLVMPasses LLVMRemarks LLVMBitstreamReader
  LLVMDebugInfoDWARF LLVMDebugInfoCodeView LLVMTextAPI
)

if(APPLE)
  target_link_libraries(cot PRIVATE "-framework CoreFoundation" "-lz" "-lcurses")
endif()
