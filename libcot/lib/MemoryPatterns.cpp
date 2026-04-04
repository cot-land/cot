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

/// cir.string_constant → llvm.mlir.global + llvm.mlir.addressof + struct init
/// Reference: Zig string literals → []const u8, FIR fir.boxchar lowering
struct StringConstantOpLowering
    : public OpConversionPattern<cir::StringConstantOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(cir::StringConstantOp op, OpAdaptor adaptor,
      ConversionPatternRewriter &rewriter) const override {
    auto loc = op.getLoc();
    auto module = op->getParentOfType<ModuleOp>();
    if (!module)
      return rewriter.notifyMatchFailure(op, "no parent module");

    llvm::StringRef strValue = op.getValue();
    auto strLen = static_cast<int64_t>(strValue.size());

    // Create a unique global name for this string constant
    // Use a counter based on existing globals to avoid collisions
    unsigned globalIndex = 0;
    for (auto &op2 : module.getBody()->getOperations()) {
      if (llvm::isa<LLVM::GlobalOp>(op2))
        globalIndex++;
    }
    std::string globalName = ".str." + std::to_string(globalIndex);

    // Create llvm.mlir.global constant @.str.N("hello")
    auto i8Type = rewriter.getIntegerType(8);
    auto arrayType = LLVM::LLVMArrayType::get(i8Type, strLen);

    // Insert global at module level (before current function)
    {
      OpBuilder::InsertionGuard guard(rewriter);
      rewriter.setInsertionPointToStart(module.getBody());
      rewriter.create<LLVM::GlobalOp>(
          loc, arrayType, /*isConstant=*/true,
          LLVM::Linkage::Internal, globalName,
          rewriter.getStringAttr(strValue));
    } // guard restores insertion point

    // %ptr = llvm.mlir.addressof @.str.N : !llvm.ptr
    auto ptrType = LLVM::LLVMPointerType::get(op.getContext());
    auto addr = rewriter.create<LLVM::AddressOfOp>(
        loc, ptrType, globalName);

    // %len = llvm.mlir.constant(N : i64)
    auto i64Type = rewriter.getI64Type();
    auto len = rewriter.create<LLVM::ConstantOp>(
        loc, i64Type, rewriter.getI64IntegerAttr(strLen));

    // Construct the fat pointer struct: {ptr, len}
    auto sliceType = getTypeConverter()->convertType(op.getType());
    if (!sliceType)
      return rewriter.notifyMatchFailure(op, "type conversion failed");
    Value result = rewriter.create<LLVM::UndefOp>(loc, sliceType);
    result = rewriter.create<LLVM::InsertValueOp>(loc, result, addr, 0);
    result = rewriter.create<LLVM::InsertValueOp>(loc, result, len, 1);
    rewriter.replaceOp(op, result);
    return success();
  }
};

/// cir.slice_ptr → llvm.extractvalue [0] (pointer field)
struct SlicePtrOpLowering : public OpConversionPattern<cir::SlicePtrOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(cir::SlicePtrOp op, OpAdaptor adaptor,
      ConversionPatternRewriter &rewriter) const override {
    // Slice is !llvm.struct<(!llvm.ptr, i64)> — field 0 is the pointer
    rewriter.replaceOpWithNewOp<LLVM::ExtractValueOp>(
        op, adaptor.getInput(), 0);
    return success();
  }
};

/// cir.slice_len → llvm.extractvalue [1] (length field)
struct SliceLenOpLowering : public OpConversionPattern<cir::SliceLenOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(cir::SliceLenOp op, OpAdaptor adaptor,
      ConversionPatternRewriter &rewriter) const override {
    // Slice is !llvm.struct<(!llvm.ptr, i64)> — field 1 is the length
    rewriter.replaceOpWithNewOp<LLVM::ExtractValueOp>(
        op, adaptor.getInput(), 1);
    return success();
  }
};

