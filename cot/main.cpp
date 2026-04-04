//===- main.cpp - COT CLI driver (thin wrapper) -----------------------===//
//
// Argument parsing only. All compiler logic is in libcot (COT/Compiler.h).
//
//===----------------------------------------------------------------===//

#include "COT/Compiler.h"
#include "CIR/CIROps.h"

#include "mlir/IR/Builders.h"
#include "mlir/IR/Verifier.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "llvm/Support/raw_ostream.h"

#include <string>

using namespace mlir;

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
  cot::initContext(ctx);

  // ---- cot test [file.ac] ----
  if (cmd == "test") {
    if (argc >= 3) {
      std::string inputFile = argv[2];
      auto source = cot::readFile(inputFile);
      if (source.empty()) {
        llvm::errs() << "error: can't read " << inputFile << "\n";
        return 1;
      }
      auto module = cot::parseSourceToCIR(ctx, inputFile, source, true);
      if (!module) return 1;
      if (cot::emitBinary(*module, "/tmp/cot_test")) return 1;
      int code = cot::runWithTimeout("/tmp/cot_test");
      if (code == -1) {
        llvm::errs() << "test timed out (infinite loop?)\n";
        return 1;
      }
      if (code == 0) llvm::outs() << "all tests passed\n";
      else llvm::errs() << "test failed (exit " << code << ")\n";
      return code;
    }

    // No file: hardcoded gate test
    OpBuilder b(&ctx);
    auto loc = b.getUnknownLoc();
    auto module = ModuleOp::create(loc);
    auto i32 = b.getI32Type();

    auto addFn = func::FuncOp::create(loc, "add",
        b.getFunctionType({i32, i32}, {i32}));
    addFn.setPrivate();
    auto *entry = addFn.addEntryBlock();
    { OpBuilder::InsertionGuard g(b); b.setInsertionPointToStart(entry);
      auto sum = b.create<cir::AddOp>(loc, i32,
          entry->getArgument(0), entry->getArgument(1));
      b.create<func::ReturnOp>(loc, ValueRange{sum});
    }
    module.push_back(addFn);

    auto mainFn = func::FuncOp::create(loc, "main",
        b.getFunctionType({}, {i32}));
    auto *mainEntry = mainFn.addEntryBlock();
    { OpBuilder::InsertionGuard g(b); b.setInsertionPointToStart(mainEntry);
      auto c19 = b.create<cir::ConstantOp>(loc, i32, b.getI32IntegerAttr(19));
      auto c23 = b.create<cir::ConstantOp>(loc, i32, b.getI32IntegerAttr(23));
      auto call = b.create<func::CallOp>(loc, "add",
          TypeRange{i32}, ValueRange{c19, c23});
      b.create<func::ReturnOp>(loc, call.getResults());
    }
    module.push_back(mainFn);

    if (failed(verify(module))) { llvm::errs() << "verify failed\n"; return 1; }
    if (cot::emitBinary(module, "/tmp/cot_test")) return 1;
    int code = cot::runWithTimeout("/tmp/cot_test");
    llvm::outs() << "add(19, 23) = " << code
                 << (code == 42 ? " ✓\n" : " ✗\n");
    return code == 42 ? 0 : 1;
  }

  // ---- cot emit-cir <file> ----
  if (cmd == "emit-cir" && argc >= 3) {
    std::string inputFile = argv[2];
    auto source = cot::readFile(inputFile);
    if (source.empty()) {
      llvm::errs() << "error: can't read " << inputFile << "\n";
      return 1;
    }
    auto module = cot::parseSourceToCIR(ctx, inputFile, source);
    if (!module) return 1;
    if (cot::runSema(*module)) return 1;
    (*module)->print(llvm::outs());
    return 0;
  }

  // ---- cot emit-llvm <file> ----
  if (cmd == "emit-llvm" && argc >= 3) {
    std::string inputFile = argv[2];
    auto source = cot::readFile(inputFile);
    if (source.empty()) {
      llvm::errs() << "error: can't read " << inputFile << "\n";
      return 1;
    }
    auto module = cot::parseSourceToCIR(ctx, inputFile, source);
    if (!module) return 1;
    if (cot::lowerToLLVM(*module)) return 1;
    (*module)->print(llvm::outs());
    return 0;
  }

  // ---- cot build <file> [-o output] ----
  if (cmd == "build" && argc >= 3) {
    std::string inputFile = argv[2];
    std::string outputFile = "a.out";
    if (argc >= 5 && std::string(argv[3]) == "-o") outputFile = argv[4];
    auto source = cot::readFile(inputFile);
    if (source.empty()) {
      llvm::errs() << "error: can't read " << inputFile << "\n";
      return 1;
    }
    auto module = cot::parseSourceToCIR(ctx, inputFile, source);
    if (!module) return 1;
    if (cot::emitBinary(*module, outputFile)) return 1;
    llvm::outs() << outputFile << "\n";
    return 0;
  }

  llvm::errs() << "unknown command: " << cmd << "\n";
  return 1;
}
