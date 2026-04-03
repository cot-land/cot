//===- Passes.h - COT compiler passes ----------------------------*- C++ -*-===//
//
// Public API for COT compiler passes.
// libcot is the compiler pass library for the COT toolkit.
//
// Architecture: Each pass transforms CIR (MLIR dialect) → CIR or CIR → LLVM.
// References: ~/claude/references/llvm-project/mlir/lib/Conversion/
//
//===----------------------------------------------------------------------===//
#ifndef COT_PASSES_H
#define COT_PASSES_H

#include "mlir/Pass/Pass.h"
#include "mlir/Transforms/DialectConversion.h"

namespace mlir {
class LLVMTypeConverter;
} // namespace mlir

namespace cot {

/// Populate the pattern set with CIR → LLVM dialect lowering patterns.
/// Reference: arith::populateArithToLLVMConversionPatterns()
void populateCIRToLLVMConversionPatterns(
    const mlir::LLVMTypeConverter &converter,
    mlir::RewritePatternSet &patterns);

/// Create the CIR → LLVM dialect lowering pass.
/// Lowers all CIR ops to LLVM dialect equivalents.
/// Reference: MLIR ConversionPatterns (Lattner's canonical lowering pattern)
std::unique_ptr<mlir::Pass> createCIRToLLVMPass();

} // namespace cot

#endif // COT_PASSES_H
