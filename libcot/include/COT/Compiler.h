//===- Compiler.h - COT compiler library API --------------------*- C++ -*-===//
//
// Compiler-as-library: pipeline orchestration, frontend dispatch, codegen.
// The cot CLI is a thin wrapper around this API.
//
// Reference: Clang's libclang pattern — compiler logic in library, CLI is
// just argument parsing.
//
//===----------------------------------------------------------------------===//
#ifndef COT_COMPILER_H
#define COT_COMPILER_H

#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/IR/OwningOpRef.h"

#include <string>

namespace cot {

/// Initialize an MLIRContext with all required dialects for CIR compilation.
void initContext(mlir::MLIRContext &ctx);

/// Parse a source file into a CIR MLIR module.
/// Dispatches to the correct frontend based on file extension (.ac, .zig, .ts).
/// If testMode is true, ac frontend wraps test blocks in a runner main.
mlir::OwningOpRef<mlir::ModuleOp> parseSourceToCIR(
    mlir::MLIRContext &ctx, const std::string &inputFile,
    const std::string &source, bool testMode = false);

/// Run Sema (type checking + cast insertion) on a CIR module.
/// Returns 0 on success, 1 on failure.
int runSema(mlir::ModuleOp module);

/// Lower CIR to LLVM dialect (includes func-to-llvm with shared type converter).
/// Returns 0 on success, 1 on failure.
int lowerToLLVM(mlir::ModuleOp module);

/// Full pipeline: Sema → verify → lower → LLVM IR → object → link → binary.
/// Returns 0 on success, 1 on failure.
int emitBinary(mlir::ModuleOp module, const std::string &outputPath);

/// Run an executable with a timeout. Returns exit code, or -1 on timeout.
int runWithTimeout(const std::string &path, unsigned timeoutSeconds = 10);

/// Read a file into a string. Returns empty string on failure.
std::string readFile(const std::string &path);

} // namespace cot

#endif // COT_COMPILER_H
