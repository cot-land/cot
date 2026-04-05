//===- CIRCApi.cpp - CIR dialect C API implementation ----------------===//
//
// Type-safe C API for building CIR ops. Eliminates raw mlirOperationCreate
// boilerplate in non-C++ frontends.
//
// Reference: mlir/lib/CAPI/IR/IR.cpp pattern.
//
//===----------------------------------------------------------------===//

#include "CIRCApi.h"
#include "CIR/CIROps.h"

#include "mlir/CAPI/IR.h"
#include "mlir/CAPI/Registration.h"
#include "mlir/CAPI/Support.h"
#include "mlir/IR/Builders.h"

using namespace mlir;

//===----------------------------------------------------------------------===//
// Helpers
//===----------------------------------------------------------------------===//

/// Create an OpBuilder at the end of a block.
static OpBuilder builderAtEnd(MlirBlock block, MlirLocation loc) {
  Block *b = unwrap(block);
  return OpBuilder::atBlockEnd(b);
}

//===----------------------------------------------------------------------===//
// Dialect Registration
//===----------------------------------------------------------------------===//

void cirRegisterDialect(MlirContext ctx) {
  unwrap(ctx)->getOrLoadDialect<cir::CIRDialect>();
}

//===----------------------------------------------------------------------===//
// Type Constructors
//===----------------------------------------------------------------------===//

MlirType cirPointerTypeGet(MlirContext ctx) {
  return wrap(cir::PointerType::get(unwrap(ctx)));
}

MlirType cirRefTypeGet(MlirContext ctx, MlirType pointeeType) {
  return wrap(cir::RefType::get(unwrap(ctx), unwrap(pointeeType)));
}

MlirType cirStructTypeGet(MlirContext ctx, MlirStringRef name,
                          intptr_t nFields,
                          MlirStringRef *fieldNames,
                          MlirType *fieldTypes) {
  auto *context = unwrap(ctx);
  llvm::SmallVector<StringAttr> names;
  llvm::SmallVector<Type> types;
  for (intptr_t i = 0; i < nFields; i++) {
    names.push_back(StringAttr::get(context, unwrap(fieldNames[i])));
    types.push_back(unwrap(fieldTypes[i]));
  }
  return wrap(cir::StructType::get(context, unwrap(name), names, types));
}

MlirType cirArrayTypeGet(MlirContext ctx, int64_t size,
                         MlirType elementType) {
  return wrap(cir::ArrayType::get(unwrap(ctx), size, unwrap(elementType)));
}

MlirType cirSliceTypeGet(MlirContext ctx, MlirType elementType) {
  return wrap(cir::SliceType::get(unwrap(ctx), unwrap(elementType)));
}

//===----------------------------------------------------------------------===//
// Type Queries
//===----------------------------------------------------------------------===//

bool cirTypeIsPointer(MlirType type) {
  return llvm::isa<cir::PointerType>(unwrap(type));
}

bool cirTypeIsRef(MlirType type) {
  return llvm::isa<cir::RefType>(unwrap(type));
}

MlirType cirRefTypeGetPointee(MlirType refType) {
  return wrap(llvm::cast<cir::RefType>(unwrap(refType)).getPointeeType());
}

bool cirTypeIsStruct(MlirType type) {
  return llvm::isa<cir::StructType>(unwrap(type));
}

intptr_t cirStructTypeGetNumFields(MlirType structType) {
  return llvm::cast<cir::StructType>(unwrap(structType))
      .getFieldTypes().size();
}

int cirStructTypeGetFieldIndex(MlirType structType, MlirStringRef name) {
  return llvm::cast<cir::StructType>(unwrap(structType))
      .getFieldIndex(unwrap(name));
}

bool cirTypeIsArray(MlirType type) {
  return llvm::isa<cir::ArrayType>(unwrap(type));
}

int64_t cirArrayTypeGetSize(MlirType arrayType) {
  return llvm::cast<cir::ArrayType>(unwrap(arrayType)).getSize();
}

