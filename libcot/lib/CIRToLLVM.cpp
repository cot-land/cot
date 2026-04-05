//===- CIRToLLVM.cpp - CIR → LLVM dialect lowering pass ---------------===//
//
// Pass definition and top-level pattern population.
// Individual patterns are in category files:
//   ArithmeticPatterns.cpp, BitwisePatterns.cpp,
//   MemoryPatterns.cpp, ControlFlowPatterns.cpp
//
// Reference: mlir/lib/Conversion/ArithToLLVM/ArithToLLVM.cpp
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
#include "mlir/Conversion/FuncToLLVM/ConvertFuncToLLVM.h"
#include "mlir/Transforms/DialectConversion.h"

using namespace mlir;

namespace {

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

    LLVMTypeConverter tc(&getContext());
    // CIR type → LLVM type conversions
    tc.addConversion([](cir::PointerType type) {
      return LLVM::LLVMPointerType::get(type.getContext());
    });
    // !cir.ref<T> → !llvm.ptr (same as !cir.ptr — zero runtime cost)
    tc.addConversion([](cir::RefType type) {
      return LLVM::LLVMPointerType::get(type.getContext());
    });
    tc.addConversion([&tc](cir::StructType type) -> mlir::Type {
      llvm::SmallVector<mlir::Type> fields;
      for (auto f : type.getFieldTypes())
        fields.push_back(tc.convertType(f));
      return LLVM::LLVMStructType::getLiteral(type.getContext(), fields);
    });
    tc.addConversion([&tc](cir::ArrayType type) -> mlir::Type {
      return LLVM::LLVMArrayType::get(
          tc.convertType(type.getElementType()), type.getSize());
    });
    // !cir.optional<T>:
    //   Pointer-like: → !llvm.ptr (null = none)
    //   Non-pointer:  → !llvm.struct<(T, i1)> where i1 is tag (1=some, 0=none)
    // Reference: Zig ?T layout, Rust Option niche encoding
    tc.addConversion([&tc](cir::OptionalType type) -> mlir::Type {
      auto ctx = type.getContext();
      if (type.isPointerLike()) {
        return LLVM::LLVMPointerType::get(ctx);
      }
      auto payloadType = tc.convertType(type.getPayloadType());
      auto tagType = IntegerType::get(ctx, 1);
      return LLVM::LLVMStructType::getLiteral(ctx, {payloadType, tagType});
    });
    // !cir.enum<"Name", TagType, ...> → TagType
    // Enum IS its tag integer at LLVM level. Variant names dropped.
    // Reference: Zig enum(u8) → u8
    tc.addConversion([](cir::EnumType type) -> mlir::Type {
      return type.getTagType();
    });
    // !cir.tagged_union<"Name", ...> → !llvm.struct<(i8, [max_payload x i8])>
    // Tag is i8 (supports up to 256 variants). Payload is byte array
    // sized to the largest variant.
    // Reference: Rust Variants::Multiple with TagEncoding::Direct
    tc.addConversion([&tc](cir::TaggedUnionType type) -> mlir::Type {
      auto ctx = type.getContext();
      auto tagType = IntegerType::get(ctx, 8);
      unsigned maxBits = type.getMaxPayloadBitWidth();
      unsigned payloadBytes = (maxBits + 7) / 8;
      if (payloadBytes == 0) payloadBytes = 1; // min 1 byte
      auto payloadType = LLVM::LLVMArrayType::get(
          IntegerType::get(ctx, 8), payloadBytes);
      return LLVM::LLVMStructType::getLiteral(ctx, {tagType, payloadType});
    });
    // !cir.error_union<T> → !llvm.struct<(T, i16)>
    // Layout: {payload, error_code}. error_code=0 means success.
    // Reference: Zig E!T layout (InternPool ErrorUnionType)
    tc.addConversion([&tc](cir::ErrorUnionType type) -> mlir::Type {
      auto ctx = type.getContext();
      auto payloadType = tc.convertType(type.getPayloadType());
      auto errorCodeType = IntegerType::get(ctx, 16);
      return LLVM::LLVMStructType::getLiteral(ctx,
                                               {payloadType, errorCodeType});
    });
    // !cir.slice<T> → !llvm.struct<(!llvm.ptr, i64)>
    // Fat pointer: {pointer to data, length}
    // Reference: Zig []T, FIR fir.boxchar
    tc.addConversion([](cir::SliceType type) -> mlir::Type {
      auto ctx = type.getContext();
      auto ptrType = LLVM::LLVMPointerType::get(ctx);
      auto lenType = IntegerType::get(ctx, 64);
      return LLVM::LLVMStructType::getLiteral(ctx, {ptrType, lenType});
    });

    RewritePatternSet patterns(&getContext());
    cot::populateCIRToLLVMConversionPatterns(tc, patterns);
    // Also convert func ops in the same pass with shared type converter.
    // This ensures CIR types in function signatures get converted.
    mlir::populateFuncToLLVMConversionPatterns(tc, patterns);
    if (failed(applyFullConversion(getOperation(), target,
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
  populateArithmeticPatterns(converter, patterns);
  populateBitwisePatterns(converter, patterns);
  populateMemoryPatterns(converter, patterns);
  populateControlFlowPatterns(converter, patterns);
}

std::unique_ptr<mlir::Pass> cot::createCIRToLLVMPass() {
  return std::make_unique<CIRToLLVMPass>();
}
