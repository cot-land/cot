//===- CIRToLLVM.cpp - CIR → LLVM dialect lowering ----------------===//
//
// Lowers all CIR ops to LLVM dialect equivalents using MLIR's
// ConversionPattern infrastructure.
//
// Reference: mlir/lib/Conversion/ArithToLLVM/ArithToLLVM.cpp
//   ~/claude/references/llvm-project/mlir/lib/Conversion/ArithToLLVM/
//
// Pattern: One ConversionPattern per CIR op. Each pattern replaces a
// CIR op with the equivalent LLVM dialect op(s). The CIRToLLVMPass
// registers all patterns and runs applyPartialConversion.
//
//===----------------------------------------------------------------===//

#include "COT/Passes.h"
#include "CIR/CIROps.h"

#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Conversion/LLVMCommon/ConversionTarget.h"
#include "mlir/Conversion/LLVMCommon/TypeConverter.h"
#include "mlir/Transforms/DialectConversion.h"

using namespace mlir;

namespace {

//===----------------------------------------------------------------------===//
// Arithmetic lowering
//===----------------------------------------------------------------------===//

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
    // Reference: ArithToLLVM DivSIOpLowering → llvm.sdiv
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
    // Reference: ArithToLLVM RemSIOpLowering → llvm.srem
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
    // Reference: ArithToLLVM — integer neg is sub(0, x)
    auto type = getTypeConverter()->convertType(op.getType());
    auto zero = rewriter.create<LLVM::ConstantOp>(op.getLoc(), type,
        rewriter.getIntegerAttr(type, 0));
    rewriter.replaceOpWithNewOp<LLVM::SubOp>(op, type, zero,
        adaptor.getOperand());
    return success();
  }
};

//===----------------------------------------------------------------------===//
// Bitwise lowering
//===----------------------------------------------------------------------===//

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

struct XorOpLowering : public OpConversionPattern<cir::XorOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(cir::XorOp op, OpAdaptor adaptor,
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
    // Reference: ArithToLLVM — bit_not is xor(x, -1)
    auto type = getTypeConverter()->convertType(op.getType());
    auto allOnes = rewriter.create<LLVM::ConstantOp>(op.getLoc(), type,
        rewriter.getIntegerAttr(type, -1));
    rewriter.replaceOpWithNewOp<LLVM::XOrOp>(op, type,
        adaptor.getOperand(), allOnes);
    return success();
  }
};

//===----------------------------------------------------------------------===//
// Shift lowering
//===----------------------------------------------------------------------===//

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
    // Reference: ArithToLLVM ShRUI — logical (unsigned) shift right
    rewriter.replaceOpWithNewOp<LLVM::LShrOp>(op,
        getTypeConverter()->convertType(op.getType()),
        adaptor.getLhs(), adaptor.getRhs());
    return success();
  }
};

//===----------------------------------------------------------------------===//
// Comparison lowering
//===----------------------------------------------------------------------===//

struct CmpOpLowering : public OpConversionPattern<cir::CmpOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(cir::CmpOp op, OpAdaptor adaptor,
      ConversionPatternRewriter &rewriter) const override {
    // Reference: ArithToLLVM CmpIOpLowering — predicate values match directly
    // CIR::CmpIPredicate enum values match LLVM::ICmpPredicate
    auto pred = static_cast<LLVM::ICmpPredicate>(
        static_cast<uint64_t>(op.getPredicate()));
    rewriter.replaceOpWithNewOp<LLVM::ICmpOp>(op,
        getTypeConverter()->convertType(op.getResult().getType()),
        pred, adaptor.getLhs(), adaptor.getRhs());
    return success();
  }
};

//===----------------------------------------------------------------------===//
// Control flow / misc lowering
//===----------------------------------------------------------------------===//

struct TrapOpLowering : public OpConversionPattern<cir::TrapOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(cir::TrapOp op, OpAdaptor adaptor,
      ConversionPatternRewriter &rewriter) const override {
    // Lower to llvm.trap + llvm.unreachable
    rewriter.create<LLVM::Trap>(op.getLoc());
    rewriter.replaceOpWithNewOp<LLVM::UnreachableOp>(op);
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

//===----------------------------------------------------------------------===//
// Pass definition
//===----------------------------------------------------------------------===//

struct CIRToLLVMPass
    : public PassWrapper<CIRToLLVMPass, OperationPass<ModuleOp>> {
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(CIRToLLVMPass)
  StringRef getArgument() const override { return "cir-to-llvm"; }
  StringRef getDescription() const override {
    return "Lower CIR ops to LLVM dialect";
  }
  void runOnOperation() override {
    LLVMConversionTarget target(getContext());
    target.addLegalOp<ModuleOp>();
    // func ops are lowered by a separate func-to-llvm pass
    target.addLegalDialect<func::FuncDialect>();
    LLVMTypeConverter tc(&getContext());
    RewritePatternSet patterns(&getContext());
    cot::populateCIRToLLVMConversionPatterns(tc, patterns);
    if (failed(applyPartialConversion(getOperation(), target,
                                      std::move(patterns))))
      signalPassFailure();
  }
};

} // namespace

//===----------------------------------------------------------------------===//
// Public API
//===----------------------------------------------------------------------===//

void cot::populateCIRToLLVMConversionPatterns(
    const LLVMTypeConverter &converter,
    RewritePatternSet &patterns) {
  // Reference: arith::populateArithToLLVMConversionPatterns()
  MLIRContext *ctx = patterns.getContext();
  patterns.add<
      // Arithmetic
      AddOpLowering, SubOpLowering, MulOpLowering,
      DivOpLowering, RemOpLowering, NegOpLowering,
      // Bitwise
      BitAndOpLowering, BitOrOpLowering, XorOpLowering, BitNotOpLowering,
      // Shifts
      ShlOpLowering, ShrOpLowering,
      // Comparison, control flow, constants
      CmpOpLowering, TrapOpLowering, ConstantOpLowering
  >(converter, ctx);
}

std::unique_ptr<mlir::Pass> cot::createCIRToLLVMPass() {
  return std::make_unique<CIRToLLVMPass>();
}
