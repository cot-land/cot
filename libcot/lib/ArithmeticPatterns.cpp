//===- ArithmeticPatterns.cpp - Arithmetic CIR → LLVM lowering --------===//
//
// Patterns: add, sub, mul, div, rem, neg, constant, cmp, select
//
//===----------------------------------------------------------------===//

#include "COT/CIRToLLVMPatterns.h"

namespace {

struct AddOpLowering : public OpConversionPattern<cir::AddOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(cir::AddOp op, OpAdaptor adaptor,
      ConversionPatternRewriter &rewriter) const override {
    rewriter.replaceOpWithNewOp<LLVM::AddOp>(op,
        getTypeConverter()->convertType(op.getType()),
        adaptor.getLhs(), adaptor.getRhs());
    return success();
  }
};

struct SubOpLowering : public OpConversionPattern<cir::SubOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(cir::SubOp op, OpAdaptor adaptor,
      ConversionPatternRewriter &rewriter) const override {
    rewriter.replaceOpWithNewOp<LLVM::SubOp>(op,
        getTypeConverter()->convertType(op.getType()),
        adaptor.getLhs(), adaptor.getRhs());
    return success();
  }
};

struct MulOpLowering : public OpConversionPattern<cir::MulOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(cir::MulOp op, OpAdaptor adaptor,
      ConversionPatternRewriter &rewriter) const override {
    rewriter.replaceOpWithNewOp<LLVM::MulOp>(op,
        getTypeConverter()->convertType(op.getType()),
        adaptor.getLhs(), adaptor.getRhs());
    return success();
  }
};

struct DivOpLowering : public OpConversionPattern<cir::DivOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(cir::DivOp op, OpAdaptor adaptor,
      ConversionPatternRewriter &rewriter) const override {
    rewriter.replaceOpWithNewOp<LLVM::SDivOp>(op,
        getTypeConverter()->convertType(op.getType()),
        adaptor.getLhs(), adaptor.getRhs());
    return success();
  }
};

struct RemOpLowering : public OpConversionPattern<cir::RemOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(cir::RemOp op, OpAdaptor adaptor,
      ConversionPatternRewriter &rewriter) const override {
    rewriter.replaceOpWithNewOp<LLVM::SRemOp>(op,
        getTypeConverter()->convertType(op.getType()),
        adaptor.getLhs(), adaptor.getRhs());
    return success();
  }
};

struct NegOpLowering : public OpConversionPattern<cir::NegOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(cir::NegOp op, OpAdaptor adaptor,
      ConversionPatternRewriter &rewriter) const override {
    auto type = getTypeConverter()->convertType(op.getType());
    auto zero = rewriter.create<LLVM::ConstantOp>(op.getLoc(), type,
        rewriter.getIntegerAttr(type, 0));
    rewriter.replaceOpWithNewOp<LLVM::SubOp>(op, type, zero,
        adaptor.getOperand());
    return success();
  }
};

struct ConstantOpLowering : public OpConversionPattern<cir::ConstantOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(cir::ConstantOp op, OpAdaptor adaptor,
      ConversionPatternRewriter &rewriter) const override {
    rewriter.replaceOpWithNewOp<LLVM::ConstantOp>(op,
        getTypeConverter()->convertType(op.getType()), op.getValue());
    return success();
  }
};

struct CmpOpLowering : public OpConversionPattern<cir::CmpOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(cir::CmpOp op, OpAdaptor adaptor,
      ConversionPatternRewriter &rewriter) const override {
    auto pred = static_cast<LLVM::ICmpPredicate>(
        static_cast<uint64_t>(op.getPredicate()));
    rewriter.replaceOpWithNewOp<LLVM::ICmpOp>(op,
        getTypeConverter()->convertType(op.getResult().getType()),
        pred, adaptor.getLhs(), adaptor.getRhs());
    return success();
  }
};

struct SelectOpLowering : public OpConversionPattern<cir::SelectOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(cir::SelectOp op, OpAdaptor adaptor,
      ConversionPatternRewriter &rewriter) const override {
    rewriter.replaceOpWithNewOp<LLVM::SelectOp>(op,
        adaptor.getCondition(), adaptor.getTrueValue(),
        adaptor.getFalseValue());
    return success();
  }
};

} // namespace

void cot::populateArithmeticPatterns(
    const LLVMTypeConverter &converter,
    RewritePatternSet &patterns) {
  MLIRContext *ctx = patterns.getContext();
  patterns.add<
      AddOpLowering, SubOpLowering, MulOpLowering,
      DivOpLowering, RemOpLowering, NegOpLowering,
      ConstantOpLowering, CmpOpLowering, SelectOpLowering
  >(converter, ctx);
}
