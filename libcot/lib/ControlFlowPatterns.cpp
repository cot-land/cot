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

/// cir.switch → llvm.switch
/// Reference: LLVM SwitchOp
struct SwitchOpLowering : public OpConversionPattern<cir::SwitchOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(cir::SwitchOp op, OpAdaptor adaptor,
      ConversionPatternRewriter &rewriter) const override {
    auto caseValues = op.getCaseValues();
    auto caseDests = op.getCaseDests();
    // Build DenseIntElementsAttr for case values
    auto valType = op.getValue().getType();
    llvm::SmallVector<llvm::APInt> apValues;
    unsigned bitWidth = valType.getIntOrFloatBitWidth();
    for (auto v : caseValues)
      apValues.push_back(llvm::APInt(bitWidth, v, /*isSigned=*/true));
    auto caseValuesAttr = DenseIntElementsAttr::get(
        RankedTensorType::get({static_cast<int64_t>(apValues.size())}, valType),
        apValues);
    // Build case destinations
    llvm::SmallVector<Block *> caseDestBlocks(caseDests.begin(),
                                               caseDests.end());
    llvm::SmallVector<ValueRange> caseOperands(caseDestBlocks.size(),
                                                ValueRange{});
    // Create LLVM switch with all empty operand segments
    auto switchOp = rewriter.create<LLVM::SwitchOp>(
        op.getLoc(), adaptor.getValue(),
        op.getDefaultDest(), ValueRange{},
        caseValuesAttr, caseDestBlocks, caseOperands);
    (void)switchOp;
    rewriter.eraseOp(op);
    return success();
  }
};

/// cir.throw → llvm.trap + llvm.unreachable
/// Phase 1 lowering: crash on throw (like assertion failure).
/// Phase 2 will add full C++ ABI: __cxa_allocate_exception + __cxa_throw.
/// Reference: LLVM InvokeInst, C++ ABI __cxa_throw
struct ThrowOpLowering : public OpConversionPattern<cir::ThrowOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(cir::ThrowOp op, OpAdaptor adaptor,
      ConversionPatternRewriter &rewriter) const override {
    // For now: trap + unreachable (same as assertion failure).
    // TODO: Lower to __cxa_allocate_exception + __cxa_throw for full C++ ABI.
    rewriter.create<LLVM::Trap>(op.getLoc());
    rewriter.replaceOpWithNewOp<LLVM::UnreachableOp>(op);
    return success();
  }
};

/// cir.invoke → llvm.call + llvm.br (simplified — no actual unwinding)
/// Phase 1: invoke lowers to a normal call + branch to normalDest.
/// Phase 2 will use llvm.invoke with personality function for real unwinding.
/// Reference: LLVM InvokeOp
struct InvokeOpLowering : public OpConversionPattern<cir::InvokeOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(cir::InvokeOp op, OpAdaptor adaptor,
      ConversionPatternRewriter &rewriter) const override {
    auto loc = op.getLoc();
    // Lower as regular call (no unwinding in Phase 1)
    llvm::SmallVector<mlir::Type> resultTypes;
    if (op.getResult())
      resultTypes.push_back(
          getTypeConverter()->convertType(op.getResult().getType()));
    auto call = rewriter.create<LLVM::CallOp>(
        loc, resultTypes, op.getCallee(), adaptor.getOperands());
    // Branch to normal destination
    rewriter.create<LLVM::BrOp>(loc, mlir::ValueRange{}, op.getNormalDest());
    // If call has a result, replace the invoke result with the call result
    if (op.getResult()) {
      rewriter.replaceOp(op, call.getResult());
    } else {
      rewriter.eraseOp(op);
    }
    return success();
  }
};

/// cir.landingpad → llvm.mlir.undef (simplified — no actual landing pad)
/// Phase 1: landingpad never reached (invoke doesn't unwind).
/// Phase 2 will use llvm.landingpad with personality function.
/// Reference: LLVM LandingpadOp
struct LandingPadOpLowering : public OpConversionPattern<cir::LandingPadOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(cir::LandingPadOp op, OpAdaptor adaptor,
      ConversionPatternRewriter &rewriter) const override {
    auto llvmType = getTypeConverter()->convertType(op.getType());
    if (!llvmType)
      return rewriter.notifyMatchFailure(op, "type conversion failed");
    // For now: undef (this block is never reached in Phase 1).
    rewriter.replaceOpWithNewOp<LLVM::UndefOp>(op, llvmType);
    return success();
  }
};

} // namespace

void cot::populateControlFlowPatterns(
    const LLVMTypeConverter &converter,
    RewritePatternSet &patterns) {
  MLIRContext *ctx = patterns.getContext();
  patterns.add<BrOpLowering, CondBrOpLowering, TrapOpLowering,
               SwitchOpLowering,
               ThrowOpLowering, InvokeOpLowering, LandingPadOpLowering>(
      converter, ctx);
}