MlirType cirArrayTypeGetElementType(MlirType arrayType) {
  return wrap(llvm::cast<cir::ArrayType>(unwrap(arrayType)).getElementType());
}

bool cirTypeIsSlice(MlirType type) {
  return llvm::isa<cir::SliceType>(unwrap(type));
}

MlirType cirSliceTypeGetElementType(MlirType sliceType) {
  return wrap(
      llvm::cast<cir::SliceType>(unwrap(sliceType)).getElementType());
}

//===----------------------------------------------------------------------===//
// Constants
//===----------------------------------------------------------------------===//

MlirValue cirBuildConstantInt(MlirBlock block, MlirLocation loc,
                              MlirType type, int64_t value) {
  auto b = builderAtEnd(block, loc);
  auto l = unwrap(loc);
  auto t = unwrap(type);
  auto op = b.create<cir::ConstantOp>(l, t, b.getIntegerAttr(t, value));
  return wrap(op.getResult());
}

MlirValue cirBuildConstantFloat(MlirBlock block, MlirLocation loc,
                                MlirType type, double value) {
  auto b = builderAtEnd(block, loc);
  auto l = unwrap(loc);
  auto t = unwrap(type);
  auto op = b.create<cir::ConstantOp>(l, t, b.getFloatAttr(t, value));
  return wrap(op.getResult());
}

MlirValue cirBuildConstantBool(MlirBlock block, MlirLocation loc,
                               bool value) {
  auto b = builderAtEnd(block, loc);
  auto l = unwrap(loc);
  auto t = b.getI1Type();
  auto op = b.create<cir::ConstantOp>(l, t,
      b.getIntegerAttr(t, value ? 1 : 0));
  return wrap(op.getResult());
}

MlirValue cirBuildStringConstant(MlirBlock block, MlirLocation loc,
                                 MlirStringRef value) {
  auto b = builderAtEnd(block, loc);
  auto l = unwrap(loc);
  auto sliceType = cir::SliceType::get(b.getContext(), b.getIntegerType(8));
  auto op = b.create<cir::StringConstantOp>(l, sliceType,
      b.getStringAttr(unwrap(value)));
  return wrap(op.getResult());
}

//===----------------------------------------------------------------------===//
// Arithmetic — binary ops share a pattern
//===----------------------------------------------------------------------===//

#define CIR_BINARY_OP(Name, OpClass)                                    \
  MlirValue cirBuild##Name(MlirBlock block, MlirLocation loc,          \
                           MlirType type, MlirValue lhs,               \
                           MlirValue rhs) {                             \
    auto b = builderAtEnd(block, loc);                                  \
    auto op = b.create<cir::OpClass>(unwrap(loc), unwrap(type),         \
                                     unwrap(lhs), unwrap(rhs));         \
    return wrap(op.getResult());                                        \
  }

CIR_BINARY_OP(Add, AddOp)
CIR_BINARY_OP(Sub, SubOp)
CIR_BINARY_OP(Mul, MulOp)
CIR_BINARY_OP(Div, DivOp)
CIR_BINARY_OP(Rem, RemOp)
CIR_BINARY_OP(BitAnd, BitAndOp)
CIR_BINARY_OP(BitOr, BitOrOp)
CIR_BINARY_OP(BitXor, BitXorOp)
CIR_BINARY_OP(Shl, ShlOp)
CIR_BINARY_OP(Shr, ShrOp)

#undef CIR_BINARY_OP

//===----------------------------------------------------------------------===//
// Unary ops
//===----------------------------------------------------------------------===//

#define CIR_UNARY_OP(Name, OpClass)                                     \
  MlirValue cirBuild##Name(MlirBlock block, MlirLocation loc,          \
                           MlirType type, MlirValue operand) {          \
    auto b = builderAtEnd(block, loc);                                  \
    auto op = b.create<cir::OpClass>(unwrap(loc), unwrap(type),         \
                                     unwrap(operand));                   \
    return wrap(op.getResult());                                        \
  }

