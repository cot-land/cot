package main

// CGo bindings for MLIR C API — port of libzc/mlir.zig
// Reference: ~/claude/references/llvm-project/mlir/include/mlir-c/IR.h

/*
#cgo CFLAGS: -I/opt/homebrew/Cellar/llvm@20/20.1.8/include -I../libcir/include -I../libcir/c-api -I../build/libcir/include
#cgo LDFLAGS: -L../build/libcir -lCIR -L/opt/homebrew/Cellar/llvm@20/20.1.8/lib -lMLIRCAPIIR -lMLIRIR -lMLIRSupport -lMLIRDialect -lMLIRBytecodeWriter -lMLIRBytecodeReader -lMLIRBytecodeOpInterface -lMLIRPass -lMLIRAsmParser -lMLIRParser -lMLIRFuncDialect -lMLIRCastInterfaces -lLLVMSupport -lLLVMDemangle -lc++ -lz -lcurses

#include <stdlib.h>
#include <string.h>
#include "mlir-c/IR.h"
#include "mlir-c/BuiltinTypes.h"
#include "mlir-c/BuiltinAttributes.h"
#include "CIRCApi.h"

// Forward declare bytecode writer functions
MlirLogicalResult mlirOperationWriteBytecodeWithConfig(
    MlirOperation op, MlirBytecodeWriterConfig config,
    MlirStringCallback callback, void *userData);
MlirBytecodeWriterConfig mlirBytecodeWriterConfigCreate();
void mlirBytecodeWriterConfigDestroy(MlirBytecodeWriterConfig config);
void mlirBytecodeWriterConfigDesiredEmitVersion(
    MlirBytecodeWriterConfig config, int64_t version);

// Callback trampoline for bytecode serialization
extern void goMlirStringCallback(MlirStringRef str, void *userData);
*/
import "C"
import "unsafe"

// ============================================================
// Core types
// ============================================================

type MlirContext struct{ ptr C.MlirContext }
type MlirModule struct{ ptr C.MlirModule }
type MlirOperation struct{ ptr C.MlirOperation }
type MlirBlock struct{ ptr C.MlirBlock }
type MlirRegion struct{ ptr C.MlirRegion }
type MlirValue struct{ ptr C.MlirValue }
type MlirType struct{ ptr C.MlirType }
type MlirAttribute struct{ ptr C.MlirAttribute }
type MlirLocation struct{ ptr C.MlirLocation }
type MlirNamedAttr = C.MlirNamedAttribute

// BlockGetArgument returns the i-th argument of a block.
func BlockGetArgument(block MlirBlock, i int) MlirValue {
	return MlirValue{C.mlirBlockGetArgument(block.ptr, C.intptr_t(i))}
}

// TypeEqual checks if two MLIR types are identical.
func TypeEqual(a, b MlirType) bool {
	return bool(C.mlirTypeEqual(a.ptr, b.ptr))
}

// ValueGetType returns the MLIR type of a value.
func ValueGetType(v MlirValue) MlirType {
	return MlirType{ptr: C.mlirValueGetType(v.ptr)}
}

// ============================================================
// Context and Module
// ============================================================

func createContext() MlirContext {
	ctx := C.mlirContextCreate()
	C.cirRegisterDialect(ctx)
	C.mlirContextSetAllowUnregisteredDialects(ctx, true)
	return MlirContext{ctx}
}

func createModule(ctx MlirContext) MlirModule {
	loc := C.mlirLocationUnknownGet(ctx.ptr)
	return MlirModule{C.mlirModuleCreateEmpty(loc)}
}

func destroyModule(m MlirModule)  { C.mlirModuleDestroy(m.ptr) }
func destroyContext(ctx MlirContext) { C.mlirContextDestroy(ctx.ptr) }

func moduleGetBody(m MlirModule) MlirBlock {
	return MlirBlock{C.mlirModuleGetBody(m.ptr)}
}

func moduleGetOperation(m MlirModule) MlirOperation {
	return MlirOperation{C.mlirModuleGetOperation(m.ptr)}
}

// ============================================================
// Builder — mirrors libzc/mlir.zig Builder
// ============================================================

type Builder struct {
	ctx MlirContext
	loc MlirLocation
}

