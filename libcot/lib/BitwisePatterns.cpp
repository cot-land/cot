//===- BitwisePatterns.cpp - Bitwise/shift CIR → LLVM lowering --------===//
//
// Patterns: bit_and, bit_or, bit_xor, bit_not, shl, shr
//
//===----------------------------------------------------------------===//

#include "COT/CIRToLLVMPatterns.h"

namespace {

struct BitAndOpLowering : public OpConversionPattern<cir::BitAndOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(cir::BitAndOp op, OpAdaptor adaptor,
      ConversionPatternRewriter &rewriter) const override {
    rewriter.replaceOpWithNewOp<LLVM::AndOp>(op,
        getTypeConverter()->convertType(op.getType()),
        adaptor.getLhs(), adaptor.getRhs());
    return success();
  }
};

struct BitOrOpLowering : public OpConversionPattern<cir::BitOrOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(cir::BitOrOp op, OpAdaptor adaptor,
      ConversionPatternRewriter &rewriter) const override {
    rewriter.replaceOpWithNewOp<LLVM::OrOp>(op,
        getTypeConverter()->convertType(op.getType()),
        adaptor.getLhs(), adaptor.getRhs());
    return success();
  }
};

struct BitXorOpLowering : public OpConversionPattern<cir::BitXorOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(cir::BitXorOp op, OpAdaptor adaptor,
      ConversionPatternRewriter &rewriter) const override {
    rewriter.replaceOpWithNewOp<LLVM::XOrOp>(op,
        getTypeConverter()->convertType(op.getType()),
        adaptor.getLhs(), adaptor.getRhs());
    return success();
  }
};

struct BitNotOpLowering : public OpConversionPattern<cir::BitNotOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(cir::BitNotOp op, OpAdaptor adaptor,
      ConversionPatternRewriter &rewriter) const override {
    auto type = getTypeConverter()->convertType(op.getType());
    if (!type)
      return rewriter.notifyMatchFailure(op, "failed to convert type");
    auto allOnes = rewriter.create<LLVM::ConstantOp>(op.getLoc(), type,
        rewriter.getIntegerAttr(type, -1));
    rewriter.replaceOpWithNewOp<LLVM::XOrOp>(op, type,
        adaptor.getOperand(), allOnes);
    return success();
  }
};

struct ShlOpLowering : public OpConversionPattern<cir::ShlOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(cir::ShlOp op, OpAdaptor adaptor,
      ConversionPatternRewriter &rewriter) const override {
    rewriter.replaceOpWithNewOp<LLVM::ShlOp>(op,
        getTypeConverter()->convertType(op.getType()),
        adaptor.getLhs(), adaptor.getRhs());
    return success();
  }
};

struct ShrOpLowering : public OpConversionPattern<cir::ShrOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(cir::ShrOp op, OpAdaptor adaptor,
      ConversionPatternRewriter &rewriter) const override {
    rewriter.replaceOpWithNewOp<LLVM::LShrOp>(op,
        getTypeConverter()->convertType(op.getType()),
        adaptor.getLhs(), adaptor.getRhs());
    return success();
  }
};

} // namespace

void cot::populateBitwisePatterns(
    const LLVMTypeConverter &converter,
    RewritePatternSet &patterns) {
  MLIRContext *ctx = patterns.getContext();
  patterns.add<
      BitAndOpLowering, BitOrOpLowering, BitXorOpLowering,
      BitNotOpLowering, ShlOpLowering, ShrOpLowering
  >(converter, ctx);
}
