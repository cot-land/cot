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
void populateWitnessTablePatterns(
    const mlir::LLVMTypeConverter &converter,
    mlir::RewritePatternSet &patterns);

//--- CIR → CIR transformation passes ---

/// Create the semantic analysis pass (type checking + cast insertion).
/// Reference: Zig Sema, Flang Transforms.
std::unique_ptr<mlir::Pass> createSemanticAnalysisPass();

/// Create the generic specializer pass (monomorphize generic functions).
/// Finds cir.generic_apply ops, clones generic function bodies with concrete
/// types substituted for !cir.type_param, replaces generic_apply with func.call.
/// Must run BEFORE CIR→LLVM lowering (type_param can't lower to LLVM).
/// Reference: Swift GenericSpecializer.
std::unique_ptr<mlir::Pass> createGenericSpecializerPass();

//--- CIR → LLVM lowering pass ---

/// Create the CIR → LLVM dialect lowering pass.
std::unique_ptr<mlir::Pass> createCIRToLLVMPass();

} // namespace cot

#endif // COT_PASSES_H