CIR_UNARY_OP(Neg, NegOp)
CIR_UNARY_OP(BitNot, BitNotOp)

#undef CIR_UNARY_OP

//===----------------------------------------------------------------------===//
// Comparison + Select
//===----------------------------------------------------------------------===//

MlirValue cirBuildCmp(MlirBlock block, MlirLocation loc,
                      enum CirCmpPredicate predicate,
                      MlirValue lhs, MlirValue rhs) {
  auto b = builderAtEnd(block, loc);
  auto pred = static_cast<cir::CmpIPredicate>(predicate);
  auto op = b.create<cir::CmpOp>(unwrap(loc), pred,
                                  unwrap(lhs), unwrap(rhs));
  return wrap(op.getResult());
}

MlirValue cirBuildSelect(MlirBlock block, MlirLocation loc,
                         MlirType resultType, MlirValue condition,
                         MlirValue trueVal, MlirValue falseVal) {
  auto b = builderAtEnd(block, loc);
  auto op = b.create<cir::SelectOp>(unwrap(loc), unwrap(resultType),
      unwrap(condition), unwrap(trueVal), unwrap(falseVal));
  return wrap(op.getResult());
}

//===----------------------------------------------------------------------===//
// Type Casts
//===----------------------------------------------------------------------===//

#define CIR_CAST_OP(Name, OpClass)                                      \
  MlirValue cirBuild##Name(MlirBlock block, MlirLocation loc,          \
                           MlirType dstType, MlirValue input) {         \
    auto b = builderAtEnd(block, loc);                                  \
    auto op = b.create<cir::OpClass>(unwrap(loc), unwrap(dstType),      \
                                     unwrap(input));                     \
    return wrap(op.getResult());                                        \
  }

CIR_CAST_OP(ExtSI, ExtSIOp)
CIR_CAST_OP(ExtUI, ExtUIOp)
CIR_CAST_OP(TruncI, TruncIOp)
CIR_CAST_OP(SIToFP, SIToFPOp)
CIR_CAST_OP(FPToSI, FPToSIOp)
CIR_CAST_OP(ExtF, ExtFOp)
CIR_CAST_OP(TruncF, TruncFOp)

#undef CIR_CAST_OP

//===----------------------------------------------------------------------===//
// Memory
//===----------------------------------------------------------------------===//

MlirValue cirBuildAlloca(MlirBlock block, MlirLocation loc,
                         MlirType elemType) {
  auto b = builderAtEnd(block, loc);
  auto ptrType = cir::PointerType::get(b.getContext());
  auto op = b.create<cir::AllocaOp>(unwrap(loc), ptrType,
      TypeAttr::get(unwrap(elemType)));
  return wrap(op.getResult());
}

void cirBuildStore(MlirBlock block, MlirLocation loc,
                   MlirValue value, MlirValue addr) {
  auto b = builderAtEnd(block, loc);
  b.create<cir::StoreOp>(unwrap(loc), unwrap(value), unwrap(addr));
}

MlirValue cirBuildLoad(MlirBlock block, MlirLocation loc,
                       MlirType resultType, MlirValue addr) {
  auto b = builderAtEnd(block, loc);
  auto op = b.create<cir::LoadOp>(unwrap(loc), unwrap(resultType),
                                   unwrap(addr));
  return wrap(op.getResult());
}

//===----------------------------------------------------------------------===//
// References
//===----------------------------------------------------------------------===//

MlirValue cirBuildAddrOf(MlirBlock block, MlirLocation loc,
                         MlirType refType, MlirValue addr) {
  auto b = builderAtEnd(block, loc);
  auto op = b.create<cir::AddrOfOp>(unwrap(loc), unwrap(refType),
                                     unwrap(addr));
  return wrap(op.getResult());
}

