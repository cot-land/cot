//===- Pipeline.cpp - COT configurable pass pipeline ------------------===//
//
// PipelineBuilder implementation. Replaces the hardcoded pipeline in
// Compiler.cpp with an extensible version that supports plugin passes.
//
// Reference: Flang's createDefaultFIROptimizerPassPipeline
//   ~/claude/references/flang-ref/flang/include/flang/Optimizer/Passes/Pipelines.h
//
//===----------------------------------------------------------------===//

#include "COT/Pipeline.h"
#include "COT/Passes.h"
#include "CIR/CIROps.h"

#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/IR/Verifier.h"
#include "mlir/Pass/PassManager.h"
#include "mlir/Target/LLVMIR/Export.h"
#include "mlir/Target/LLVMIR/Dialect/LLVMIR/LLVMToLLVMIRTranslation.h"
#include "mlir/Target/LLVMIR/Dialect/Builtin/BuiltinToLLVMIRTranslation.h"

#include "llvm/IR/Module.h"
#include "llvm/IR/LLVMContext.h"
#include "llvm/IR/LegacyPassManager.h"
#include "llvm/MC/TargetRegistry.h"
#include "llvm/Support/FileSystem.h"
#include "llvm/Support/TargetSelect.h"
#include "llvm/Support/Program.h"
#include "llvm/Support/raw_ostream.h"
#include "llvm/Target/TargetMachine.h"
#include "llvm/TargetParser/Host.h"

using namespace mlir;

namespace cot {

PipelineBuilder::PipelineBuilder(MLIRContext *ctx) : ctx_(ctx) {}

void PipelineBuilder::addPreSemaPass(std::unique_ptr<Pass> pass) {
  preSemaPasses_.push_back(std::move(pass));
}

void PipelineBuilder::addPostSemaPass(std::unique_ptr<Pass> pass) {
  postSemaPasses_.push_back(std::move(pass));
}

void PipelineBuilder::addPostLoweringPass(std::unique_ptr<Pass> pass) {
  postLoweringPasses_.push_back(std::move(pass));
}

int PipelineBuilder::runSemaStages(ModuleOp module) {
  // 1. Pre-Sema passes (raw CIR from frontend)
  if (!preSemaPasses_.empty()) {
    PassManager prePM(ctx_);
    for (auto &pass : preSemaPasses_)
      prePM.addPass(std::move(pass));
    if (failed(prePM.run(module))) {
      llvm::errs() << "error: pre-sema pass failed\n";
      return 1;
    }
  }

  // 2. Sema (type checking + cast insertion)
  {
    PassManager semaPM(ctx_);
    semaPM.enableVerifier(false); // IR may be invalid pre-Sema
    semaPM.addNestedPass<func::FuncOp>(createSemanticAnalysisPass());
    if (failed(semaPM.run(module))) {
      llvm::errs() << "error: semantic analysis failed\n";
      return 1;
    }
  }

  // 3. Generic specialization (monomorphize cir.generic_apply)
  {
    PassManager specPM(ctx_);
    specPM.addPass(createGenericSpecializerPass());
    if (failed(specPM.run(module))) {
      llvm::errs() << "error: generic specialization failed\n";
      return 1;
    }
  }

  // 4. Verify (after specialization, all types should be concrete)
  if (failed(verify(module))) {
    llvm::errs() << "error: verify failed after sema\n";
    return 1;
  }

  // 5. Post-Sema passes (typed, verified CIR)
  if (!postSemaPasses_.empty()) {
    PassManager postPM(ctx_);
    for (auto &pass : postSemaPasses_)
      postPM.addPass(std::move(pass));
    if (failed(postPM.run(module))) {
      llvm::errs() << "error: post-sema pass failed\n";
      return 1;
    }
  }

  return 0;
}

int PipelineBuilder::runLoweringStages(ModuleOp module) {
  // CIR + func → LLVM (shared type converter)
  {
    PassManager pm(ctx_);
    pm.addPass(createCIRToLLVMPass());
    if (failed(pm.run(module))) {
      llvm::errs() << "error: lowering failed\n";
      return 1;
    }
  }

  // Post-lowering passes (LLVM dialect)
  if (!postLoweringPasses_.empty()) {
    PassManager postPM(ctx_);
    for (auto &pass : postLoweringPasses_)
      postPM.addPass(std::move(pass));
    if (failed(postPM.run(module))) {
      llvm::errs() << "error: post-lowering pass failed\n";
      return 1;
    }
  }

  return 0;
}

int PipelineBuilder::runCodegen(ModuleOp module,
                                const std::string &outputPath) {
  // MLIR → LLVM IR
  registerBuiltinDialectTranslation(*ctx_);
  registerLLVMDialectTranslation(*ctx_);
  llvm::LLVMContext llvmCtx;
  auto llvmMod = translateModuleToLLVMIR(module, llvmCtx);
  if (!llvmMod) {
    llvm::errs() << "error: MLIR→LLVM IR failed\n";
    return 1;
  }

  // LLVM IR → .o
  llvm::InitializeNativeTarget();
  llvm::InitializeNativeTargetAsmPrinter();
  llvm::InitializeNativeTargetAsmParser();

  auto triple = llvm::sys::getDefaultTargetTriple();
  llvmMod->setTargetTriple(triple);

  std::string err;
  auto *target = llvm::TargetRegistry::lookupTarget(triple, err);
  if (!target) { llvm::errs() << err << "\n"; return 1; }

  auto tm = target->createTargetMachine(triple, "generic", "",
      llvm::TargetOptions(), std::nullopt);
  llvmMod->setDataLayout(tm->createDataLayout());

  llvm::SmallString<128> objPath;
  if (auto ec = llvm::sys::fs::createTemporaryFile("cot", "o", objPath)) {
    llvm::errs() << ec.message() << "\n";
    return 1;
  }
  std::error_code ec;
  llvm::raw_fd_ostream out(objPath, ec, llvm::sys::fs::OF_None);
  if (ec) { llvm::errs() << ec.message() << "\n"; return 1; }

  llvm::legacy::PassManager pass;
  if (tm->addPassesToEmitFile(pass, out, nullptr,
                              llvm::CodeGenFileType::ObjectFile)) {
    llvm::errs() << "error: can't emit object\n";
    return 1;
  }
  pass.run(*llvmMod);
  out.flush();

  // Link via cc
  auto ccPath = llvm::sys::findProgramByName("cc");
  if (!ccPath) { llvm::errs() << "error: cc not found\n"; return 1; }
  llvm::SmallVector<llvm::StringRef> linkArgs = {*ccPath, "-o", outputPath,
                                                  objPath};
  int linkResult = llvm::sys::ExecuteAndWait(*ccPath, linkArgs);
  llvm::sys::fs::remove(objPath);
  if (linkResult) { llvm::errs() << "error: link failed\n"; return 1; }

  return 0;
}

int PipelineBuilder::runToTypedCIR(ModuleOp module) {
  return runSemaStages(module);
}

int PipelineBuilder::runToLLVM(ModuleOp module) {
  if (int rc = runSemaStages(module)) return rc;
  return runLoweringStages(module);
}

int PipelineBuilder::emitBinary(ModuleOp module,
                                const std::string &outputPath) {
  if (int rc = runSemaStages(module)) return rc;
  if (int rc = runLoweringStages(module)) return rc;
  return runCodegen(module, outputPath);
}

} // namespace cot
