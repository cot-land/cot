//===- SemanticAnalysis.cpp - CIR semantic analysis pass ---------------===//
//
// CIR → CIR transformation: validate types, insert casts, resolve fields.
// This is the first pass in the pipeline, runs before lowering.
//
// Architecture: Manual walk pass (not pattern-based).
// Reference: Zig Sema — ~/claude/references/zig/src/Sema.zig
//            Flang Transforms — ~/claude/references/flang-ref/flang/lib/Optimizer/Transforms/
//
// The pass walks each function in forward order, maintaining a symbol table
// (function signatures from the module). It validates type constraints and
// inserts implicit cast ops (cir.extsi, cir.trunci, etc.) at type boundaries.
//
// Explicit casts (user-written `as` / `@intCast`) are emitted by frontends.
// This pass handles implicit coercion at call boundaries.
//
//===----------------------------------------------------------------===//

#include "COT/Passes.h"
#include "CIR/CIROps.h"

#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/Pass/Pass.h"

using namespace mlir;

namespace {

/// Semantic analysis pass — CIR → CIR transformation.
///
/// Phase 3 scope:
///   - Validate call argument types against callee signatures
///   - Insert cast ops at type boundaries (int widening, etc.)
///
/// Future phases will add:
///   - Struct field resolution
///   - Generic instantiation support
///   - Error union validation
struct SemanticAnalysisPass
    : public PassWrapper<SemanticAnalysisPass,
                         OperationPass<func::FuncOp>> {
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(SemanticAnalysisPass)

  StringRef getArgument() const override { return "cir-sema"; }
  StringRef getDescription() const override {
    return "CIR semantic analysis: type checking and cast insertion";
  }

  void runOnOperation() override {
    auto funcOp = getOperation();
    auto moduleOp = funcOp->getParentOfType<ModuleOp>();
    if (!moduleOp) return;

    // Build symbol table once per function (cached, not per-call O(n) lookup).
    // Reference: Zig Sema builds symbol table in one pass, then resolves.
    symbolTable.clear();
    moduleOp.walk([&](func::FuncOp fn) {
      symbolTable[fn.getName()] = fn;
    });

    // Walk in forward order within each block.
    // Process calls to validate argument types and insert casts.
    funcOp.walk([&](func::CallOp callOp) {
      if (failed(resolveCallTypes(callOp)))
        signalPassFailure();
    });
  }

private:
  /// Cached function signatures — built once per runOnOperation.
  llvm::DenseMap<llvm::StringRef, func::FuncOp> symbolTable;

  /// Look up callee signature and insert casts for type mismatches.
  /// Returns failure() on semantic errors that should halt compilation.
  /// Reference: Zig Sema coerce() — inserts explicit casts at call boundaries.
  LogicalResult resolveCallTypes(func::CallOp callOp) {
    auto it = symbolTable.find(callOp.getCallee());
    if (it == symbolTable.end()) return success(); // external function — skip
    auto callee = it->second;

    auto paramTypes = callee.getArgumentTypes();
    auto operands = callOp.getOperands();
    if (paramTypes.size() != operands.size()) {
      callOp.emitError("call to '") << callee.getName()
          << "' passes " << operands.size() << " arguments, expected "
          << paramTypes.size();
      return failure();
    }

    OpBuilder builder(callOp);

    for (unsigned i = 0; i < paramTypes.size(); i++) {
      auto paramType = paramTypes[i];
      auto argValue = operands[i];
      auto argType = argValue.getType();

      if (paramType == argType) continue;

      // Insert appropriate cast based on type pair
      Value cast = insertCast(builder, callOp.getLoc(),
                              argValue, argType, paramType);
      if (!cast) {
        callOp.emitError("cannot convert argument ")
            << i << " from " << argType << " to " << paramType;
        return failure();
      }
      callOp.setOperand(i, cast);
    }

    return success();
  }

  /// Determine and insert the correct cast op for a type conversion.
  /// Returns the cast result value, or nullptr if cast is not possible.
  ///
  /// Reference: Arith dialect cast hierarchy — each direction is a
  /// separate op. No if/else chains at lowering time.
  Value insertCast(OpBuilder &builder, Location loc,
                   Value input, Type srcType, Type dstType) {
    bool srcInt = llvm::isa<IntegerType>(srcType);
    bool dstInt = llvm::isa<IntegerType>(dstType);
    bool srcFloat = llvm::isa<FloatType>(srcType);
    bool dstFloat = llvm::isa<FloatType>(dstType);

    if (srcInt && dstInt) {
      unsigned srcW = srcType.getIntOrFloatBitWidth();
      unsigned dstW = dstType.getIntOrFloatBitWidth();
      if (dstW > srcW)
        return builder.create<cir::ExtSIOp>(loc, dstType, input);
      if (dstW < srcW)
        return builder.create<cir::TruncIOp>(loc, dstType, input);
      return input; // same width
    }

    if (srcInt && dstFloat)
      return builder.create<cir::SIToFPOp>(loc, dstType, input);

    if (srcFloat && dstInt)
      return builder.create<cir::FPToSIOp>(loc, dstType, input);

    if (srcFloat && dstFloat) {
      unsigned srcW = srcType.getIntOrFloatBitWidth();
      unsigned dstW = dstType.getIntOrFloatBitWidth();
      if (dstW > srcW)
        return builder.create<cir::ExtFOp>(loc, dstType, input);
      if (dstW < srcW)
        return builder.create<cir::TruncFOp>(loc, dstType, input);
      return input;
    }

    return nullptr; // unsupported cast — caller will emit diagnostic
  }
};

} // namespace

//===----------------------------------------------------------------------===//
// Public API
//===----------------------------------------------------------------------===//

std::unique_ptr<mlir::Pass> cot::createSemanticAnalysisPass() {
  return std::make_unique<SemanticAnalysisPass>();
}
