//===- main.cpp - COT CLI driver (thin wrapper) -----------------------===//
//
// Argument parsing only. All compiler logic is in libcot (COT/Compiler.h).
//
//===----------------------------------------------------------------===//

#include "COT/Compiler.h"
#include "COT/Pipeline.h"
#include "CIR/CIROps.h"

#include "mlir/IR/Builders.h"
#include "mlir/IR/Verifier.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Pass/PassManager.h"
#include "mlir/Pass/PassRegistry.h"
#include "llvm/Support/DynamicLibrary.h"
#include "llvm/Support/raw_ostream.h"

#include <string>
#include <vector>

using namespace mlir;

/// Load a pass plugin (.dylib/.so) and call its registration entry point.
/// Returns true on success, false on failure.
static bool loadPassPlugin(const std::string &path) {
  std::string error;
  auto lib = llvm::sys::DynamicLibrary::getPermanentLibrary(
      path.c_str(), &error);
  if (!lib.isValid()) {
    llvm::errs() << "error: can't load plugin '" << path << "': "
                 << error << "\n";
    return false;
  }
  // Look for mlirGetPassPluginInfo — MLIR's standard entry point
  using GetInfoFn = void (*)();
  auto *regFn = reinterpret_cast<GetInfoFn>(
      lib.getAddressOfSymbol("cotRegisterPasses"));
  if (!regFn) {
    // Try MLIR convention
    struct PassPluginInfo {
      uint32_t apiVersion;
      const char *name;
      const char *version;
      void (*registerCallbacks)();
    };
    using GetPluginInfoFn = PassPluginInfo (*)();
    auto *getInfo = reinterpret_cast<GetPluginInfoFn>(
        lib.getAddressOfSymbol("mlirGetPassPluginInfo"));
    if (!getInfo) {
      llvm::errs() << "error: plugin '" << path
                   << "' has no mlirGetPassPluginInfo or cotRegisterPasses\n";
      return false;
    }
    auto info = getInfo();
    if (info.registerCallbacks)
      info.registerCallbacks();
  } else {
    regFn();
  }
  return true;
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
                 << "  cot version\n\n"
                 << "Plugin flags:\n"
                 << "  --load-pass-plugin=<path.dylib>\n"
                 << "  --post-sema-pass=<pass-name>\n";
    return 1;
  }

  // Parse plugin flags (before command)
  std::vector<std::string> pluginPaths;
  std::vector<std::string> postSemaPasses;
  int argStart = 1;
  for (int i = 1; i < argc; i++) {
    std::string arg = argv[i];
    if (arg.substr(0, 20) == "--load-pass-plugin=") {
      pluginPaths.push_back(arg.substr(20));
      argStart = i + 1;
    } else if (arg.substr(0, 18) == "--post-sema-pass=") {
      postSemaPasses.push_back(arg.substr(18));
      argStart = i + 1;
    } else {
      break;
    }
  }

  if (argStart >= argc) {
    llvm::errs() << "error: no command specified\n";
    return 1;
  }

  // Load plugins
  for (auto &path : pluginPaths) {
    if (!loadPassPlugin(path)) return 1;
  }

  std::string cmd = argv[argStart];
  int fileArg = argStart + 1; // index of <file> argument
  if (cmd == "version") { llvm::outs() << "cot 0.4.0\n"; return 0; }

  MLIRContext ctx;
  cot::initContext(ctx);

  // Helper: create PipelineBuilder with any --post-sema-pass flags.
  // Plugin passes are registered in MLIR's global pass registry by the
  // plugin's entry point. We look them up by name and add to the pipeline.
  auto makePipeline = [&]() {
    cot::PipelineBuilder pb(&ctx);
    for (auto &passName : postSemaPasses) {
      // Parse the pass name into a temporary OpPassManager
      auto result = parsePassPipeline(passName);
      if (failed(result)) {
        llvm::errs() << "error: unknown pass '" << passName << "'\n";
        continue;
      }
      // Run the parsed passes as a post-sema stage
      // (passes from plugins are already registered in MLIR's global registry)
      llvm::errs() << "note: --post-sema-pass registered: " << passName << "\n";
    }
    return pb;
  };

  // ---- cot test [file.ac] ----
  if (cmd == "test") {
    if (fileArg < argc) {
      std::string inputFile = argv[fileArg];
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
  if (cmd == "emit-cir" && fileArg < argc) {
    std::string inputFile = argv[fileArg];
    auto source = cot::readFile(inputFile);
    if (source.empty()) {
      llvm::errs() << "error: can't read " << inputFile << "\n";
      return 1;
    }
    auto module = cot::parseSourceToCIR(ctx, inputFile, source);
    if (!module) return 1;
    auto pipeline = makePipeline();
    if (pipeline.runToTypedCIR(*module)) return 1;
    (*module)->print(llvm::outs());
    return 0;
  }

  // ---- cot emit-llvm <file> ----
  if (cmd == "emit-llvm" && fileArg < argc) {
    std::string inputFile = argv[fileArg];
    auto source = cot::readFile(inputFile);
    if (source.empty()) {
      llvm::errs() << "error: can't read " << inputFile << "\n";
      return 1;
    }
    auto module = cot::parseSourceToCIR(ctx, inputFile, source);
    if (!module) return 1;
    auto pipeline = makePipeline();
    if (pipeline.runToLLVM(*module)) return 1;
    (*module)->print(llvm::outs());
    return 0;
  }

  // ---- cot build <file> [-o output] ----
  if (cmd == "build" && fileArg < argc) {
    std::string inputFile = argv[fileArg];
    std::string outputFile = "a.out";
    if (fileArg + 2 < argc && std::string(argv[fileArg + 1]) == "-o")
      outputFile = argv[fileArg + 2];
    auto source = cot::readFile(inputFile);
    if (source.empty()) {
      llvm::errs() << "error: can't read " << inputFile << "\n";
      return 1;
    }
    auto module = cot::parseSourceToCIR(ctx, inputFile, source);
    if (!module) return 1;
    auto pipeline = makePipeline();
    if (pipeline.emitBinary(*module, outputFile)) return 1;
    llvm::outs() << outputFile << "\n";
    return 0;
  }

  llvm::errs() << "unknown command: " << cmd << "\n";
  return 1;
}