func newBuilder(ctx MlirContext) Builder {
	return Builder{
		ctx: ctx,
		loc: MlirLocation{C.mlirLocationUnknownGet(ctx.ptr)},
	}
}

// IntType creates an MLIR integer type with the given bit width.
func (b *Builder) IntType(bits int) MlirType {
	return MlirType{C.mlirIntegerTypeGet(b.ctx.ptr, C.uint(bits))}
}

// F32Type creates an MLIR f32 type.
func (b *Builder) F32Type() MlirType {
	return MlirType{C.mlirF32TypeGet(b.ctx.ptr)}
}

// F64Type creates an MLIR f64 type.
func (b *Builder) F64Type() MlirType {
	return MlirType{C.mlirF64TypeGet(b.ctx.ptr)}
}

// ParseType parses a type from a string like "!cir.ptr" or "!cir.struct<...>".
func (b *Builder) ParseType(s string) MlirType {
	cs := C.CString(s)
	defer C.free(unsafe.Pointer(cs))
	ref := C.mlirStringRefCreateFromCString(cs)
	return MlirType{C.mlirTypeParseGet(b.ctx.ptr, ref)}
}

// FuncType creates a function type.
func (b *Builder) FuncType(inputs []MlirType, results []MlirType) MlirType {
	var inPtr *C.MlirType
	var resPtr *C.MlirType
	if len(inputs) > 0 {
		inPtr = (*C.MlirType)(unsafe.Pointer(&inputs[0]))
	}
	if len(results) > 0 {
		resPtr = (*C.MlirType)(unsafe.Pointer(&results[0]))
	}
	return MlirType{C.mlirFunctionTypeGet(b.ctx.ptr,
		C.intptr_t(len(inputs)), inPtr,
		C.intptr_t(len(results)), resPtr)}
}

// IntAttr creates an integer attribute.
func (b *Builder) IntAttr(ty MlirType, value int64) MlirAttribute {
	return MlirAttribute{C.mlirIntegerAttrGet(ty.ptr, C.int64_t(value))}
}

// TypeAttr creates a type attribute.
func (b *Builder) TypeAttr(ty MlirType) MlirAttribute {
	return MlirAttribute{C.mlirTypeAttrGet(ty.ptr)}
}

// StrAttr creates a string attribute.
func (b *Builder) StrAttr(s string) MlirAttribute {
	cs := C.CString(s)
	defer C.free(unsafe.Pointer(cs))
	ref := C.mlirStringRefCreateFromCString(cs)
	return MlirAttribute{C.mlirStringAttrGet(b.ctx.ptr, ref)}
}

// FlatSymbolRefAttr creates a flat symbol reference attribute.
func (b *Builder) FlatSymbolRefAttr(name string) MlirAttribute {
	cs := C.CString(name)
	defer C.free(unsafe.Pointer(cs))
	ref := C.mlirStringRefCreateFromCString(cs)
	return MlirAttribute{C.mlirFlatSymbolRefAttrGet(b.ctx.ptr, ref)}
}

// NamedAttr creates a named attribute.
func (b *Builder) NamedAttr(name string, attr MlirAttribute) MlirNamedAttr {
	cs := C.CString(name)
	defer C.free(unsafe.Pointer(cs))
	ref := C.mlirStringRefCreateFromCString(cs)
	id := C.mlirIdentifierGet(b.ctx.ptr, ref)
	return C.mlirNamedAttributeGet(id, attr.ptr)
}

// Emit creates an MLIR operation and appends it to the given block.
// Returns the first result value (or zero MlirValue if no results).
func (b *Builder) Emit(block MlirBlock, name string, resultTypes []MlirType, operands []MlirValue, attrs []MlirNamedAttr) MlirValue {
	cs := C.CString(name)
	defer C.free(unsafe.Pointer(cs))
	ref := C.mlirStringRefCreateFromCString(cs)
	state := C.mlirOperationStateGet(ref, b.loc.ptr)

	if len(resultTypes) > 0 {
		C.mlirOperationStateAddResults(&state, C.intptr_t(len(resultTypes)),
			(*C.MlirType)(unsafe.Pointer(&resultTypes[0])))
	}
	if len(operands) > 0 {
		C.mlirOperationStateAddOperands(&state, C.intptr_t(len(operands)),
			(*C.MlirValue)(unsafe.Pointer(&operands[0])))
	}
	if len(attrs) > 0 {
		C.mlirOperationStateAddAttributes(&state, C.intptr_t(len(attrs)),
			&attrs[0])
	}

	op := C.mlirOperationCreate(&state)
	C.mlirBlockAppendOwnedOperation(block.ptr, op)

	if len(resultTypes) > 0 {
		return MlirValue{C.mlirOperationGetResult(op, 0)}
	}
	return MlirValue{}
}

