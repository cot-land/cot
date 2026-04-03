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

/// Populate ALL CIR → LLVM lowering patterns.
/// Calls the category-specific functions below.
void populateCIRToLLVMConversionPatterns(
    const mlir::LLVMTypeConverter &converter,
    mlir::RewritePatternSet &patterns);

/// Category-specific pattern population (for selective use).
void populateArithmeticPatterns(
    const mlir::LLVMTypeConverter &converter,
    mlir::RewritePatternSet &patterns);
void populateBitwisePatterns(
    const mlir::LLVMTypeConverter &converter,
    mlir::RewritePatternSet &patterns);
void populateMemoryPatterns(
    const mlir::LLVMTypeConverter &converter,
    mlir::RewritePatternSet &patterns);
void populateControlFlowPatterns(
    const mlir::LLVMTypeConverter &converter,
    mlir::RewritePatternSet &patterns);

/// Create the CIR → LLVM dialect lowering pass.
std::unique_ptr<mlir::Pass> createCIRToLLVMPass();

} // namespace cot

#endif // COT_PASSES_H
