//===- CIRCApi.h - CIR dialect C API ----------------------------*- C -*-===//
//
// C API for the CIR MLIR dialect.
// Frontends in any language (Zig, Go, Rust, Python) use this to produce CIR.
// Every CIR type and op has a corresponding C function — no raw
// mlirOperationCreate boilerplate needed.
//
// Reference: mlir-c/IR.h pattern — opaque types, plain C, no exceptions.
//
//===------------------------------------------------------------------===//

#ifndef CIR_C_API_H
#define CIR_C_API_H

#include "mlir-c/IR.h"
#include "mlir-c/Support.h"

#ifdef __cplusplus
extern "C" {
#endif

//===----------------------------------------------------------------------===//
// Dialect Registration
//===----------------------------------------------------------------------===//

/// Register the CIR dialect with an MLIR context.
void cirRegisterDialect(MlirContext ctx);

//===----------------------------------------------------------------------===//
// Type Constructors
//===----------------------------------------------------------------------===//

/// Get !cir.ptr type (opaque pointer).
MlirType cirPointerTypeGet(MlirContext ctx);

/// Get !cir.ref<T> type (typed safe reference).
MlirType cirRefTypeGet(MlirContext ctx, MlirType pointeeType);

/// Get !cir.struct<"name", fields...> type.
MlirType cirStructTypeGet(MlirContext ctx, MlirStringRef name,
                          intptr_t nFields,
                          MlirStringRef *fieldNames,
                          MlirType *fieldTypes);

/// Get !cir.array<N x T> type.
MlirType cirArrayTypeGet(MlirContext ctx, int64_t size,
                         MlirType elementType);

/// Get !cir.slice<T> type (fat pointer {ptr, len}).
MlirType cirSliceTypeGet(MlirContext ctx, MlirType elementType);

//===----------------------------------------------------------------------===//
// Type Queries
//===----------------------------------------------------------------------===//

/// Check if a type is !cir.ptr.
bool cirTypeIsPointer(MlirType type);

/// Check if a type is !cir.ref<T>.
bool cirTypeIsRef(MlirType type);

/// Get pointee type from !cir.ref<T>. Undefined if not a ref type.
MlirType cirRefTypeGetPointee(MlirType refType);

/// Check if a type is !cir.struct.
bool cirTypeIsStruct(MlirType type);

/// Get struct field count.
intptr_t cirStructTypeGetNumFields(MlirType structType);

/// Get struct field index by name. Returns -1 if not found.
int cirStructTypeGetFieldIndex(MlirType structType, MlirStringRef name);

/// Check if a type is !cir.array.
bool cirTypeIsArray(MlirType type);

/// Get array size.
int64_t cirArrayTypeGetSize(MlirType arrayType);

/// Get array element type.
MlirType cirArrayTypeGetElementType(MlirType arrayType);

/// Check if a type is !cir.slice<T>.
bool cirTypeIsSlice(MlirType type);

/// Get element type from !cir.slice<T>.
MlirType cirSliceTypeGetElementType(MlirType sliceType);

//===----------------------------------------------------------------------===//
// Constants
//===----------------------------------------------------------------------===//

/// Create cir.constant with integer value.
MlirValue cirBuildConstantInt(MlirBlock block, MlirLocation loc,
                              MlirType type, int64_t value);

/// Create cir.constant with float value.
MlirValue cirBuildConstantFloat(MlirBlock block, MlirLocation loc,
                                MlirType type, double value);

/// Create cir.constant with bool value (i1).
MlirValue cirBuildConstantBool(MlirBlock block, MlirLocation loc,
                               bool value);

/// Create cir.string_constant "value" : !cir.slice<i8>.
MlirValue cirBuildStringConstant(MlirBlock block, MlirLocation loc,
                                 MlirStringRef value);

//===----------------------------------------------------------------------===//
// Arithmetic
//===----------------------------------------------------------------------===//

MlirValue cirBuildAdd(MlirBlock block, MlirLocation loc,
                      MlirType type, MlirValue lhs, MlirValue rhs);
MlirValue cirBuildSub(MlirBlock block, MlirLocation loc,
                      MlirType type, MlirValue lhs, MlirValue rhs);
MlirValue cirBuildMul(MlirBlock block, MlirLocation loc,
                      MlirType type, MlirValue lhs, MlirValue rhs);
MlirValue cirBuildDiv(MlirBlock block, MlirLocation loc,
                      MlirType type, MlirValue lhs, MlirValue rhs);
MlirValue cirBuildRem(MlirBlock block, MlirLocation loc,
                      MlirType type, MlirValue lhs, MlirValue rhs);
MlirValue cirBuildNeg(MlirBlock block, MlirLocation loc,
                      MlirType type, MlirValue operand);

//===----------------------------------------------------------------------===//
// Bitwise
//===----------------------------------------------------------------------===//

MlirValue cirBuildBitAnd(MlirBlock block, MlirLocation loc,
                         MlirType type, MlirValue lhs, MlirValue rhs);
MlirValue cirBuildBitOr(MlirBlock block, MlirLocation loc,
                        MlirType type, MlirValue lhs, MlirValue rhs);
MlirValue cirBuildBitXor(MlirBlock block, MlirLocation loc,
                         MlirType type, MlirValue lhs, MlirValue rhs);
MlirValue cirBuildBitNot(MlirBlock block, MlirLocation loc,
                         MlirType type, MlirValue operand);
MlirValue cirBuildShl(MlirBlock block, MlirLocation loc,
                      MlirType type, MlirValue lhs, MlirValue rhs);
MlirValue cirBuildShr(MlirBlock block, MlirLocation loc,
                      MlirType type, MlirValue lhs, MlirValue rhs);

//===----------------------------------------------------------------------===//
// Comparison
//===----------------------------------------------------------------------===//

/// CIR comparison predicates (matches CIR_CmpIPredicate enum values).
enum CirCmpPredicate {
  CIR_CMP_EQ  = 0,
  CIR_CMP_NE  = 1,
  CIR_CMP_SLT = 2,
  CIR_CMP_SLE = 3,
  CIR_CMP_SGT = 4,
  CIR_CMP_SGE = 5,
};

/// Create cir.cmp with predicate. Returns i1.
MlirValue cirBuildCmp(MlirBlock block, MlirLocation loc,
                      enum CirCmpPredicate predicate,
                      MlirValue lhs, MlirValue rhs);

/// Create cir.select (ternary: condition ? trueVal : falseVal).
MlirValue cirBuildSelect(MlirBlock block, MlirLocation loc,
                         MlirType resultType, MlirValue condition,
                         MlirValue trueVal, MlirValue falseVal);

//===----------------------------------------------------------------------===//
// Type Casts
//===----------------------------------------------------------------------===//

MlirValue cirBuildExtSI(MlirBlock block, MlirLocation loc,
                        MlirType dstType, MlirValue input);
MlirValue cirBuildExtUI(MlirBlock block, MlirLocation loc,
                        MlirType dstType, MlirValue input);
MlirValue cirBuildTruncI(MlirBlock block, MlirLocation loc,
                         MlirType dstType, MlirValue input);
MlirValue cirBuildSIToFP(MlirBlock block, MlirLocation loc,
                         MlirType dstType, MlirValue input);
MlirValue cirBuildFPToSI(MlirBlock block, MlirLocation loc,
                         MlirType dstType, MlirValue input);
MlirValue cirBuildExtF(MlirBlock block, MlirLocation loc,
                       MlirType dstType, MlirValue input);
MlirValue cirBuildTruncF(MlirBlock block, MlirLocation loc,
                         MlirType dstType, MlirValue input);

//===----------------------------------------------------------------------===//
// Memory
//===----------------------------------------------------------------------===//

/// Create cir.alloca for stack allocation. Returns !cir.ptr.
MlirValue cirBuildAlloca(MlirBlock block, MlirLocation loc,
                         MlirType elemType);

/// Create cir.store (value → addr).
void cirBuildStore(MlirBlock block, MlirLocation loc,
                   MlirValue value, MlirValue addr);

/// Create cir.load (addr → value).
MlirValue cirBuildLoad(MlirBlock block, MlirLocation loc,
                       MlirType resultType, MlirValue addr);

//===----------------------------------------------------------------------===//
// References (address-of / dereference)
//===----------------------------------------------------------------------===//

/// Create cir.addr_of (&x). Takes !cir.ptr, returns !cir.ref<T>.
MlirValue cirBuildAddrOf(MlirBlock block, MlirLocation loc,
                         MlirType refType, MlirValue addr);

/// Create cir.deref (*p). Takes !cir.ref<T>, returns T.
MlirValue cirBuildDeref(MlirBlock block, MlirLocation loc,
                        MlirType resultType, MlirValue ref);

//===----------------------------------------------------------------------===//
// Aggregates — Structs
//===----------------------------------------------------------------------===//

/// Create cir.struct_init from field values.
MlirValue cirBuildStructInit(MlirBlock block, MlirLocation loc,
                             MlirType structType,
                             intptr_t nFields, MlirValue *fields);

/// Create cir.field_val (extract field from struct value).
MlirValue cirBuildFieldVal(MlirBlock block, MlirLocation loc,
                           MlirType resultType, MlirValue input,
                           int64_t fieldIndex);

/// Create cir.field_ptr (pointer to struct field).
MlirValue cirBuildFieldPtr(MlirBlock block, MlirLocation loc,
                           MlirValue base, int64_t fieldIndex,
                           MlirType elemType);

//===----------------------------------------------------------------------===//
// Aggregates — Arrays
//===----------------------------------------------------------------------===//

/// Create cir.array_init from element values.
MlirValue cirBuildArrayInit(MlirBlock block, MlirLocation loc,
                            MlirType arrayType,
                            intptr_t nElements, MlirValue *elements);

/// Create cir.elem_val (extract element by constant index).
MlirValue cirBuildElemVal(MlirBlock block, MlirLocation loc,
                          MlirType resultType, MlirValue input,
                          int64_t index);

/// Create cir.elem_ptr (pointer to array element by dynamic index).
MlirValue cirBuildElemPtr(MlirBlock block, MlirLocation loc,
                          MlirValue base, MlirValue index,
                          MlirType elemType);

//===----------------------------------------------------------------------===//
// Control Flow
//===----------------------------------------------------------------------===//

/// Create cir.br (unconditional branch).
void cirBuildBr(MlirBlock block, MlirLocation loc,
                MlirBlock dest,
                intptr_t nArgs, MlirValue *args);

/// Create cir.condbr (conditional branch).
void cirBuildCondBr(MlirBlock block, MlirLocation loc,
                    MlirValue condition,
                    MlirBlock trueDest, MlirBlock falseDest);

/// Create cir.trap (abort).
void cirBuildTrap(MlirBlock block, MlirLocation loc);

//===----------------------------------------------------------------------===//
// Slice Operations
//===----------------------------------------------------------------------===//

/// Create cir.slice_ptr (extract pointer from slice). Returns !cir.ptr.
MlirValue cirBuildSlicePtr(MlirBlock block, MlirLocation loc,
                           MlirValue slice);

/// Create cir.slice_len (extract length from slice). Returns i64.
MlirValue cirBuildSliceLen(MlirBlock block, MlirLocation loc,
                           MlirValue slice);

/// Create cir.slice_elem (index into slice, unchecked). Returns element type.
MlirValue cirBuildSliceElem(MlirBlock block, MlirLocation loc,
                            MlirType elemType, MlirValue slice,
                            MlirValue index);

//===----------------------------------------------------------------------===//
// Optional Type + Operations
//===----------------------------------------------------------------------===//

/// Get !cir.optional<T> type.
MlirType cirOptionalTypeGet(MlirContext ctx, MlirType payloadType);

/// Check if a type is !cir.optional<T>.
bool cirTypeIsOptional(MlirType type);

/// Get payload type from !cir.optional<T>.
MlirType cirOptionalTypeGetPayload(MlirType optType);

/// Check if optional uses null-pointer optimization.
bool cirOptionalTypeIsPointerLike(MlirType optType);

/// Create cir.none (null optional).
MlirValue cirBuildNone(MlirBlock block, MlirLocation loc,
                       MlirType optionalType);

/// Create cir.wrap_optional (T → ?T).
MlirValue cirBuildWrapOptional(MlirBlock block, MlirLocation loc,
                               MlirType optionalType, MlirValue value);

/// Create cir.is_non_null (?T → i1).
MlirValue cirBuildIsNonNull(MlirBlock block, MlirLocation loc,
                            MlirValue optional);

/// Create cir.optional_payload (?T → T, unchecked).
MlirValue cirBuildOptionalPayload(MlirBlock block, MlirLocation loc,
                                  MlirType payloadType, MlirValue optional);

/// Create cir.array_to_slice (array pointer + range → slice).
MlirValue cirBuildArrayToSlice(MlirBlock block, MlirLocation loc,
                               MlirType sliceType, MlirValue base,
                               MlirValue start, MlirValue end,
                               MlirType arrayType);

//===----------------------------------------------------------------------===//
// Switch
//===----------------------------------------------------------------------===//

/// Create cir.switch (integer multi-way branch).
void cirBuildSwitch(MlirBlock block, MlirLocation loc,
                    MlirValue value,
                    intptr_t nCases, int64_t *caseValues,
                    MlirBlock *caseDests,
                    MlirBlock defaultDest);

//===----------------------------------------------------------------------===//
// Enum Type + Operations
//===----------------------------------------------------------------------===//

/// Get !cir.enum<"Name", TagType, ...> type.
MlirType cirEnumTypeGet(MlirContext ctx, MlirStringRef name,
                        MlirType tagType,
                        intptr_t nVariants,
                        MlirStringRef *variantNames,
                        int64_t *variantValues);

/// Check if a type is !cir.enum<...>.
bool cirTypeIsEnum(MlirType type);

/// Get tag type from !cir.enum<...>.
MlirType cirEnumTypeGetTagType(MlirType enumType);

/// Get variant value by name. Returns -1 if not found.
int64_t cirEnumTypeGetVariantValue(MlirType enumType, MlirStringRef name);

/// Create cir.enum_constant (construct enum value by variant name).
MlirValue cirBuildEnumConstant(MlirBlock block, MlirLocation loc,
                               MlirType enumType, MlirStringRef variant);

/// Create cir.enum_value (extract integer from enum).
MlirValue cirBuildEnumValue(MlirBlock block, MlirLocation loc,
                            MlirType tagType, MlirValue enumVal);

//===----------------------------------------------------------------------===//
// Error Union Type + Operations
//===----------------------------------------------------------------------===//

/// Get !cir.error_union<T> type.
MlirType cirErrorUnionTypeGet(MlirContext ctx, MlirType payloadType);

/// Check if a type is !cir.error_union<T>.
bool cirTypeIsErrorUnion(MlirType type);

/// Get payload type from !cir.error_union<T>.
MlirType cirErrorUnionTypeGetPayload(MlirType euType);

/// Create cir.wrap_result (T → E!T, success case).
MlirValue cirBuildWrapResult(MlirBlock block, MlirLocation loc,
                             MlirType errorUnionType, MlirValue value);

/// Create cir.wrap_error (i16 → E!T, error case).
MlirValue cirBuildWrapError(MlirBlock block, MlirLocation loc,
                            MlirType errorUnionType, MlirValue errorCode);

/// Create cir.is_error (E!T → i1).
MlirValue cirBuildIsError(MlirBlock block, MlirLocation loc,
                          MlirValue errorUnion);

/// Create cir.error_payload (E!T → T, unchecked).
MlirValue cirBuildErrorPayload(MlirBlock block, MlirLocation loc,
                               MlirType payloadType, MlirValue errorUnion);

/// Create cir.error_code (E!T → i16).
MlirValue cirBuildErrorCode(MlirBlock block, MlirLocation loc,
                            MlirValue errorUnion);

//===----------------------------------------------------------------------===//
// Exception-Based Error Handling
//===----------------------------------------------------------------------===//

/// Create cir.throw (throw exception value).
void cirBuildThrow(MlirBlock block, MlirLocation loc, MlirValue value);

/// Create cir.invoke (call with normal/unwind successors).
/// Returns the call result (or null if void).
MlirValue cirBuildInvoke(MlirBlock block, MlirLocation loc,
                         MlirStringRef callee,
                         intptr_t nOperands, MlirValue *operands,
                         MlirType resultType,
                         MlirBlock normalDest, MlirBlock unwindDest);

/// Create cir.landingpad (catch exception value).
MlirValue cirBuildLandingPad(MlirBlock block, MlirLocation loc,
                             MlirType resultType);

#ifdef __cplusplus
}
#endif

#endif // CIR_C_API_H