// EmitBranch creates a terminator operation with successor blocks.
func (b *Builder) EmitBranch(block MlirBlock, name string, operands []MlirValue, successors []MlirBlock) {
	cs := C.CString(name)
	defer C.free(unsafe.Pointer(cs))
	ref := C.mlirStringRefCreateFromCString(cs)
	state := C.mlirOperationStateGet(ref, b.loc.ptr)

	if len(operands) > 0 {
		C.mlirOperationStateAddOperands(&state, C.intptr_t(len(operands)),
			(*C.MlirValue)(unsafe.Pointer(&operands[0])))
	}
	if len(successors) > 0 {
		C.mlirOperationStateAddSuccessors(&state, C.intptr_t(len(successors)),
			(*C.MlirBlock)(unsafe.Pointer(&successors[0])))
	}

	op := C.mlirOperationCreate(&state)
	C.mlirBlockAppendOwnedOperation(block.ptr, op)
}

// CreateBlock creates a new basic block (no arguments).
func (b *Builder) CreateBlock() MlirBlock {
	return MlirBlock{C.mlirBlockCreate(0, nil, nil)}
}

// CreateFunc creates a func.func operation with an entry block.
// Returns the func operation and the entry block.
func (b *Builder) CreateFunc(module MlirModule, name string, paramTypes []MlirType, resultTypes []MlirType) (MlirOperation, MlirBlock) {
	funcTy := b.FuncType(paramTypes, resultTypes)

	// Create entry block with parameter types as arguments
	var argTypes *C.MlirType
	locs := make([]C.MlirLocation, len(paramTypes))
	for i := range locs {
		locs[i] = b.loc.ptr
	}
	if len(paramTypes) > 0 {
		argTypes = (*C.MlirType)(unsafe.Pointer(&paramTypes[0]))
	}
	var locsPtr *C.MlirLocation
	if len(locs) > 0 {
		locsPtr = &locs[0]
	}
	entryBlock := C.mlirBlockCreate(C.intptr_t(len(paramTypes)), argTypes, locsPtr)

	// Create region and add entry block
	region := C.mlirRegionCreate()
	C.mlirRegionAppendOwnedBlock(region, entryBlock)

	// Build func.func operation
	cname := C.CString("func.func")
	defer C.free(unsafe.Pointer(cname))
	nameRef := C.mlirStringRefCreateFromCString(cname)
	state := C.mlirOperationStateGet(nameRef, b.loc.ptr)

	C.mlirOperationStateAddOwnedRegions(&state, 1, &region)

	// Attributes: sym_name and function_type
	attrs := []MlirNamedAttr{
		b.NamedAttr("sym_name", b.StrAttr(name)),
		b.NamedAttr("function_type", MlirAttribute{C.mlirTypeAttrGet(funcTy.ptr)}),
	}
	C.mlirOperationStateAddAttributes(&state, C.intptr_t(len(attrs)), &attrs[0])

	funcOp := C.mlirOperationCreate(&state)

	// Append to module body
	moduleBody := C.mlirModuleGetBody(module.ptr)
	C.mlirBlockAppendOwnedOperation(moduleBody, funcOp)

	return MlirOperation{funcOp}, MlirBlock{entryBlock}
}

// AddBlock adds a new block to a function's region.
func (b *Builder) AddBlock(funcOp MlirOperation) MlirBlock {
	block := C.mlirBlockCreate(0, nil, nil)
	region := C.mlirOperationGetRegion(funcOp.ptr, 0)
	C.mlirRegionAppendOwnedBlock(region, block)
	return MlirBlock{block}
}

// ============================================================
// CIR C API wrappers
// ============================================================