MlirValue cirBuildDeref(MlirBlock block, MlirLocation loc,
                        MlirType resultType, MlirValue ref) {
  auto b = builderAtEnd(block, loc);
  auto op = b.create<cir::DerefOp>(unwrap(loc), unwrap(resultType),
                                    unwrap(ref));
  return wrap(op.getResult());
}

//===----------------------------------------------------------------------===//
// Aggregates — Structs
//===----------------------------------------------------------------------===//

MlirValue cirBuildStructInit(MlirBlock block, MlirLocation loc,
                             MlirType structType,
                             intptr_t nFields, MlirValue *fields) {
  auto b = builderAtEnd(block, loc);
  llvm::SmallVector<Value> fieldVals;
  for (intptr_t i = 0; i < nFields; i++)
    fieldVals.push_back(unwrap(fields[i]));
  auto op = b.create<cir::StructInitOp>(unwrap(loc), unwrap(structType),
                                         fieldVals);
  return wrap(op.getResult());
}

MlirValue cirBuildFieldVal(MlirBlock block, MlirLocation loc,
                           MlirType resultType, MlirValue input,
                           int64_t fieldIndex) {
  auto b = builderAtEnd(block, loc);
  auto op = b.create<cir::FieldValOp>(unwrap(loc), unwrap(resultType),
      unwrap(input), b.getI64IntegerAttr(fieldIndex));
  return wrap(op.getResult());
}

MlirValue cirBuildFieldPtr(MlirBlock block, MlirLocation loc,
                           MlirValue base, int64_t fieldIndex,
                           MlirType elemType) {
  auto b = builderAtEnd(block, loc);
  auto ptrType = cir::PointerType::get(b.getContext());
  auto op = b.create<cir::FieldPtrOp>(unwrap(loc), ptrType,
      unwrap(base), b.getI64IntegerAttr(fieldIndex),
      TypeAttr::get(unwrap(elemType)));
  return wrap(op.getResult());
}

//===----------------------------------------------------------------------===//
// Aggregates — Arrays
//===----------------------------------------------------------------------===//

MlirValue cirBuildArrayInit(MlirBlock block, MlirLocation loc,
                            MlirType arrayType,
                            intptr_t nElements, MlirValue *elements) {
  auto b = builderAtEnd(block, loc);
  llvm::SmallVector<Value> elemVals;
  for (intptr_t i = 0; i < nElements; i++)
    elemVals.push_back(unwrap(elements[i]));
  auto op = b.create<cir::ArrayInitOp>(unwrap(loc), unwrap(arrayType),
                                        elemVals);
  return wrap(op.getResult());
}

MlirValue cirBuildElemVal(MlirBlock block, MlirLocation loc,
                          MlirType resultType, MlirValue input,
                          int64_t index) {
  auto b = builderAtEnd(block, loc);
  auto op = b.create<cir::ElemValOp>(unwrap(loc), unwrap(resultType),
      unwrap(input), b.getI64IntegerAttr(index));
  return wrap(op.getResult());
}

MlirValue cirBuildElemPtr(MlirBlock block, MlirLocation loc,
                          MlirValue base, MlirValue index,
                          MlirType elemType) {
  auto b = builderAtEnd(block, loc);
  auto ptrType = cir::PointerType::get(b.getContext());
  auto op = b.create<cir::ElemPtrOp>(unwrap(loc), ptrType,
      unwrap(base), unwrap(index), TypeAttr::get(unwrap(elemType)));
  return wrap(op.getResult());
}

//===----------------------------------------------------------------------===//
// Control Flow
//===----------------------------------------------------------------------===//

void cirBuildBr(MlirBlock block, MlirLocation loc,
                MlirBlock dest,
                intptr_t nArgs, MlirValue *args) {
  auto b = builderAtEnd(block, loc);
  llvm::SmallVector<Value> argVals;
  for (intptr_t i = 0; i < nArgs; i++)
    argVals.push_back(unwrap(args[i]));
  b.create<cir::BrOp>(unwrap(loc), argVals, unwrap(dest));
}