/// cir.slice_elem → extractvalue [0] (ptr) + GEP + load
/// Reference: Zig slice indexing pattern
struct SliceElemOpLowering : public OpConversionPattern<cir::SliceElemOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(cir::SliceElemOp op, OpAdaptor adaptor,
      ConversionPatternRewriter &rewriter) const override {
    auto loc = op.getLoc();
    auto elemType = getTypeConverter()->convertType(op.getType());
    if (!elemType)
      return rewriter.notifyMatchFailure(op, "type conversion failed");
    // Extract pointer from slice struct
    auto ptr = rewriter.create<LLVM::ExtractValueOp>(
        loc, adaptor.getInput(), 0);
    // GEP to the element
    auto ptrType = LLVM::LLVMPointerType::get(op.getContext());
    auto gep = rewriter.create<LLVM::GEPOp>(
        loc, ptrType, elemType, ptr,
        llvm::ArrayRef<LLVM::GEPArg>{adaptor.getIndex()});
    // Load the element
    rewriter.replaceOpWithNewOp<LLVM::LoadOp>(op, elemType, gep);
    return success();
  }
};

/// cir.array_to_slice → GEP(start) + sub(end-start) + {ptr, len}
/// Reference: Zig arr[lo..hi] slicing
struct ArrayToSliceOpLowering
    : public OpConversionPattern<cir::ArrayToSliceOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(cir::ArrayToSliceOp op, OpAdaptor adaptor,
      ConversionPatternRewriter &rewriter) const override {
    auto loc = op.getLoc();
    auto sliceType = getTypeConverter()->convertType(op.getType());
    if (!sliceType)
      return rewriter.notifyMatchFailure(op, "type conversion failed");

    auto arrayType = getTypeConverter()->convertType(op.getElemType());
    if (!arrayType)
      return rewriter.notifyMatchFailure(op, "array type conversion failed");

    // GEP to arr[start] — pointer to first element of slice
    auto ptrType = LLVM::LLVMPointerType::get(op.getContext());

    // Get element type from the LLVM array type
    auto llvmArrayType = llvm::dyn_cast<LLVM::LLVMArrayType>(arrayType);
    if (!llvmArrayType)
      return rewriter.notifyMatchFailure(op, "expected LLVM array type");
    auto elemType = llvmArrayType.getElementType();

    auto startPtr = rewriter.create<LLVM::GEPOp>(
        loc, ptrType, arrayType, adaptor.getBase(),
        llvm::ArrayRef<LLVM::GEPArg>{0, adaptor.getStart()});

    // Length = end - start
    auto len = rewriter.create<LLVM::SubOp>(
        loc, adaptor.getEnd(), adaptor.getStart());

    // Build {ptr, len} struct
    Value result = rewriter.create<LLVM::UndefOp>(loc, sliceType);
    result = rewriter.create<LLVM::InsertValueOp>(loc, result, startPtr, 0);
    result = rewriter.create<LLVM::InsertValueOp>(loc, result, len, 1);
    rewriter.replaceOp(op, result);
    return success();
  }
};

/// Helper: check if CIR optional type is pointer-like (null-ptr optimization).
static bool isPointerLikeOptional(cir::OptionalType optType) {
  return optType.isPointerLike();
}

/// cir.none → null optional value
/// Non-pointer: undef struct + insertvalue(i1 0, [1])
/// Pointer: llvm.mlir.zero (null pointer)
struct NoneOpLowering : public OpConversionPattern<cir::NoneOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(cir::NoneOp op, OpAdaptor adaptor,
      ConversionPatternRewriter &rewriter) const override {
    auto loc = op.getLoc();
    auto optType = llvm::cast<cir::OptionalType>(op.getType());
    auto llvmType = getTypeConverter()->convertType(op.getType());
    if (!llvmType)
      return rewriter.notifyMatchFailure(op, "type conversion failed");
    if (isPointerLikeOptional(optType)) {
      // Null pointer
      rewriter.replaceOpWithNewOp<LLVM::ZeroOp>(op, llvmType);
    } else {
      // Struct with tag=0: {undef_payload, i1 0}
      Value result = rewriter.create<LLVM::UndefOp>(loc, llvmType);
      auto zero = rewriter.create<LLVM::ConstantOp>(
          loc, rewriter.getI1Type(), rewriter.getBoolAttr(false));
      result = rewriter.create<LLVM::InsertValueOp>(loc, result, zero, 1);
      rewriter.replaceOp(op, result);
    }
    return success();
  }
};

