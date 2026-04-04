//===- Compiler.cpp - COT compiler library implementation -------------===//
//
// Pipeline orchestration, frontend dispatch, codegen.
// Moved from cot/main.cpp to libcot for compiler-as-library support.
//
// Reference: Clang's CompilerInstance — compiler logic in library.
//
//===----------------------------------------------------------------===//

#include "COT/Compiler.h"
#include "COT/Pipeline.h"
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
#include "mlir/Parser/Parser.h"

#include "llvm/Support/MemoryBuffer.h"
#include "llvm/Support/Program.h"
#include "llvm/Support/raw_ostream.h"

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
// Pipeline stages — delegate to PipelineBuilder
//===----------------------------------------------------------------------===//

int cot::runSema(ModuleOp module) {
  PipelineBuilder pipeline(module.getContext());
  return pipeline.runToTypedCIR(module);
}

int cot::lowerToLLVM(ModuleOp module) {
  PipelineBuilder pipeline(module.getContext());
  return pipeline.runToLLVM(module);
}

int cot::emitBinary(ModuleOp module, const std::string &outputPath) {
  PipelineBuilder pipeline(module.getContext());
  return pipeline.emitBinary(module, outputPath);
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
