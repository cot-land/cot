//===- Compiler.cpp - COT compiler library implementation -------------===//
//
// Pipeline orchestration, frontend dispatch, codegen.
// Moved from cot/main.cpp to libcot for compiler-as-library support.
//
// Reference: Clang's CompilerInstance — compiler logic in library.
//
//===----------------------------------------------------------------===//

#include "COT/Compiler.h"
#include "COT/Passes.h"
#include "CIR/CIROps.h"

// ac frontend (C++)
#include "scanner.h"
#include "parser.h"
#include "codegen.h"

// libzc C ABI — Zig frontend
extern "C" int zc_parse(
    const char *source_ptr, size_t source_len,
    const char *filename,
    const char **out_ptr, size_t *out_len);

// libtc C ABI — TypeScript frontend (Go)
extern "C" int tc_parse(
    char *source_ptr, size_t source_len,
    char *filename,
    char **out_ptr, size_t *out_len);

#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/Verifier.h"
#include "mlir/Pass/PassManager.h"
#include "mlir/Parser/Parser.h"
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
#include "llvm/Support/MemoryBuffer.h"
#include "llvm/Support/raw_ostream.h"
#include "llvm/Target/TargetMachine.h"
#include "llvm/TargetParser/Host.h"

using namespace mlir;

//===----------------------------------------------------------------------===//
// Context initialization
//===----------------------------------------------------------------------===//

void cot::initContext(MLIRContext &ctx) {
  ctx.getOrLoadDialect<cir::CIRDialect>();
  ctx.getOrLoadDialect<func::FuncDialect>();
  ctx.getOrLoadDialect<LLVM::LLVMDialect>();
}

//===----------------------------------------------------------------------===//
// File I/O
//===----------------------------------------------------------------------===//

std::string cot::readFile(const std::string &path) {
  auto bufOrErr = llvm::MemoryBuffer::getFile(path);
  if (!bufOrErr) return "";
  return (*bufOrErr)->getBuffer().str();
}

//===----------------------------------------------------------------------===//
// Frontend dispatch
//===----------------------------------------------------------------------===//

static bool endsWith(const std::string &s, const std::string &suffix) {
  return s.size() >= suffix.size() &&
      s.compare(s.size() - suffix.size(), suffix.size(), suffix) == 0;
}

OwningOpRef<ModuleOp> cot::parseSourceToCIR(MLIRContext &ctx,
    const std::string &inputFile, const std::string &source,
    bool testMode) {

  // Zig frontend
  if (endsWith(inputFile, ".zig")) {
    const char *cirBytes = nullptr;
    size_t cirLen = 0;
    int rc = zc_parse(source.data(), source.size(), inputFile.c_str(),
                      &cirBytes, &cirLen);
    if (rc != 0) { llvm::errs() << "error: zig frontend failed\n"; return {}; }
    ParserConfig config(&ctx);
    return parseSourceString<ModuleOp>(llvm::StringRef(cirBytes, cirLen), config);
  }

  // TypeScript frontend
  if (endsWith(inputFile, ".ts")) {
    char *cirBytes = nullptr;
    size_t cirLen = 0;
    int rc = tc_parse(const_cast<char*>(source.data()), source.size(),
        const_cast<char*>(inputFile.c_str()), &cirBytes, &cirLen);
    if (rc != 0) { llvm::errs() << "error: typescript frontend failed\n"; return {}; }
    ParserConfig config(&ctx);
    auto result = parseSourceString<ModuleOp>(
        llvm::StringRef(cirBytes, cirLen), config);
    free(cirBytes);
    return result;
  }

  // ac frontend (default)
  auto tokens = ac::scanAll(source);
  auto ast = ac::parse(source, tokens);
  return ac::codegen(ctx, source, ast, testMode);
}

//===----------------------------------------------------------------------===//
// Pipeline stages
//===----------------------------------------------------------------------===//

int cot::runSema(ModuleOp module) {
  MLIRContext *ctx = module.getContext();
  PassManager semaPM(ctx);
  semaPM.enableVerifier(false); // IR may be invalid pre-Sema
  semaPM.addNestedPass<func::FuncOp>(createSemanticAnalysisPass());
  if (failed(semaPM.run(module))) {
    llvm::errs() << "error: semantic analysis failed\n";
    return 1;
  }
  if (failed(verify(module))) {
    llvm::errs() << "error: verify failed after sema\n";
    return 1;
  }
  return 0;
}

int cot::lowerToLLVM(ModuleOp module) {
  MLIRContext *ctx = module.getContext();
  // Sema first
  {
    PassManager semaPM(ctx);
    semaPM.enableVerifier(false);
    semaPM.addNestedPass<func::FuncOp>(createSemanticAnalysisPass());
    if (failed(semaPM.run(module))) {
      llvm::errs() << "error: sema failed\n";
      return 1;
    }
  }
  // CIR + func → LLVM (shared type converter)
  PassManager pm(ctx);
  pm.addPass(createCIRToLLVMPass());
  if (failed(pm.run(module))) {
    llvm::errs() << "error: lowering failed\n";
    return 1;
  }
  return 0;
}

int cot::emitBinary(ModuleOp module, const std::string &outputPath) {
  MLIRContext *ctx = module.getContext();

  // Sema
  {
    PassManager semaPM(ctx);
    semaPM.enableVerifier(false);
    semaPM.addNestedPass<func::FuncOp>(createSemanticAnalysisPass());
    if (failed(semaPM.run(module))) {
      llvm::errs() << "error: semantic analysis failed\n";
      return 1;
    }
  }
  if (failed(verify(module))) {
    llvm::errs() << "error: verify failed after sema\n";
    return 1;
  }

  // Lower CIR + func → LLVM
  PassManager pm(ctx);
  pm.addPass(createCIRToLLVMPass());
  if (failed(pm.run(module))) {
    llvm::errs() << "error: lowering failed\n";
    return 1;
  }

  // MLIR → LLVM IR
  registerBuiltinDialectTranslation(*ctx);
  registerLLVMDialectTranslation(*ctx);
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
  llvm::SmallVector<llvm::StringRef> linkArgs = {*ccPath, "-o", outputPath, objPath};
  int linkResult = llvm::sys::ExecuteAndWait(*ccPath, linkArgs);
  llvm::sys::fs::remove(objPath);
  if (linkResult) { llvm::errs() << "error: link failed\n"; return 1; }

  return 0;
}

//===----------------------------------------------------------------------===//
// Process execution
//===----------------------------------------------------------------------===//

int cot::runWithTimeout(const std::string &path, unsigned timeoutSeconds) {
  auto prog = llvm::sys::findProgramByName(path);
  llvm::StringRef execPath = prog ? llvm::StringRef(*prog) : llvm::StringRef(path);
  llvm::SmallVector<llvm::StringRef> args = {execPath};
  std::string errMsg;
  bool execFailed = false;
  int rc = llvm::sys::ExecuteAndWait(execPath, args,
      /*Env=*/std::nullopt, /*Redirects=*/{},
      timeoutSeconds, /*MemoryLimit=*/0, &errMsg, &execFailed);
  if (execFailed && !errMsg.empty()) {
    llvm::errs() << "error: " << errMsg << "\n";
    return -1;
  }
  return rc;
}
