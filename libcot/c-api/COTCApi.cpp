//===- COTCApi.cpp - COT compiler C API implementation ----------------===//
//
// C wrappers for COT pipeline operations.
//
//===----------------------------------------------------------------===//

#include "COTCApi.h"
#include "COT/Compiler.h"
#include "COT/Pipeline.h"

#include "mlir/CAPI/IR.h"
#include "mlir/CAPI/Pass.h"
#include "mlir/CAPI/Support.h"

using namespace mlir;

//===----------------------------------------------------------------------===//
// Context
//===----------------------------------------------------------------------===//

void cotInitContext(MlirContext ctx) {
  cot::initContext(*unwrap(ctx));
}

//===----------------------------------------------------------------------===//
// Simple Pipeline
//===----------------------------------------------------------------------===//

int cotRunSema(MlirModule module) {
  return cot::runSema(unwrap(module));
}

int cotLowerToLLVM(MlirModule module) {
  return cot::lowerToLLVM(unwrap(module));
}

int cotEmitBinary(MlirModule module, const char *outputPath) {
  return cot::emitBinary(unwrap(module), std::string(outputPath));
}

//===----------------------------------------------------------------------===//
// Configurable Pipeline
//===----------------------------------------------------------------------===//

CotPipelineBuilder cotPipelineBuilderCreate(MlirContext ctx) {
  auto *builder = new cot::PipelineBuilder(unwrap(ctx));
  return {builder};
}

void cotPipelineBuilderDestroy(CotPipelineBuilder builder) {
  delete static_cast<cot::PipelineBuilder *>(builder.ptr);
}

void cotPipelineBuilderAddPreSemaPass(CotPipelineBuilder builder,
                                      MlirPass pass) {
  static_cast<cot::PipelineBuilder *>(builder.ptr)
      ->addPreSemaPass(std::unique_ptr<Pass>(unwrap(pass)));
}

void cotPipelineBuilderAddPostSemaPass(CotPipelineBuilder builder,
                                       MlirPass pass) {
  static_cast<cot::PipelineBuilder *>(builder.ptr)
      ->addPostSemaPass(std::unique_ptr<Pass>(unwrap(pass)));
}

void cotPipelineBuilderAddPostLoweringPass(CotPipelineBuilder builder,
                                           MlirPass pass) {
  static_cast<cot::PipelineBuilder *>(builder.ptr)
      ->addPostLoweringPass(std::unique_ptr<Pass>(unwrap(pass)));
}

int cotPipelineBuilderRunToTypedCIR(CotPipelineBuilder builder,
                                    MlirModule module) {
  return static_cast<cot::PipelineBuilder *>(builder.ptr)
      ->runToTypedCIR(unwrap(module));
}

int cotPipelineBuilderRunToLLVM(CotPipelineBuilder builder,
                                MlirModule module) {
  return static_cast<cot::PipelineBuilder *>(builder.ptr)
      ->runToLLVM(unwrap(module));
}

int cotPipelineBuilderEmitBinary(CotPipelineBuilder builder,
                                 MlirModule module,
                                 const char *outputPath) {
  return static_cast<cot::PipelineBuilder *>(builder.ptr)
      ->emitBinary(unwrap(module), std::string(outputPath));
}