/// cir.wrap_optional → wrap T in ?T
/// Non-pointer: undef struct + insertvalue(payload, [0]) + insertvalue(i1 1, [1])
/// Pointer: identity (pointer IS the optional)
struct WrapOptionalOpLowering
    : public OpConversionPattern<cir::WrapOptionalOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(cir::WrapOptionalOp op, OpAdaptor adaptor,
      ConversionPatternRewriter &rewriter) const override {
    auto loc = op.getLoc();
    auto optType = llvm::cast<cir::OptionalType>(op.getType());
    auto llvmType = getTypeConverter()->convertType(op.getType());
    if (!llvmType)
      return rewriter.notifyMatchFailure(op, "type conversion failed");
    if (isPointerLikeOptional(optType)) {
      // Pointer: the value IS the optional
      rewriter.replaceOp(op, adaptor.getInput());
    } else {
      // Struct: {payload, tag=1}
      Value result = rewriter.create<LLVM::UndefOp>(loc, llvmType);
      result = rewriter.create<LLVM::InsertValueOp>(
          loc, result, adaptor.getInput(), 0);
      auto one = rewriter.create<LLVM::ConstantOp>(
          loc, rewriter.getI1Type(), rewriter.getBoolAttr(true));
      result = rewriter.create<LLVM::InsertValueOp>(loc, result, one, 1);
      rewriter.replaceOp(op, result);
    }
    return success();
  }
};

/// cir.is_non_null → test optional for non-null
/// Non-pointer: extractvalue [1] (tag field)
/// Pointer: icmp ne ptr, null
struct IsNonNullOpLowering
    : public OpConversionPattern<cir::IsNonNullOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(cir::IsNonNullOp op, OpAdaptor adaptor,
      ConversionPatternRewriter &rewriter) const override {
    auto loc = op.getLoc();
    auto optType = llvm::cast<cir::OptionalType>(op.getInput().getType());
    if (isPointerLikeOptional(optType)) {
      // icmp ne ptr, null
      auto null = rewriter.create<LLVM::ZeroOp>(
          loc, LLVM::LLVMPointerType::get(op.getContext()));
      rewriter.replaceOpWithNewOp<LLVM::ICmpOp>(
          op, LLVM::ICmpPredicate::ne, adaptor.getInput(), null);
    } else {
      // extractvalue [1] — the tag field
      rewriter.replaceOpWithNewOp<LLVM::ExtractValueOp>(
          op, adaptor.getInput(), 1);
    }
    return success();
  }
};

/// cir.optional_payload → extract payload from optional (unchecked)
/// Non-pointer: extractvalue [0] (payload field)
/// Pointer: identity (pointer IS the payload)
struct OptionalPayloadOpLowering
    : public OpConversionPattern<cir::OptionalPayloadOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(cir::OptionalPayloadOp op, OpAdaptor adaptor,
      ConversionPatternRewriter &rewriter) const override {
    auto optType = llvm::cast<cir::OptionalType>(op.getInput().getType());
    if (isPointerLikeOptional(optType)) {
      // Pointer: the optional IS the payload
      rewriter.replaceOp(op, adaptor.getInput());
    } else {
      // extractvalue [0] — the payload field
      rewriter.replaceOpWithNewOp<LLVM::ExtractValueOp>(
          op, adaptor.getInput(), 0);
    }
    return success();
  }
};

/// cir.wrap_result → wrap T in E!T (success, error_code=0)
/// undef struct + insertvalue(payload, [0]) + insertvalue(i16 0, [1])
/// Reference: Zig wrap_errunion_payload AIR instruction
struct WrapResultOpLowering
    : public OpConversionPattern<cir::WrapResultOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(cir::WrapResultOp op, OpAdaptor adaptor,
      ConversionPatternRewriter &rewriter) const override {
    auto loc = op.getLoc();
    auto llvmType = getTypeConverter()->convertType(op.getType());
    if (!llvmType)
      return rewriter.notifyMatchFailure(op, "type conversion failed");
    // {payload, error_code=0}
    Value result = rewriter.create<LLVM::UndefOp>(loc, llvmType);
    result = rewriter.create<LLVM::InsertValueOp>(
        loc, result, adaptor.getInput(), 0);
    auto zero = rewriter.create<LLVM::ConstantOp>(
        loc, rewriter.getIntegerType(16),
        rewriter.getIntegerAttr(rewriter.getIntegerType(16), 0));
    result = rewriter.create<LLVM::InsertValueOp>(loc, result, zero, 1);
    rewriter.replaceOp(op, result);
    return success();
  }
};

