//===- ArithmeticPatterns.cpp - Arithmetic CIR → LLVM lowering --------===//
//
// Patterns: add, sub, mul, div, rem, neg, constant, cmp, select
//
//===----------------------------------------------------------------===//

#include "COT/CIRToLLVMPatterns.h"

namespace {

/// Helper: convert op type with null check.
/// Reference: ArithToLLVM — all patterns check type conversion result.
static Type convertOpType(const TypeConverter *tc, Operation *op) {
  return tc->convertType(op->getResult(0).getType());
}

struct AddOpLowering : public OpConversionPattern<cir::AddOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(cir::AddOp op, OpAdaptor adaptor,
      ConversionPatternRewriter &rewriter) const override {
    auto type = convertOpType(getTypeConverter(), op);
    if (!type) return rewriter.notifyMatchFailure(op, "type conversion failed");
    rewriter.replaceOpWithNewOp<LLVM::AddOp>(op, type,
        adaptor.getLhs(), adaptor.getRhs());
    return success();
  }
};

struct SubOpLowering : public OpConversionPattern<cir::SubOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(cir::SubOp op, OpAdaptor adaptor,
      ConversionPatternRewriter &rewriter) const override {
    auto type = convertOpType(getTypeConverter(), op);
    if (!type) return rewriter.notifyMatchFailure(op, "type conversion failed");
    rewriter.replaceOpWithNewOp<LLVM::SubOp>(op, type,
        adaptor.getLhs(), adaptor.getRhs());
    return success();
  }
};

struct MulOpLowering : public OpConversionPattern<cir::MulOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(cir::MulOp op, OpAdaptor adaptor,
      ConversionPatternRewriter &rewriter) const override {
    auto type = convertOpType(getTypeConverter(), op);
    if (!type) return rewriter.notifyMatchFailure(op, "type conversion failed");
    rewriter.replaceOpWithNewOp<LLVM::MulOp>(op, type,
        adaptor.getLhs(), adaptor.getRhs());
    return success();
  }
};

struct DivOpLowering : public OpConversionPattern<cir::DivOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(cir::DivOp op, OpAdaptor adaptor,
      ConversionPatternRewriter &rewriter) const override {
    auto type = convertOpType(getTypeConverter(), op);
    if (!type) return rewriter.notifyMatchFailure(op, "type conversion failed");
    rewriter.replaceOpWithNewOp<LLVM::SDivOp>(op, type,
        adaptor.getLhs(), adaptor.getRhs());
    return success();
  }
};

struct RemOpLowering : public OpConversionPattern<cir::RemOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(cir::RemOp op, OpAdaptor adaptor,
      ConversionPatternRewriter &rewriter) const override {
    auto type = convertOpType(getTypeConverter(), op);
    if (!type) return rewriter.notifyMatchFailure(op, "type conversion failed");
    rewriter.replaceOpWithNewOp<LLVM::SRemOp>(op, type,
        adaptor.getLhs(), adaptor.getRhs());
    return success();
  }
};

struct NegOpLowering : public OpConversionPattern<cir::NegOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(cir::NegOp op, OpAdaptor adaptor,
      ConversionPatternRewriter &rewriter) const override {
    auto type = getTypeConverter()->convertType(op.getType());
    if (!type)
      return rewriter.notifyMatchFailure(op, "failed to convert type");
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
    auto type = getTypeConverter()->convertType(op.getType());
    if (!type)
      return rewriter.notifyMatchFailure(op, "failed to convert type");
    rewriter.replaceOpWithNewOp<LLVM::ConstantOp>(op, type, op.getValue());
    return success();
  }
};