// --- Constants ---

func CirBuildConstantInt(block MlirBlock, loc MlirLocation, ty MlirType, value int64) MlirValue {
	return MlirValue{ptr: C.cirBuildConstantInt(block.ptr, loc.ptr, ty.ptr, C.int64_t(value))}
}

func CirBuildConstantFloat(block MlirBlock, loc MlirLocation, ty MlirType, value float64) MlirValue {
	return MlirValue{ptr: C.cirBuildConstantFloat(block.ptr, loc.ptr, ty.ptr, C.double(value))}
}

func CirBuildConstantBool(block MlirBlock, loc MlirLocation, value bool) MlirValue {
	return MlirValue{ptr: C.cirBuildConstantBool(block.ptr, loc.ptr, C.bool(value))}
}

func CirBuildStringConstant(block MlirBlock, loc MlirLocation, s string) MlirValue {
	cs := C.CString(s)
	defer C.free(unsafe.Pointer(cs))
	ref := C.MlirStringRef{data: cs, length: C.size_t(len(s))}
	return MlirValue{ptr: C.cirBuildStringConstant(block.ptr, loc.ptr, ref)}
}

// --- Arithmetic ---

func CirBuildAdd(block MlirBlock, loc MlirLocation, ty MlirType, lhs MlirValue, rhs MlirValue) MlirValue {
	return MlirValue{ptr: C.cirBuildAdd(block.ptr, loc.ptr, ty.ptr, lhs.ptr, rhs.ptr)}
}

func CirBuildSub(block MlirBlock, loc MlirLocation, ty MlirType, lhs MlirValue, rhs MlirValue) MlirValue {
	return MlirValue{ptr: C.cirBuildSub(block.ptr, loc.ptr, ty.ptr, lhs.ptr, rhs.ptr)}
}

func CirBuildMul(block MlirBlock, loc MlirLocation, ty MlirType, lhs MlirValue, rhs MlirValue) MlirValue {
	return MlirValue{ptr: C.cirBuildMul(block.ptr, loc.ptr, ty.ptr, lhs.ptr, rhs.ptr)}
}

func CirBuildDiv(block MlirBlock, loc MlirLocation, ty MlirType, lhs MlirValue, rhs MlirValue) MlirValue {
	return MlirValue{ptr: C.cirBuildDiv(block.ptr, loc.ptr, ty.ptr, lhs.ptr, rhs.ptr)}
}

func CirBuildRem(block MlirBlock, loc MlirLocation, ty MlirType, lhs MlirValue, rhs MlirValue) MlirValue {
	return MlirValue{ptr: C.cirBuildRem(block.ptr, loc.ptr, ty.ptr, lhs.ptr, rhs.ptr)}
}

func CirBuildNeg(block MlirBlock, loc MlirLocation, ty MlirType, operand MlirValue) MlirValue {
	return MlirValue{ptr: C.cirBuildNeg(block.ptr, loc.ptr, ty.ptr, operand.ptr)}
}

// --- Bitwise ---

func CirBuildBitAnd(block MlirBlock, loc MlirLocation, ty MlirType, lhs MlirValue, rhs MlirValue) MlirValue {
	return MlirValue{ptr: C.cirBuildBitAnd(block.ptr, loc.ptr, ty.ptr, lhs.ptr, rhs.ptr)}
}

func CirBuildBitOr(block MlirBlock, loc MlirLocation, ty MlirType, lhs MlirValue, rhs MlirValue) MlirValue {
	return MlirValue{ptr: C.cirBuildBitOr(block.ptr, loc.ptr, ty.ptr, lhs.ptr, rhs.ptr)}
}

func CirBuildBitXor(block MlirBlock, loc MlirLocation, ty MlirType, lhs MlirValue, rhs MlirValue) MlirValue {
	return MlirValue{ptr: C.cirBuildBitXor(block.ptr, loc.ptr, ty.ptr, lhs.ptr, rhs.ptr)}
}

func CirBuildBitNot(block MlirBlock, loc MlirLocation, ty MlirType, operand MlirValue) MlirValue {
	return MlirValue{ptr: C.cirBuildBitNot(block.ptr, loc.ptr, ty.ptr, operand.ptr)}
}

