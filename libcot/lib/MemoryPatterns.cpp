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
    auto elemType = op.getElemType();
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

} // namespace

void cot::populateMemoryPatterns(
    const LLVMTypeConverter &converter,
    RewritePatternSet &patterns) {
  MLIRContext *ctx = patterns.getContext();
  patterns.add<AllocaOpLowering, StoreOpLowering, LoadOpLowering>(
      converter, ctx);
}
