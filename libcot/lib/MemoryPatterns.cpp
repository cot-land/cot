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

/// cir.addr_of → identity (both !cir.ptr and !cir.ref<T> lower to !llvm.ptr)
struct AddrOfOpLowering : public OpConversionPattern<cir::AddrOfOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(cir::AddrOfOp op, OpAdaptor adaptor,
      ConversionPatternRewriter &rewriter) const override {
    rewriter.replaceOp(op, adaptor.getAddr());
    return success();
  }
};

/// cir.deref → llvm.load (type-safe load through !cir.ref<T>)
struct DerefOpLowering : public OpConversionPattern<cir::DerefOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(cir::DerefOp op, OpAdaptor adaptor,
      ConversionPatternRewriter &rewriter) const override {
    auto resultType = getTypeConverter()->convertType(op.getType());
    if (!resultType)
      return rewriter.notifyMatchFailure(op, "type conversion failed");
    rewriter.replaceOpWithNewOp<LLVM::LoadOp>(op, resultType, adaptor.getRef());
    return success();
  }
};

/// cir.field_val → llvm.extractvalue
/// Reference: FIR ExtractValueOpConversion
struct FieldValOpLowering : public OpConversionPattern<cir::FieldValOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(cir::FieldValOp op, OpAdaptor adaptor,
      ConversionPatternRewriter &rewriter) const override {
    auto resultType = getTypeConverter()->convertType(op.getType());
    if (!resultType)
      return rewriter.notifyMatchFailure(op, "failed to convert result type");
    rewriter.replaceOpWithNewOp<LLVM::ExtractValueOp>(
        op, adaptor.getInput(), op.getFieldIndex());
    return success();
  }
};

/// cir.field_ptr → llvm.getelementptr [0, field_index]
/// Reference: FIR CoordinateOpConversion
struct FieldPtrOpLowering : public OpConversionPattern<cir::FieldPtrOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(cir::FieldPtrOp op, OpAdaptor adaptor,
      ConversionPatternRewriter &rewriter) const override {
    auto structType = getTypeConverter()->convertType(op.getElemType());
    if (!structType)
      return rewriter.notifyMatchFailure(op, "failed to convert struct type");
    auto ptrType = LLVM::LLVMPointerType::get(op.getContext());
    rewriter.replaceOpWithNewOp<LLVM::GEPOp>(
        op, ptrType, structType, adaptor.getBase(),
        llvm::ArrayRef<LLVM::GEPArg>{0, static_cast<int32_t>(op.getFieldIndex())});
    return success();
  }
};

/// cir.array_init → llvm.mlir.undef + llvm.insertvalue chain
struct ArrayInitOpLowering : public OpConversionPattern<cir::ArrayInitOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(cir::ArrayInitOp op, OpAdaptor adaptor,
      ConversionPatternRewriter &rewriter) const override {
    auto llvmType = getTypeConverter()->convertType(op.getType());
    if (!llvmType)
      return rewriter.notifyMatchFailure(op, "failed to convert type");
    Value result = rewriter.create<LLVM::UndefOp>(op.getLoc(), llvmType);
    for (auto [i, elem] : llvm::enumerate(adaptor.getElements())) {
      result = rewriter.create<LLVM::InsertValueOp>(
          op.getLoc(), result, elem, i);
    }
    rewriter.replaceOp(op, result);
    return success();
  }
};

/// cir.elem_val → llvm.extractvalue (constant index)
struct ElemValOpLowering : public OpConversionPattern<cir::ElemValOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(cir::ElemValOp op, OpAdaptor adaptor,
      ConversionPatternRewriter &rewriter) const override {
    rewriter.replaceOpWithNewOp<LLVM::ExtractValueOp>(
        op, adaptor.getInput(), op.getIndex());
    return success();
  }
};

/// cir.elem_ptr → llvm.getelementptr [0, %index] (dynamic index)
struct ElemPtrOpLowering : public OpConversionPattern<cir::ElemPtrOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(cir::ElemPtrOp op, OpAdaptor adaptor,
      ConversionPatternRewriter &rewriter) const override {
    auto arrayType = getTypeConverter()->convertType(op.getElemType());
    if (!arrayType)
      return rewriter.notifyMatchFailure(op, "failed to convert array type");
    auto ptrType = LLVM::LLVMPointerType::get(op.getContext());
    rewriter.replaceOpWithNewOp<LLVM::GEPOp>(
        op, ptrType, arrayType, adaptor.getBase(),
        llvm::ArrayRef<LLVM::GEPArg>{0, adaptor.getIndex()});
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
               AddrOfOpLowering, DerefOpLowering,
               FieldValOpLowering, FieldPtrOpLowering,
               StructInitOpLowering,
               ArrayInitOpLowering, ElemValOpLowering, ElemPtrOpLowering>(
      converter, ctx);
}
