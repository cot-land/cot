//===- ControlFlowPatterns.cpp - Control flow CIR → LLVM lowering -----===//
//
// Patterns: br, condbr, trap
//
//===----------------------------------------------------------------===//

#include "COT/CIRToLLVMPatterns.h"

namespace {

struct BrOpLowering : public OpConversionPattern<cir::BrOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(cir::BrOp op, OpAdaptor adaptor,
      ConversionPatternRewriter &rewriter) const override {
    rewriter.replaceOpWithNewOp<LLVM::BrOp>(op,
        adaptor.getDestOperands(), op.getDest());
    return success();
  }
};

struct CondBrOpLowering : public OpConversionPattern<cir::CondBrOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(cir::CondBrOp op, OpAdaptor adaptor,
      ConversionPatternRewriter &rewriter) const override {
    rewriter.replaceOpWithNewOp<LLVM::CondBrOp>(op,
        adaptor.getCondition(), op.getTrueDest(), op.getFalseDest());
    return success();
  }
};

struct TrapOpLowering : public OpConversionPattern<cir::TrapOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(cir::TrapOp op, OpAdaptor adaptor,
      ConversionPatternRewriter &rewriter) const override {
    rewriter.create<LLVM::Trap>(op.getLoc());
    rewriter.replaceOpWithNewOp<LLVM::UnreachableOp>(op);
    return success();
  }
};

} // namespace

void cot::populateControlFlowPatterns(
    const LLVMTypeConverter &converter,
    RewritePatternSet &patterns) {
  MLIRContext *ctx = patterns.getContext();
  patterns.add<BrOpLowering, CondBrOpLowering, TrapOpLowering>(
      converter, ctx);
}
