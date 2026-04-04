//===- Pipeline.h - COT configurable pass pipeline ---------------*- C++ -*-===//
//
// PipelineBuilder: configurable compilation pipeline with extension points.
// Language developers can inject custom CIR→CIR passes at three points:
//   1. Pre-Sema  — before type checking (desugaring, macro expansion)
//   2. Post-Sema — after type checking (optimization, linting, ARC)
//   3. Post-Lowering — after CIR→LLVM (target-specific transforms)
//
// Reference: MLIR PassManager, Flang's createDefaultFIROptimizerPassPipeline
//
//===----------------------------------------------------------------------===//
#ifndef COT_PIPELINE_H
#define COT_PIPELINE_H

#include "mlir/IR/BuiltinOps.h"
#include "mlir/Pass/Pass.h"
#include "llvm/ADT/SmallVector.h"

#include <memory>
#include <string>

namespace cot {

class PipelineBuilder {
public:
  explicit PipelineBuilder(mlir::MLIRContext *ctx);

  /// Add a pass to run before Sema (on raw frontend CIR).
  void addPreSemaPass(std::unique_ptr<mlir::Pass> pass);

  /// Add a pass to run after Sema (on typed, verified CIR).
  /// This is the primary extension point for optimization and analysis.
  void addPostSemaPass(std::unique_ptr<mlir::Pass> pass);

  /// Add a pass to run after CIR→LLVM lowering (on LLVM dialect).
  void addPostLoweringPass(std::unique_ptr<mlir::Pass> pass);

  /// Run full pipeline: [pre-sema] → Sema → verify → [post-sema] →
  ///   CIRToLLVM → [post-lowering] → LLVM IR → native binary.
  /// Returns 0 on success, 1 on failure.
  int emitBinary(mlir::ModuleOp module, const std::string &outputPath);

  /// Run up to typed CIR (no lowering): [pre-sema] → Sema → verify →
  ///   [post-sema]. For emit-cir command.
  /// Returns 0 on success, 1 on failure.
  int runToTypedCIR(mlir::ModuleOp module);

  /// Run up to LLVM dialect: [pre-sema] → Sema → verify → [post-sema] →
  ///   CIRToLLVM → [post-lowering]. For emit-llvm command.
  /// Returns 0 on success, 1 on failure.
  int runToLLVM(mlir::ModuleOp module);

private:
  mlir::MLIRContext *ctx_;
  llvm::SmallVector<std::unique_ptr<mlir::Pass>> preSemaPasses_;
  llvm::SmallVector<std::unique_ptr<mlir::Pass>> postSemaPasses_;
  llvm::SmallVector<std::unique_ptr<mlir::Pass>> postLoweringPasses_;

  /// Run pre-sema passes + Sema + verify + post-sema passes.
  /// Shared by all pipeline entry points.
  int runSemaStages(mlir::ModuleOp module);

  /// Run CIRToLLVM + post-lowering passes.
  int runLoweringStages(mlir::ModuleOp module);

  /// LLVM IR → native binary (object file + link).
  int runCodegen(mlir::ModuleOp module, const std::string &outputPath);
};

} // namespace cot

#endif // COT_PIPELINE_H