func CirBuildShl(block MlirBlock, loc MlirLocation, ty MlirType, lhs MlirValue, rhs MlirValue) MlirValue {
	return MlirValue{ptr: C.cirBuildShl(block.ptr, loc.ptr, ty.ptr, lhs.ptr, rhs.ptr)}
}

func CirBuildShr(block MlirBlock, loc MlirLocation, ty MlirType, lhs MlirValue, rhs MlirValue) MlirValue {
	return MlirValue{ptr: C.cirBuildShr(block.ptr, loc.ptr, ty.ptr, lhs.ptr, rhs.ptr)}
}

// --- Comparison ---

func CirBuildCmp(block MlirBlock, loc MlirLocation, predicate int, lhs MlirValue, rhs MlirValue) MlirValue {
	return MlirValue{ptr: C.cirBuildCmp(block.ptr, loc.ptr, C.enum_CirCmpPredicate(predicate), lhs.ptr, rhs.ptr)}
}

func CirBuildSelect(block MlirBlock, loc MlirLocation, ty MlirType, cond MlirValue, trueVal MlirValue, falseVal MlirValue) MlirValue {
	return MlirValue{ptr: C.cirBuildSelect(block.ptr, loc.ptr, ty.ptr, cond.ptr, trueVal.ptr, falseVal.ptr)}
}

// --- Type Casts ---

func CirBuildExtSI(block MlirBlock, loc MlirLocation, dstType MlirType, input MlirValue) MlirValue {
	return MlirValue{ptr: C.cirBuildExtSI(block.ptr, loc.ptr, dstType.ptr, input.ptr)}
}

func CirBuildExtUI(block MlirBlock, loc MlirLocation, dstType MlirType, input MlirValue) MlirValue {
	return MlirValue{ptr: C.cirBuildExtUI(block.ptr, loc.ptr, dstType.ptr, input.ptr)}
}

func CirBuildTruncI(block MlirBlock, loc MlirLocation, dstType MlirType, input MlirValue) MlirValue {
	return MlirValue{ptr: C.cirBuildTruncI(block.ptr, loc.ptr, dstType.ptr, input.ptr)}
}

func CirBuildSIToFP(block MlirBlock, loc MlirLocation, dstType MlirType, input MlirValue) MlirValue {
	return MlirValue{ptr: C.cirBuildSIToFP(block.ptr, loc.ptr, dstType.ptr, input.ptr)}
}

func CirBuildFPToSI(block MlirBlock, loc MlirLocation, dstType MlirType, input MlirValue) MlirValue {
	return MlirValue{ptr: C.cirBuildFPToSI(block.ptr, loc.ptr, dstType.ptr, input.ptr)}
}

func CirBuildExtF(block MlirBlock, loc MlirLocation, dstType MlirType, input MlirValue) MlirValue {
	return MlirValue{ptr: C.cirBuildExtF(block.ptr, loc.ptr, dstType.ptr, input.ptr)}
}

func CirBuildTruncF(block MlirBlock, loc MlirLocation, dstType MlirType, input MlirValue) MlirValue {
	return MlirValue{ptr: C.cirBuildTruncF(block.ptr, loc.ptr, dstType.ptr, input.ptr)}
}

// --- Memory ---

func CirBuildAlloca(block MlirBlock, loc MlirLocation, elemType MlirType) MlirValue {
	return MlirValue{ptr: C.cirBuildAlloca(block.ptr, loc.ptr, elemType.ptr)}
}

func CirBuildStore(block MlirBlock, loc MlirLocation, value MlirValue, addr MlirValue) {
	C.cirBuildStore(block.ptr, loc.ptr, value.ptr, addr.ptr)
}

func CirBuildLoad(block MlirBlock, loc MlirLocation, resultType MlirType, addr MlirValue) MlirValue {
	return MlirValue{ptr: C.cirBuildLoad(block.ptr, loc.ptr, resultType.ptr, addr.ptr)}
}

// --- References ---

func CirBuildAddrOf(block MlirBlock, loc MlirLocation, refType MlirType, addr MlirValue) MlirValue {
	return MlirValue{ptr: C.cirBuildAddrOf(block.ptr, loc.ptr, refType.ptr, addr.ptr)}
}