void cirBuildCondBr(MlirBlock block, MlirLocation loc,
                    MlirValue condition,
                    MlirBlock trueDest, MlirBlock falseDest) {
  auto b = builderAtEnd(block, loc);
  b.create<cir::CondBrOp>(unwrap(loc), unwrap(condition),
                           unwrap(trueDest), unwrap(falseDest));
}

void cirBuildTrap(MlirBlock block, MlirLocation loc) {
  auto b = builderAtEnd(block, loc);
  b.create<cir::TrapOp>(unwrap(loc));
}

//===----------------------------------------------------------------------===//
// Slice Operations
//===----------------------------------------------------------------------===//

MlirValue cirBuildSlicePtr(MlirBlock block, MlirLocation loc,
                           MlirValue slice) {
  auto b = builderAtEnd(block, loc);
  auto ptrType = cir::PointerType::get(b.getContext());
  auto op = b.create<cir::SlicePtrOp>(unwrap(loc), ptrType, unwrap(slice));
  return wrap(op.getResult());
}

MlirValue cirBuildSliceLen(MlirBlock block, MlirLocation loc,
                           MlirValue slice) {
  auto b = builderAtEnd(block, loc);
  auto i64Type = b.getI64Type();
  auto op = b.create<cir::SliceLenOp>(unwrap(loc), i64Type, unwrap(slice));
  return wrap(op.getResult());
}

MlirValue cirBuildSliceElem(MlirBlock block, MlirLocation loc,
                            MlirType elemType, MlirValue slice,
                            MlirValue index) {
  auto b = builderAtEnd(block, loc);
  auto op = b.create<cir::SliceElemOp>(unwrap(loc), unwrap(elemType),
                                        unwrap(slice), unwrap(index));
  return wrap(op.getResult());
}

//===----------------------------------------------------------------------===//
// Optional Type + Operations
//===----------------------------------------------------------------------===//

MlirType cirOptionalTypeGet(MlirContext ctx, MlirType payloadType) {
  return wrap(cir::OptionalType::get(unwrap(ctx), unwrap(payloadType)));
}

bool cirTypeIsOptional(MlirType type) {
  return llvm::isa<cir::OptionalType>(unwrap(type));
}

MlirType cirOptionalTypeGetPayload(MlirType optType) {
  return wrap(
      llvm::cast<cir::OptionalType>(unwrap(optType)).getPayloadType());
}

bool cirOptionalTypeIsPointerLike(MlirType optType) {
  return llvm::cast<cir::OptionalType>(unwrap(optType)).isPointerLike();
}

MlirValue cirBuildNone(MlirBlock block, MlirLocation loc,
                       MlirType optionalType) {
  auto b = builderAtEnd(block, loc);
  auto op = b.create<cir::NoneOp>(unwrap(loc), unwrap(optionalType));
  return wrap(op.getResult());
}

MlirValue cirBuildWrapOptional(MlirBlock block, MlirLocation loc,
                               MlirType optionalType, MlirValue value) {
  auto b = builderAtEnd(block, loc);
  auto op = b.create<cir::WrapOptionalOp>(unwrap(loc), unwrap(optionalType),
                                           unwrap(value));
  return wrap(op.getResult());
}

MlirValue cirBuildIsNonNull(MlirBlock block, MlirLocation loc,
                            MlirValue optional) {
  auto b = builderAtEnd(block, loc);
  auto op = b.create<cir::IsNonNullOp>(unwrap(loc), b.getI1Type(),
                                        unwrap(optional));
  return wrap(op.getResult());
}

MlirValue cirBuildOptionalPayload(MlirBlock block, MlirLocation loc,
                                  MlirType payloadType, MlirValue optional) {
  auto b = builderAtEnd(block, loc);
  auto op = b.create<cir::OptionalPayloadOp>(unwrap(loc), unwrap(payloadType),
                                              unwrap(optional));
  return wrap(op.getResult());
}

