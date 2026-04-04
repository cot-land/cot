package main

// CGo bindings for MLIR C API — port of libzc/mlir.zig
// Reference: ~/claude/references/llvm-project/mlir/include/mlir-c/IR.h

/*
#cgo CFLAGS: -I/opt/homebrew/Cellar/llvm@20/20.1.8/include -I../libcir/include -I../libcir/c-api -I../libcir/build/include
#cgo LDFLAGS: -L../libcir/build -lCIR -L/opt/homebrew/Cellar/llvm@20/20.1.8/lib -lMLIRCAPIIR -lMLIRIR -lMLIRSupport -lMLIRDialect -lMLIRBytecodeWriter -lMLIRBytecodeReader -lMLIRBytecodeOpInterface -lMLIRPass -lMLIRAsmParser -lMLIRParser -lMLIRFuncDialect -lMLIRCastInterfaces -lLLVMSupport -lLLVMDemangle -lc++ -lz -lcurses

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