func CirBuildDeref(block MlirBlock, loc MlirLocation, resultType MlirType, ref MlirValue) MlirValue {
	return MlirValue{ptr: C.cirBuildDeref(block.ptr, loc.ptr, resultType.ptr, ref.ptr)}
}

// --- Aggregates: Structs ---

func CirBuildStructInit(block MlirBlock, loc MlirLocation, ty MlirType, fields []MlirValue) MlirValue {
	if len(fields) == 0 {
		return MlirValue{ptr: C.cirBuildStructInit(block.ptr, loc.ptr, ty.ptr, 0, nil)}
	}
	return MlirValue{ptr: C.cirBuildStructInit(block.ptr, loc.ptr, ty.ptr, C.intptr_t(len(fields)), (*C.MlirValue)(unsafe.Pointer(&fields[0])))}
}

func CirBuildFieldVal(block MlirBlock, loc MlirLocation, resultType MlirType, input MlirValue, fieldIndex int64) MlirValue {
	return MlirValue{ptr: C.cirBuildFieldVal(block.ptr, loc.ptr, resultType.ptr, input.ptr, C.int64_t(fieldIndex))}
}

func CirBuildFieldPtr(block MlirBlock, loc MlirLocation, base MlirValue, fieldIndex int64, elemType MlirType) MlirValue {
	return MlirValue{ptr: C.cirBuildFieldPtr(block.ptr, loc.ptr, base.ptr, C.int64_t(fieldIndex), elemType.ptr)}
}

// --- Aggregates: Arrays ---

func CirBuildArrayInit(block MlirBlock, loc MlirLocation, ty MlirType, elems []MlirValue) MlirValue {
	if len(elems) == 0 {
		return MlirValue{ptr: C.cirBuildArrayInit(block.ptr, loc.ptr, ty.ptr, 0, nil)}
	}
	return MlirValue{ptr: C.cirBuildArrayInit(block.ptr, loc.ptr, ty.ptr, C.intptr_t(len(elems)), (*C.MlirValue)(unsafe.Pointer(&elems[0])))}
}

func CirBuildElemVal(block MlirBlock, loc MlirLocation, resultType MlirType, input MlirValue, index int64) MlirValue {
	return MlirValue{ptr: C.cirBuildElemVal(block.ptr, loc.ptr, resultType.ptr, input.ptr, C.int64_t(index))}
}

func CirBuildElemPtr(block MlirBlock, loc MlirLocation, base MlirValue, index MlirValue, elemType MlirType) MlirValue {
	return MlirValue{ptr: C.cirBuildElemPtr(block.ptr, loc.ptr, base.ptr, index.ptr, elemType.ptr)}
}

// --- Control Flow ---

func CirBuildBr(block MlirBlock, loc MlirLocation, dest MlirBlock, args []MlirValue) {
	if len(args) == 0 {
		C.cirBuildBr(block.ptr, loc.ptr, dest.ptr, 0, nil)
	} else {
		C.cirBuildBr(block.ptr, loc.ptr, dest.ptr, C.intptr_t(len(args)), (*C.MlirValue)(unsafe.Pointer(&args[0])))
	}
}

func CirBuildCondBr(block MlirBlock, loc MlirLocation, cond MlirValue, trueDest MlirBlock, falseDest MlirBlock) {
	C.cirBuildCondBr(block.ptr, loc.ptr, cond.ptr, trueDest.ptr, falseDest.ptr)
}

func CirBuildTrap(block MlirBlock, loc MlirLocation) {
	C.cirBuildTrap(block.ptr, loc.ptr)
}

// --- Type Constructors ---

func CirPointerTypeGet(ctx MlirContext) MlirType {
	return MlirType{ptr: C.cirPointerTypeGet(ctx.ptr)}
}

func CirRefTypeGet(ctx MlirContext, pointeeType MlirType) MlirType {
	return MlirType{ptr: C.cirRefTypeGet(ctx.ptr, pointeeType.ptr)}
}

func CirSliceTypeGet(ctx MlirContext, elementType MlirType) MlirType {
	return MlirType{ptr: C.cirSliceTypeGet(ctx.ptr, elementType.ptr)}
}