MlirValue cirBuildArrayToSlice(MlirBlock block, MlirLocation loc,
                               MlirType sliceType, MlirValue base,
                               MlirValue start, MlirValue end,
                               MlirType arrayType) {
  auto b = builderAtEnd(block, loc);
  auto op = b.create<cir::ArrayToSliceOp>(unwrap(loc), unwrap(sliceType),
      unwrap(base), unwrap(start), unwrap(end),
      TypeAttr::get(unwrap(arrayType)));
  return wrap(op.getResult());
}

//===----------------------------------------------------------------------===//
// Switch
//===----------------------------------------------------------------------===//

void cirBuildSwitch(MlirBlock block, MlirLocation loc,
                    MlirValue value,
                    intptr_t nCases, int64_t *caseValues,
                    MlirBlock *caseDests,
                    MlirBlock defaultDest) {
  auto b = builderAtEnd(block, loc);
  llvm::SmallVector<int64_t> values(caseValues, caseValues + nCases);
  llvm::SmallVector<Block *> dests;
  for (intptr_t i = 0; i < nCases; i++)
    dests.push_back(unwrap(caseDests[i]));
  b.create<cir::SwitchOp>(unwrap(loc), unwrap(value),
      DenseI64ArrayAttr::get(b.getContext(), values),
      unwrap(defaultDest), dests);
}

//===----------------------------------------------------------------------===//
// Enum Type + Operations
//===----------------------------------------------------------------------===//

MlirType cirEnumTypeGet(MlirContext ctx, MlirStringRef name,
                        MlirType tagType,
                        intptr_t nVariants,
                        MlirStringRef *variantNames,
                        int64_t *variantValues) {
  auto mlirCtx = unwrap(ctx);
  llvm::SmallVector<mlir::StringAttr> names;
  llvm::SmallVector<int64_t> values;
  for (intptr_t i = 0; i < nVariants; i++) {
    names.push_back(mlir::StringAttr::get(mlirCtx,
        llvm::StringRef(variantNames[i].data, variantNames[i].length)));
    values.push_back(variantValues[i]);
  }
  return wrap(cir::EnumType::get(mlirCtx,
      llvm::StringRef(name.data, name.length),
      unwrap(tagType), names, values));
}

bool cirTypeIsEnum(MlirType type) {
  return llvm::isa<cir::EnumType>(unwrap(type));
}

MlirType cirEnumTypeGetTagType(MlirType enumType) {
  return wrap(llvm::cast<cir::EnumType>(unwrap(enumType)).getTagType());
}

int64_t cirEnumTypeGetVariantValue(MlirType enumType, MlirStringRef name) {
  return llvm::cast<cir::EnumType>(unwrap(enumType))
      .getVariantValue(llvm::StringRef(name.data, name.length));
}

MlirValue cirBuildEnumConstant(MlirBlock block, MlirLocation loc,
                               MlirType enumType, MlirStringRef variant) {
  auto b = builderAtEnd(block, loc);
  auto op = b.create<cir::EnumConstantOp>(unwrap(loc), unwrap(enumType),
      b.getStringAttr(llvm::StringRef(variant.data, variant.length)));
  return wrap(op.getResult());
}

MlirValue cirBuildEnumValue(MlirBlock block, MlirLocation loc,
                            MlirType tagType, MlirValue enumVal) {
  auto b = builderAtEnd(block, loc);
  auto op = b.create<cir::EnumValueOp>(unwrap(loc), unwrap(tagType),
                                        unwrap(enumVal));
  return wrap(op.getResult());
}

//===----------------------------------------------------------------------===//
// Error Union Type + Operations
// Reference: Zig E!T — wrap_errunion_payload, wrap_errunion_err, is_err,
//            unwrap_errunion_payload, unwrap_errunion_err
//===----------------------------------------------------------------------===//

MlirType cirErrorUnionTypeGet(MlirContext ctx, MlirType payloadType) {
  return wrap(cir::ErrorUnionType::get(unwrap(ctx), unwrap(payloadType)));
}

