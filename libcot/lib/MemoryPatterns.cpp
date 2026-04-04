//===- MemoryPatterns.cpp - Memory CIR → LLVM lowering ----------------===//
//
// Patterns: alloca, store, load
//
//===----------------------------------------------------------------===//

#include "COT/CIRToLLVMPatterns.h"

namespace {

struct AllocaOpLowering : public OpConversionPattern<cir::AllocaOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(cir::AllocaOp op, OpAdaptor adaptor,
      ConversionPatternRewriter &rewriter) const override {
    // Convert element type (e.g. !cir.struct → !llvm.struct)
    auto elemType = getTypeConverter()->convertType(op.getElemType());
    if (!elemType)
      return failure();
    auto ptrType = LLVM::LLVMPointerType::get(op.getContext());
    auto one = rewriter.create<LLVM::ConstantOp>(
        op.getLoc(), rewriter.getI64Type(), rewriter.getI64IntegerAttr(1));
    rewriter.replaceOpWithNewOp<LLVM::AllocaOp>(
        op, ptrType, elemType, one);
    return success();
  }
};

struct StoreOpLowering : public OpConversionPattern<cir::StoreOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(cir::StoreOp op, OpAdaptor adaptor,
      ConversionPatternRewriter &rewriter) const override {
    rewriter.replaceOpWithNewOp<LLVM::StoreOp>(
        op, adaptor.getValue(), adaptor.getAddr());
    return success();
  }
};

struct LoadOpLowering : public OpConversionPattern<cir::LoadOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(cir::LoadOp op, OpAdaptor adaptor,
      ConversionPatternRewriter &rewriter) const override {
    rewriter.replaceOpWithNewOp<LLVM::LoadOp>(
        op, getTypeConverter()->convertType(op.getType()),
        adaptor.getAddr());
    return success();
  }
};

/// cir.struct_init → llvm.mlir.undef + llvm.insertvalue chain
/// Reference: FIR UndefOpConversion + InsertValueOpConversion
///   ~/claude/references/flang-ref/flang/lib/Optimizer/CodeGen/CodeGen.cpp
struct StructInitOpLowering : public OpConversionPattern<cir::StructInitOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(cir::StructInitOp op, OpAdaptor adaptor,
      ConversionPatternRewriter &rewriter) const override {
    auto llvmType = getTypeConverter()->convertType(op.getType());
    if (!llvmType)
      return failure();
    // Start with undef (FIR pattern: fir.undefined → llvm.mlir.undef)
    Value result = rewriter.create<LLVM::UndefOp>(op.getLoc(), llvmType);
    // Insert each field value (FIR pattern: fir.insert_value → llvm.insertvalue)
    for (auto [i, field] : llvm::enumerate(adaptor.getFields())) {
      result = rewriter.create<LLVM::InsertValueOp>(
          op.getLoc(), result, field, i);
    }
    rewriter.replaceOp(op, result);
    return success();
  }
};

} // namespace

void cot::populateMemoryPatterns(
    const LLVMTypeConverter &converter,
    RewritePatternSet &patterns) {
  MLIRContext *ctx = patterns.getContext();
  patterns.add<AllocaOpLowering, StoreOpLowering, LoadOpLowering,
               StructInitOpLowering>(
      converter, ctx);
}