func CirArrayTypeGet(ctx MlirContext, size int64, elementType MlirType) MlirType {
	return MlirType{ptr: C.cirArrayTypeGet(ctx.ptr, C.int64_t(size), elementType.ptr)}
}

func CirStructTypeGet(ctx MlirContext, name string, fieldNames []string, fieldTypes []MlirType) MlirType {
	cname := C.CString(name)
	defer C.free(unsafe.Pointer(cname))
	nameRef := C.MlirStringRef{data: cname, length: C.size_t(len(name))}

	nFields := len(fieldNames)
	cFieldNames := make([]C.MlirStringRef, nFields)
	cFieldNamePtrs := make([]*C.char, nFields)
	for i, fn := range fieldNames {
		cFieldNamePtrs[i] = C.CString(fn)
		cFieldNames[i] = C.MlirStringRef{data: cFieldNamePtrs[i], length: C.size_t(len(fn))}
	}
	defer func() {
		for _, p := range cFieldNamePtrs {
			C.free(unsafe.Pointer(p))
		}
	}()

	var fnPtr *C.MlirStringRef
	var ftPtr *C.MlirType
	if nFields > 0 {
		fnPtr = &cFieldNames[0]
		ftPtr = (*C.MlirType)(unsafe.Pointer(&fieldTypes[0]))
	}
	return MlirType{ptr: C.cirStructTypeGet(ctx.ptr, nameRef, C.intptr_t(nFields), fnPtr, ftPtr)}
}

// --- Slice Operations ---

func CirBuildSlicePtr(block MlirBlock, loc MlirLocation, slice MlirValue) MlirValue {
	return MlirValue{ptr: C.cirBuildSlicePtr(block.ptr, loc.ptr, slice.ptr)}
}

func CirBuildSliceLen(block MlirBlock, loc MlirLocation, slice MlirValue) MlirValue {
	return MlirValue{ptr: C.cirBuildSliceLen(block.ptr, loc.ptr, slice.ptr)}
}

func CirBuildSliceElem(block MlirBlock, loc MlirLocation, elemType MlirType, slice MlirValue, index MlirValue) MlirValue {
	return MlirValue{ptr: C.cirBuildSliceElem(block.ptr, loc.ptr, elemType.ptr, slice.ptr, index.ptr)}
}

func CirTypeIsSlice(ty MlirType) bool {
	return bool(C.cirTypeIsSlice(ty.ptr))
}

// --- Type Queries ---

func CirTypeIsStruct(ty MlirType) bool {
	return bool(C.cirTypeIsStruct(ty.ptr))
}

func CirStructTypeGetFieldIndex(structType MlirType, name string) int {
	cs := C.CString(name)
	defer C.free(unsafe.Pointer(cs))
	ref := C.MlirStringRef{data: cs, length: C.size_t(len(name))}
	return int(C.cirStructTypeGetFieldIndex(structType.ptr, ref))
}

func CirStructTypeGetNumFields(structType MlirType) int {
	return int(C.cirStructTypeGetNumFields(structType.ptr))
}

// ============================================================
// Bytecode serialization
// ============================================================

// bytecodeBuffer is used by the callback to accumulate bytecode.
var bytecodeBuffer []byte

//export goMlirStringCallback
func goMlirStringCallback(str C.MlirStringRef, userData unsafe.Pointer) {
	data := C.GoBytes(unsafe.Pointer(str.data), C.int(str.length))
	bytecodeBuffer = append(bytecodeBuffer, data...)
}

// SerializeToBytecode serializes an MLIR module to bytecode bytes.
func SerializeToBytecode(module MlirModule) ([]byte, error) {
	bytecodeBuffer = nil
	op := C.mlirModuleGetOperation(module.ptr)
	config := C.mlirBytecodeWriterConfigCreate()
	C.mlirBytecodeWriterConfigDesiredEmitVersion(config, 1)
	C.mlirOperationWriteBytecodeWithConfig(op, config,
		(C.MlirStringCallback)(C.goMlirStringCallback), nil)
	C.mlirBytecodeWriterConfigDestroy(config)
	result := make([]byte, len(bytecodeBuffer))
	copy(result, bytecodeBuffer)
	bytecodeBuffer = nil
	return result, nil
}