bool cirTypeIsErrorUnion(MlirType type) {
  return llvm::isa<cir::ErrorUnionType>(unwrap(type));
}

MlirType cirErrorUnionTypeGetPayload(MlirType euType) {
  return wrap(
      llvm::cast<cir::ErrorUnionType>(unwrap(euType)).getPayloadType());
}

MlirValue cirBuildWrapResult(MlirBlock block, MlirLocation loc,
                             MlirType errorUnionType, MlirValue value) {
  auto b = builderAtEnd(block, loc);
  auto op = b.create<cir::WrapResultOp>(unwrap(loc), unwrap(errorUnionType),
                                         unwrap(value));
  return wrap(op.getResult());
}

MlirValue cirBuildWrapError(MlirBlock block, MlirLocation loc,
                            MlirType errorUnionType, MlirValue errorCode) {
  auto b = builderAtEnd(block, loc);
  auto op = b.create<cir::WrapErrorOp>(unwrap(loc), unwrap(errorUnionType),
                                        unwrap(errorCode));
  return wrap(op.getResult());
}

MlirValue cirBuildIsError(MlirBlock block, MlirLocation loc,
                          MlirValue errorUnion) {
  auto b = builderAtEnd(block, loc);
  auto op = b.create<cir::IsErrorOp>(unwrap(loc), b.getI1Type(),
                                      unwrap(errorUnion));
  return wrap(op.getResult());
}

MlirValue cirBuildErrorPayload(MlirBlock block, MlirLocation loc,
                               MlirType payloadType, MlirValue errorUnion) {
  auto b = builderAtEnd(block, loc);
  auto op = b.create<cir::ErrorPayloadOp>(unwrap(loc), unwrap(payloadType),
                                           unwrap(errorUnion));
  return wrap(op.getResult());
}

MlirValue cirBuildErrorCode(MlirBlock block, MlirLocation loc,
                            MlirValue errorUnion) {
  auto b = builderAtEnd(block, loc);
  auto i16Type = b.getIntegerType(16);
  auto op = b.create<cir::ErrorCodeOp>(unwrap(loc), i16Type,
                                        unwrap(errorUnion));
  return wrap(op.getResult());
}

//===----------------------------------------------------------------------===//
// Exception-Based Error Handling
// Reference: LLVM InvokeOp/LandingpadOp, C++ ABI
//===----------------------------------------------------------------------===//

void cirBuildThrow(MlirBlock block, MlirLocation loc, MlirValue value) {
  auto b = builderAtEnd(block, loc);
  b.create<cir::ThrowOp>(unwrap(loc), unwrap(value));
}

MlirValue cirBuildInvoke(MlirBlock block, MlirLocation loc,
                         MlirStringRef callee,
                         intptr_t nOperands, MlirValue *operands,
                         MlirType resultType,
                         MlirBlock normalDest, MlirBlock unwindDest) {
  auto b = builderAtEnd(block, loc);
  llvm::SmallVector<Value> opVals;
  for (intptr_t i = 0; i < nOperands; i++)
    opVals.push_back(unwrap(operands[i]));
  auto calleeRef = mlir::FlatSymbolRefAttr::get(
      b.getContext(), llvm::StringRef(callee.data, callee.length));
  llvm::SmallVector<mlir::Type> resultTypes;
  if (unwrap(resultType))
    resultTypes.push_back(unwrap(resultType));
  auto op = b.create<cir::InvokeOp>(unwrap(loc), resultTypes, calleeRef,
      opVals, unwrap(normalDest), unwrap(unwindDest));
  if (op.getResult())
    return wrap(op.getResult());
  return {nullptr};
}

MlirValue cirBuildLandingPad(MlirBlock block, MlirLocation loc,
                             MlirType resultType) {
  auto b = builderAtEnd(block, loc);
  auto op = b.create<cir::LandingPadOp>(unwrap(loc), unwrap(resultType));
  return wrap(op.getResult());
}
