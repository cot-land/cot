//===- main.cpp - COT compiler driver --------------------------------===//
//
// cot build <file.ac> [-o output]    compile ac source to native binary
// cot test                           run gate test (hardcoded CIR module)
//
//===----------------------------------------------------------------===//

#include "CIR/CIROps.h"
#include "COT/Passes.h"
#include "scanner.h"
#include "parser.h"
#include "codegen.h"

// libzc C ABI — Zig frontend
extern "C" int zc_parse(
    const char *source_ptr, size_t source_len,
    const char *filename,
    const char **out_ptr, size_t *out_len);

#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/Verifier.h"
#include "mlir/Pass/PassManager.h"
#include "mlir/Conversion/FuncToLLVM/ConvertFuncToLLVMPass.h"
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
#include "llvm/Support/raw_ostream.h"
#include "llvm/Target/TargetMachine.h"
#include "llvm/TargetParser/Host.h"

#include "llvm/Support/MemoryBuffer.h"

#include <cstdlib>
#include <string>

using namespace mlir;

//===----------------------------------------------------------------------===//
// Backend: MLIR → object file → link
//===----------------------------------------------------------------------===//

static int emitBinary(ModuleOp module, const std::string &outputPath) {
  MLIRContext *ctx = module.getContext();

  // CIR → LLVM, func → LLVM (via libcot)
  PassManager pm(ctx);
  pm.addPass(cot::createCIRToLLVMPass());
  pm.addPass(createConvertFuncToLLVMPass(ConvertFuncToLLVMPassOptions{}));
  if (failed(pm.run(module))) { llvm::errs() << "error: lowering failed\n"; return 1; }

  // MLIR → LLVM IR
  registerBuiltinDialectTranslation(*ctx);
  registerLLVMDialectTranslation(*ctx);
  llvm::LLVMContext llvmCtx;
  auto llvmMod = translateModuleToLLVMIR(module, llvmCtx);
  if (!llvmMod) { llvm::errs() << "error: MLIR→LLVM IR failed\n"; return 1; }

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
    llvm::errs() << ec.message() << "\n"; return 1;
  }
  std::error_code ec;
  llvm::raw_fd_ostream out(objPath, ec, llvm::sys::fs::OF_None);
  if (ec) { llvm::errs() << ec.message() << "\n"; return 1; }

  llvm::legacy::PassManager pass;
  if (tm->addPassesToEmitFile(pass, out, nullptr, llvm::CodeGenFileType::ObjectFile)) {
    llvm::errs() << "error: can't emit object\n"; return 1;
  }
  pass.run(*llvmMod);
  out.flush();

  // Link via cc (safe invocation, no shell)
  auto ccPath = llvm::sys::findProgramByName("cc");
  if (!ccPath) { llvm::errs() << "error: cc not found\n"; return 1; }
  llvm::SmallVector<llvm::StringRef> linkArgs = {
      *ccPath, "-o", outputPath, objPath};
  int linkResult = llvm::sys::ExecuteAndWait(*ccPath, linkArgs);
  llvm::sys::fs::remove(objPath);
  if (linkResult) { llvm::errs() << "error: link failed\n"; return 1; }

  return 0;
}

//===----------------------------------------------------------------------===//
// Lower CIR only (no LLVM IR translation, no object file)
//===----------------------------------------------------------------------===//

static int lowerCIRToLLVMDialect(ModuleOp module) {
  MLIRContext *ctx = module.getContext();
  PassManager pm(ctx);
  pm.addPass(cot::createCIRToLLVMPass());
  pm.addPass(createConvertFuncToLLVMPass(ConvertFuncToLLVMPassOptions{}));
  if (failed(pm.run(module))) { llvm::errs() << "error: lowering failed\n"; return 1; }
  return 0;
}

//===----------------------------------------------------------------------===//
// Parse source file into CIR module (works for .ac and .zig)
//===----------------------------------------------------------------------===//

static OwningOpRef<ModuleOp> parseSourceToCIR(MLIRContext &ctx,
    const std::string &inputFile, const std::string &source,
    bool testMode = false) {
  bool isZig = inputFile.size() >= 4 &&
      inputFile.substr(inputFile.size() - 4) == ".zig";

  if (isZig) {
    const char *cirBytes = nullptr;
    size_t cirLen = 0;
    int rc = zc_parse(source.data(), source.size(), inputFile.c_str(), &cirBytes, &cirLen);
    if (rc != 0) { llvm::errs() << "error: zig frontend failed\n"; return {}; }
    ParserConfig config(&ctx);
    return parseSourceString<ModuleOp>(llvm::StringRef(cirBytes, cirLen), config);
  }

  // ac frontend
  auto tokens = ac::scanAll(source);
  auto ast = ac::parse(source, tokens);
  return ac::codegen(ctx, source, ast, testMode);
}

//===----------------------------------------------------------------------===//
// CLI
//===----------------------------------------------------------------------===//

static std::string readFile(const std::string &path) {
  auto bufOrErr = llvm::MemoryBuffer::getFile(path);
  if (!bufOrErr) return "";
  return (*bufOrErr)->getBuffer().str();
}

