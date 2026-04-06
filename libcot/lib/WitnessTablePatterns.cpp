//===- WitnessTablePatterns.cpp - Witness table CIR → LLVM lowering ---===//
//
// Patterns: witness_table → llvm.mlir.global, trait_call → error
//
// Reference: Swift SILWitnessTable → LLVM global constant struct
//   ~/claude/references/swift/include/swift/SIL/SILWitnessTable.h
//
//===----------------------------------------------------------------===//

#include "COT/CIRToLLVMPatterns.h"

namespace {

/// Lower cir.witness_table to an LLVM global constant struct of function
/// pointers. This is the PWT layout used for dynamic dispatch in Phase 7c.
///
/// Example:
///   cir.witness_table "Point_Summable" protocol("Summable")
///       type(!cir.struct<...>) methods(["sum"] = [@Point_sum])
/// →
///   llvm.mlir.global constant @Point_Summable() : !llvm.struct<(ptr)> {
///       %0 = llvm.mlir.addressof @Point_sum : !llvm.ptr
///       %1 = llvm.mlir.undef : !llvm.struct<(ptr)>
///       %2 = llvm.insertvalue %0, %1[0] : !llvm.struct<(ptr)>
///       llvm.return %2 : !llvm.struct<(ptr)>
///   }
struct WitnessTableOpLowering
    : public OpConversionPattern<cir::WitnessTableOp> {
  using OpConversionPattern::OpConversionPattern;

  LogicalResult matchAndRewrite(cir::WitnessTableOp op, OpAdaptor adaptor,
      ConversionPatternRewriter &rewriter) const override {
    auto impls = op.getMethodImpls();
    auto nMethods = impls.size();

    if (nMethods == 0) {
      // Empty witness table — just erase it
      rewriter.eraseOp(op);
      return success();
    }

    // Build LLVM struct type: N function pointers
    auto ctx = op.getContext();
    llvm::SmallVector<Type> fields;
    auto ptrType = LLVM::LLVMPointerType::get(ctx);
    for (size_t i = 0; i < nMethods; i++)
      fields.push_back(ptrType);
    auto structType = LLVM::LLVMStructType::getLiteral(ctx, fields);

    // Create llvm.mlir.global constant with initializer region
    auto tableName = op.getTableName();
    auto globalOp = rewriter.create<LLVM::GlobalOp>(
        op.getLoc(), structType, /*isConstant=*/true,
        LLVM::Linkage::Internal, tableName,
        /*value=*/Attribute());

    // Build initializer region: addressof each method + insertvalue chain
    auto &region = globalOp.getInitializerRegion();
    auto *block = rewriter.createBlock(&region);
    rewriter.setInsertionPointToStart(block);

    Value result = rewriter.create<LLVM::UndefOp>(op.getLoc(), structType);
    for (size_t i = 0; i < nMethods; i++) {
      auto ref = llvm::cast<FlatSymbolRefAttr>(impls[i]);
      auto fnAddr = rewriter.create<LLVM::AddressOfOp>(
          op.getLoc(), ptrType, ref);
      result = rewriter.create<LLVM::InsertValueOp>(
          op.getLoc(), result, fnAddr, i);
    }
    rewriter.create<LLVM::ReturnOp>(op.getLoc(), result);

    // Erase original witness_table op
    rewriter.eraseOp(op);
    return success();
  }
};

/// cir.trait_call must be resolved by the GenericSpecializer BEFORE lowering.
/// If one reaches CIR→LLVM, it's an error (unresolved trait method call).
struct TraitCallOpLowering
    : public OpConversionPattern<cir::TraitCallOp> {
  using OpConversionPattern::OpConversionPattern;

  LogicalResult matchAndRewrite(cir::TraitCallOp op, OpAdaptor adaptor,
      ConversionPatternRewriter &rewriter) const override {
    return rewriter.notifyMatchFailure(op,
        "cir.trait_call must be resolved by GenericSpecializer before "
        "CIR-to-LLVM lowering (unresolved trait method '" +
        op.getMethodName() + "' on protocol '" +
        op.getProtocolName() + "')");
  }
};

/// cir.method_call must be resolved by the GenericSpecializer BEFORE lowering.
/// If one reaches CIR→LLVM, it's an error (unresolved structural method call).
struct MethodCallOpLowering
    : public OpConversionPattern<cir::MethodCallOp> {
  using OpConversionPattern::OpConversionPattern;

  LogicalResult matchAndRewrite(cir::MethodCallOp op, OpAdaptor adaptor,
      ConversionPatternRewriter &rewriter) const override {
    return rewriter.notifyMatchFailure(op,
        "cir.method_call must be resolved by GenericSpecializer before "
        "CIR-to-LLVM lowering (unresolved method '" +
        op.getMethodName() + "')");
  }
};

} // namespace

void cot::populateWitnessTablePatterns(
    const LLVMTypeConverter &converter,
    RewritePatternSet &patterns) {
  MLIRContext *ctx = patterns.getContext();
  patterns.add<WitnessTableOpLowering, TraitCallOpLowering,
               MethodCallOpLowering>(converter, ctx);
}
