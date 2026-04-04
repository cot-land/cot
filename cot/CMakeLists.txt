#===----------------------------------------------------------------------===#
# cot — CLI driver executable
#
# Links: COT (passes), CIR (dialect), libac (C++ sources compiled in),
#        libzc (Zig frontend .a), libtc (TypeScript frontend .a)
#
# libzc and libtc are pre-built by Zig/Go toolchains (not CMake).
# The Makefile ensures they are built before this target.
#===----------------------------------------------------------------------===#

add_executable(cot
  main.cpp
  # libac sources compiled directly into the driver
  ../libac/scanner.cpp
  ../libac/parser.cpp
  ../libac/codegen.cpp
)

# libac headers
target_include_directories(cot PRIVATE
  ${CMAKE_CURRENT_SOURCE_DIR}/../libac
)

# COT and CIR (CMake targets — transitive deps handled automatically)
target_link_libraries(cot PRIVATE
  COT
  CIR
)

# External frontends (pre-built archives, non-CMake)
# libtc — TypeScript frontend (Go, C ABI)
target_link_libraries(cot PRIVATE
  ${CMAKE_CURRENT_SOURCE_DIR}/../libtc/libtc.a
)
# libzc — Zig frontend (C ABI)
target_link_libraries(cot PRIVATE
  ${CMAKE_CURRENT_SOURCE_DIR}/../libzc/zig-out/lib/libzc.a
)

# MLIR libraries needed by the driver but not transitively from COT
target_link_libraries(cot PRIVATE
  MLIRDialect
  MLIRBytecodeReader
  MLIRBytecodeWriter
  MLIRBytecodeOpInterface
  MLIRArithToLLVM
  MLIRCAPIIR
)

# LLVM backend libraries
target_link_libraries(cot PRIVATE
  LLVMCore LLVMSupport LLVMDemangle LLVMTarget LLVMMCParser LLVMMC
  LLVMTargetParser
  # ARM64
  LLVMAArch64CodeGen LLVMAArch64Desc LLVMAArch64Info
  LLVMAArch64AsmParser LLVMAArch64Utils
  # Codegen pipeline
  LLVMCodeGen LLVMCodeGenTypes LLVMScalarOpts LLVMAnalysis LLVMTransformUtils
  LLVMInstCombine LLVMipo LLVMBitWriter LLVMObjCARCOpts
  LLVMAggressiveInstCombine LLVMCoroutines LLVMVectorize LLVMGlobalISel
  LLVMSelectionDAG LLVMAsmPrinter LLVMCFGuard LLVMBinaryFormat LLVMObject
  LLVMIRReader LLVMBitReader LLVMAsmParser LLVMProfileData
  LLVMInstrumentation LLVMPasses LLVMRemarks LLVMBitstreamReader
  LLVMDebugInfoDWARF LLVMDebugInfoCodeView LLVMTextAPI
)

# Platform libraries
if(APPLE)
  target_link_libraries(cot PRIVATE
    "-framework CoreFoundation"
    "-framework Security"
    "-lz" "-lcurses" "-lresolv" "-lpthread"
  )
endif()

# Install
install(TARGETS cot RUNTIME DESTINATION bin)