/// cir.wrap_error → wrap error code in E!T (error, payload=undef)
/// undef struct + insertvalue(error_code, [1])
/// Reference: Zig wrap_errunion_err AIR instruction
struct WrapErrorOpLowering
    : public OpConversionPattern<cir::WrapErrorOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(cir::WrapErrorOp op, OpAdaptor adaptor,
      ConversionPatternRewriter &rewriter) const override {
    auto loc = op.getLoc();
    auto llvmType = getTypeConverter()->convertType(op.getType());
    if (!llvmType)
      return rewriter.notifyMatchFailure(op, "type conversion failed");
    // {undef_payload, error_code}
    Value result = rewriter.create<LLVM::UndefOp>(loc, llvmType);
    result = rewriter.create<LLVM::InsertValueOp>(
        loc, result, adaptor.getInput(), 1);
    rewriter.replaceOp(op, result);
    return success();
  }
};

/// cir.is_error → test error union for error
/// extractvalue [1] (error code) + icmp ne i16, 0
/// Reference: Zig is_err AIR instruction
struct IsErrorOpLowering
    : public OpConversionPattern<cir::IsErrorOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(cir::IsErrorOp op, OpAdaptor adaptor,
      ConversionPatternRewriter &rewriter) const override {
    auto loc = op.getLoc();
    // Extract error code (field [1])
    auto errorCode = rewriter.create<LLVM::ExtractValueOp>(
        loc, adaptor.getInput(), 1);
    // Compare: error_code != 0
    auto zero = rewriter.create<LLVM::ConstantOp>(
        loc, rewriter.getIntegerType(16),
        rewriter.getIntegerAttr(rewriter.getIntegerType(16), 0));
    rewriter.replaceOpWithNewOp<LLVM::ICmpOp>(
        op, LLVM::ICmpPredicate::ne, errorCode, zero);
    return success();
  }
};

/// cir.error_payload → extract payload from error union (unchecked)
/// extractvalue [0]
/// Reference: Zig unwrap_errunion_payload AIR instruction
struct ErrorPayloadOpLowering
    : public OpConversionPattern<cir::ErrorPayloadOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(cir::ErrorPayloadOp op, OpAdaptor adaptor,
      ConversionPatternRewriter &rewriter) const override {
    rewriter.replaceOpWithNewOp<LLVM::ExtractValueOp>(
        op, adaptor.getInput(), 0);
    return success();
  }
};

/// cir.error_code → extract error code from error union
/// extractvalue [1]
/// Reference: Zig unwrap_errunion_err AIR instruction
struct ErrorCodeOpLowering
    : public OpConversionPattern<cir::ErrorCodeOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(cir::ErrorCodeOp op, OpAdaptor adaptor,
      ConversionPatternRewriter &rewriter) const override {
    rewriter.replaceOpWithNewOp<LLVM::ExtractValueOp>(
        op, adaptor.getInput(), 1);
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
               StructInitOpLowering, StringConstantOpLowering,
               SlicePtrOpLowering, SliceLenOpLowering, SliceElemOpLowering,
               ArrayToSliceOpLowering,
               NoneOpLowering, WrapOptionalOpLowering,
               IsNonNullOpLowering, OptionalPayloadOpLowering,
               WrapResultOpLowering, WrapErrorOpLowering,
               IsErrorOpLowering, ErrorPayloadOpLowering,
               ErrorCodeOpLowering,
               ArrayInitOpLowering, ElemValOpLowering, ElemPtrOpLowering>(
      converter, ctx);
}
