//===- COTCApi.h - COT compiler C API ---------------------------*- C -*-===//
//
// C API for the COT compiler pipeline.
// Run Sema, lower to LLVM, emit binaries — from any language.
//
// Reference: mlir-c/Pass.h pattern.
//
//===------------------------------------------------------------------===//

#ifndef COT_C_API_H
#define COT_C_API_H

#include "mlir-c/IR.h"
#include "mlir-c/Pass.h"

#ifdef __cplusplus
extern "C" {
#endif

//===----------------------------------------------------------------------===//
// Context Initialization
//===----------------------------------------------------------------------===//

/// Initialize an MLIR context with all CIR-required dialects.
void cotInitContext(MlirContext ctx);

//===----------------------------------------------------------------------===//
// Simple Pipeline (one-call convenience)
//===----------------------------------------------------------------------===//

/// Run Sema (type checking + cast insertion). Returns 0/1.
int cotRunSema(MlirModule module);

/// Lower CIR → LLVM dialect. Returns 0/1.
int cotLowerToLLVM(MlirModule module);

/// Full pipeline: Sema → verify → lower → LLVM IR → native binary. Returns 0/1.
int cotEmitBinary(MlirModule module, const char *outputPath);

//===----------------------------------------------------------------------===//
// Configurable Pipeline
//===----------------------------------------------------------------------===//

/// Opaque pipeline builder handle.
typedef struct { void *ptr; } CotPipelineBuilder;

/// Create a pipeline builder.
CotPipelineBuilder cotPipelineBuilderCreate(MlirContext ctx);

/// Destroy a pipeline builder.
void cotPipelineBuilderDestroy(CotPipelineBuilder builder);

/// Add a pass to run before Sema (on raw frontend CIR).
void cotPipelineBuilderAddPreSemaPass(CotPipelineBuilder builder,
                                      MlirPass pass);

/// Add a pass to run after Sema (on typed, verified CIR).
void cotPipelineBuilderAddPostSemaPass(CotPipelineBuilder builder,
                                       MlirPass pass);

/// Add a pass to run after CIR→LLVM lowering.
void cotPipelineBuilderAddPostLoweringPass(CotPipelineBuilder builder,
                                           MlirPass pass);

/// Run pipeline up to typed CIR. Returns 0/1.
int cotPipelineBuilderRunToTypedCIR(CotPipelineBuilder builder,
                                    MlirModule module);

/// Run pipeline up to LLVM dialect. Returns 0/1.
int cotPipelineBuilderRunToLLVM(CotPipelineBuilder builder,
                                MlirModule module);

/// Run full pipeline to native binary. Returns 0/1.
int cotPipelineBuilderEmitBinary(CotPipelineBuilder builder,
                                 MlirModule module,
                                 const char *outputPath);

#ifdef __cplusplus
}
#endif

#endif // COT_C_API_H