struct CmpOpLowering : public OpConversionPattern<cir::CmpOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(cir::CmpOp op, OpAdaptor adaptor,
      ConversionPatternRewriter &rewriter) const override {
    auto pred = static_cast<LLVM::ICmpPredicate>(
        static_cast<uint64_t>(op.getPredicate()));
    auto resultType = getTypeConverter()->convertType(op.getResult().getType());
    if (!resultType)
      return rewriter.notifyMatchFailure(op, "type conversion failed");
    rewriter.replaceOpWithNewOp<LLVM::ICmpOp>(op, resultType,
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

//===----------------------------------------------------------------------===//
// Cast lowering — 1:1 mapping to LLVM ops (Arith pattern)
//===----------------------------------------------------------------------===//

struct ExtSIOpLowering : public OpConversionPattern<cir::ExtSIOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(cir::ExtSIOp op, OpAdaptor adaptor,
      ConversionPatternRewriter &rewriter) const override {
    rewriter.replaceOpWithNewOp<LLVM::SExtOp>(op,
        getTypeConverter()->convertType(op.getType()), adaptor.getInput());
    return success();
  }
};

struct ExtUIOpLowering : public OpConversionPattern<cir::ExtUIOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(cir::ExtUIOp op, OpAdaptor adaptor,
      ConversionPatternRewriter &rewriter) const override {
    rewriter.replaceOpWithNewOp<LLVM::ZExtOp>(op,
        getTypeConverter()->convertType(op.getType()), adaptor.getInput());
    return success();
  }
};

struct TruncIOpLowering : public OpConversionPattern<cir::TruncIOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(cir::TruncIOp op, OpAdaptor adaptor,
      ConversionPatternRewriter &rewriter) const override {
    rewriter.replaceOpWithNewOp<LLVM::TruncOp>(op,
        getTypeConverter()->convertType(op.getType()), adaptor.getInput());
    return success();
  }
};

struct SIToFPOpLowering : public OpConversionPattern<cir::SIToFPOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(cir::SIToFPOp op, OpAdaptor adaptor,
      ConversionPatternRewriter &rewriter) const override {
    rewriter.replaceOpWithNewOp<LLVM::SIToFPOp>(op,
        getTypeConverter()->convertType(op.getType()), adaptor.getInput());
    return success();
  }
};

struct FPToSIOpLowering : public OpConversionPattern<cir::FPToSIOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(cir::FPToSIOp op, OpAdaptor adaptor,
      ConversionPatternRewriter &rewriter) const override {
    rewriter.replaceOpWithNewOp<LLVM::FPToSIOp>(op,
        getTypeConverter()->convertType(op.getType()), adaptor.getInput());
    return success();
  }
};

struct ExtFOpLowering : public OpConversionPattern<cir::ExtFOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(cir::ExtFOp op, OpAdaptor adaptor,
      ConversionPatternRewriter &rewriter) const override {
    rewriter.replaceOpWithNewOp<LLVM::FPExtOp>(op,
        getTypeConverter()->convertType(op.getType()), adaptor.getInput());
    return success();
  }
};

struct TruncFOpLowering : public OpConversionPattern<cir::TruncFOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(cir::TruncFOp op, OpAdaptor adaptor,
      ConversionPatternRewriter &rewriter) const override {
    rewriter.replaceOpWithNewOp<LLVM::FPTruncOp>(op,
        getTypeConverter()->convertType(op.getType()), adaptor.getInput());
    return success();
  }
};

/// cir.enum_constant → llvm.mlir.constant (variant's integer value)
/// Reference: Zig enum literal → integer constant
struct EnumConstantOpLowering
    : public OpConversionPattern<cir::EnumConstantOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(cir::EnumConstantOp op, OpAdaptor adaptor,
      ConversionPatternRewriter &rewriter) const override {
    auto enumType = llvm::cast<cir::EnumType>(op.getType());
    auto tagType = enumType.getTagType();
    auto val = enumType.getVariantValue(op.getVariant());
    if (val < 0)
      return rewriter.notifyMatchFailure(op, "variant not found");
    rewriter.replaceOpWithNewOp<LLVM::ConstantOp>(
        op, tagType, rewriter.getIntegerAttr(tagType, val));
    return success();
  }
};

/// cir.enum_value → identity (enum IS the integer at LLVM level)
/// Reference: Rust Discriminant rvalue
struct EnumValueOpLowering
    : public OpConversionPattern<cir::EnumValueOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(cir::EnumValueOp op, OpAdaptor adaptor,
      ConversionPatternRewriter &rewriter) const override {
    // Identity — the enum is already the integer after type conversion
    rewriter.replaceOp(op, adaptor.getInput());
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
      ConstantOpLowering, CmpOpLowering, SelectOpLowering,
      // Casts — 1:1 to LLVM
      ExtSIOpLowering, ExtUIOpLowering, TruncIOpLowering,
      SIToFPOpLowering, FPToSIOpLowering,
      ExtFOpLowering, TruncFOpLowering,
      EnumConstantOpLowering, EnumValueOpLowering
  >(converter, ctx);
}