int main(int argc, char **argv) {
  if (argc < 2) {
    llvm::outs() << "cot — compiler toolkit\n\n"
                 << "Usage:\n"
                 << "  cot build <file>      compile to native binary\n"
                 << "  cot test <file.ac>    run inline tests\n"
                 << "  cot test              run gate test\n"
                 << "  cot emit-cir <file>   print CIR MLIR text\n"
                 << "  cot emit-llvm <file>  print LLVM dialect text\n"
                 << "  cot version\n";
    return 1;
  }

  std::string cmd = argv[1];
  if (cmd == "version") { llvm::outs() << "cot 0.1.0\n"; return 0; }

  MLIRContext ctx;
  ctx.getOrLoadDialect<cir::CIRDialect>();
  ctx.getOrLoadDialect<func::FuncDialect>();
  ctx.getOrLoadDialect<LLVM::LLVMDialect>();

  // ---- cot test [file.ac] ----
  if (cmd == "test") {
    if (argc >= 3) {
      // Zig pattern: cot test file.ac — compile and run inline test blocks
      std::string inputFile = argv[2];
      auto source = readFile(inputFile);
      if (source.empty()) { llvm::errs() << "error: can't read " << inputFile << "\n"; return 1; }

      auto tokens = ac::scanAll(source);
      auto ast = ac::parse(source, tokens);

      if (ast.tests.empty()) {
        llvm::errs() << "no tests found in " << inputFile << "\n";
        return 1;
      }

      auto module = ac::codegen(ctx, source, ast, /*testMode=*/true);
      if (failed(verify(*module))) { llvm::errs() << "error: verify failed\n"; return 1; }
      if (emitBinary(*module, "/tmp/cot_test")) return 1;

      llvm::outs() << "running " << ast.tests.size() << " test(s) from " << inputFile << "\n";
      int rc = std::system("/tmp/cot_test");
      int code = WEXITSTATUS(rc);
      if (code == 0) {
        llvm::outs() << "all tests passed\n";
      } else {
        llvm::errs() << "test failed (signal " << code << ")\n";
      }
      return code;
    }

    // No file: hardcoded gate test
    OpBuilder b(&ctx);
    auto loc = b.getUnknownLoc();
    auto module = ModuleOp::create(loc);
    auto i32 = b.getI32Type();

    auto addFn = func::FuncOp::create(loc, "add", b.getFunctionType({i32, i32}, {i32}));
    addFn.setPrivate();
    auto *entry = addFn.addEntryBlock();
    { OpBuilder::InsertionGuard g(b); b.setInsertionPointToStart(entry);
      auto sum = b.create<cir::AddOp>(loc, i32, entry->getArgument(0), entry->getArgument(1));
      b.create<func::ReturnOp>(loc, ValueRange{sum});
    }
    module.push_back(addFn);

    auto mainFn = func::FuncOp::create(loc, "main", b.getFunctionType({}, {i32}));
    auto *mainEntry = mainFn.addEntryBlock();
    { OpBuilder::InsertionGuard g(b); b.setInsertionPointToStart(mainEntry);
      auto c19 = b.create<cir::ConstantOp>(loc, i32, b.getI32IntegerAttr(19));
      auto c23 = b.create<cir::ConstantOp>(loc, i32, b.getI32IntegerAttr(23));
      auto call = b.create<func::CallOp>(loc, "add", TypeRange{i32}, ValueRange{c19, c23});
      b.create<func::ReturnOp>(loc, call.getResults());
    }
    module.push_back(mainFn);

    if (failed(verify(module))) { llvm::errs() << "verify failed\n"; return 1; }
    if (emitBinary(module, "/tmp/cot_test")) return 1;
    int rc = std::system("/tmp/cot_test");
    int code = WEXITSTATUS(rc);
    llvm::outs() << "add(19, 23) = " << code << (code == 42 ? " ✓\n" : " ✗\n");
    return code == 42 ? 0 : 1;
  }

  // ---- cot emit-cir <file> — print CIR MLIR text (for lit/FileCheck) ----
  if (cmd == "emit-cir" && argc >= 3) {
    std::string inputFile = argv[2];
    auto source = readFile(inputFile);
    if (source.empty()) { llvm::errs() << "error: can't read " << inputFile << "\n"; return 1; }
    auto module = parseSourceToCIR(ctx, inputFile, source);
    if (!module) return 1;
    if (failed(verify(*module))) { llvm::errs() << "error: verify failed\n"; return 1; }
    (*module)->print(llvm::outs());
    return 0;
  }

  // ---- cot emit-llvm <file> — print LLVM dialect MLIR text ----
  if (cmd == "emit-llvm" && argc >= 3) {
    std::string inputFile = argv[2];
    auto source = readFile(inputFile);
    if (source.empty()) { llvm::errs() << "error: can't read " << inputFile << "\n"; return 1; }
    auto module = parseSourceToCIR(ctx, inputFile, source);
    if (!module) return 1;
    if (failed(verify(*module))) { llvm::errs() << "error: verify failed\n"; return 1; }
    if (lowerCIRToLLVMDialect(*module)) return 1;
    (*module)->print(llvm::outs());
    return 0;
  }

  // ---- cot build <file> — compile to native binary ----
  if (cmd == "build" && argc >= 3) {
    std::string inputFile = argv[2];
    std::string outputFile = "a.out";
    if (argc >= 5 && std::string(argv[3]) == "-o") outputFile = argv[4];

    auto source = readFile(inputFile);
    if (source.empty()) { llvm::errs() << "error: can't read " << inputFile << "\n"; return 1; }

    auto module = parseSourceToCIR(ctx, inputFile, source);
    if (!module) return 1;
    if (failed(verify(*module))) { llvm::errs() << "error: verify failed\n"; return 1; }
    if (emitBinary(*module, outputFile)) return 1;
    llvm::outs() << outputFile << "\n";
    return 0;
  }

  llvm::errs() << "unknown command: " << cmd << "\n";
  return 1;
}
