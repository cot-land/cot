//! MLIR C API bindings for CIR.
//!
//! Ported from cot-failed/libzc/mlir.zig (489 lines, proven code).
//! Thin Zig wrapper around MLIR C API + CIR dialect registration.

const std = @import("std");

// ============================================================
// MLIR C API types (from mlir-c/IR.h, mlir-c/Support.h)
// ============================================================

pub const StringRef = extern struct {
    data: [*]const u8,
    length: usize,
    pub fn fromSlice(s: []const u8) StringRef {
        return .{ .data = s.ptr, .length = s.len };
    }
    pub fn toSlice(self: StringRef) []const u8 {
        return self.data[0..self.length];
    }
};

pub const LogicalResult = extern struct {
    value: i8,
    pub fn isSuccess(self: LogicalResult) bool { return self.value != 0; }
};

pub const Context = extern struct { ptr: ?*anyopaque };
pub const Module = extern struct { ptr: ?*anyopaque };
pub const Operation = extern struct { ptr: ?*anyopaque };
pub const Block = extern struct { ptr: ?*anyopaque };
pub const Region = extern struct { ptr: ?*anyopaque };
pub const Value = extern struct { ptr: ?*const anyopaque };
pub const Type = extern struct { ptr: ?*const anyopaque };
pub const Attribute = extern struct { ptr: ?*const anyopaque };
pub const Location = extern struct { ptr: ?*const anyopaque };
pub const Identifier = extern struct { ptr: ?*const anyopaque };
pub const NamedAttribute = extern struct { name: Identifier, attribute: Attribute };
pub const OperationState = extern struct {
    name: StringRef, location: Location,
    n_results: isize, results: ?[*]const Type,
    n_operands: isize, operands: ?[*]const Value,
    n_regions: isize, regions: ?[*]const Region,
    n_successors: isize, successors: ?[*]const Block,
    n_attributes: isize, attributes: ?[*]const NamedAttribute,
    enable_result_type_inference: bool,
};
pub const BytecodeWriterConfig = extern struct { ptr: ?*anyopaque };
pub const StringCallback = *const fn (StringRef, ?*anyopaque) callconv(.c) void;

// ============================================================
// MLIR C API functions
// ============================================================

pub extern "c" fn mlirContextCreate() callconv(.c) Context;
pub extern "c" fn mlirContextDestroy(ctx: Context) callconv(.c) void;
pub extern "c" fn mlirContextSetAllowUnregisteredDialects(ctx: Context, allow: bool) callconv(.c) void;
pub extern "c" fn mlirLocationUnknownGet(ctx: Context) callconv(.c) Location;
pub extern "c" fn mlirModuleCreateEmpty(loc: Location) callconv(.c) Module;
pub extern "c" fn mlirModuleGetBody(module: Module) callconv(.c) Block;
pub extern "c" fn mlirModuleGetOperation(module: Module) callconv(.c) Operation;
pub extern "c" fn mlirModuleDestroy(module: Module) callconv(.c) void;
pub extern "c" fn mlirOperationStateGet(name: StringRef, loc: Location) callconv(.c) OperationState;
pub extern "c" fn mlirOperationStateAddResults(state: *OperationState, n: isize, results: [*]const Type) callconv(.c) void;
pub extern "c" fn mlirOperationStateAddOperands(state: *OperationState, n: isize, operands: [*]const Value) callconv(.c) void;
pub extern "c" fn mlirOperationStateAddOwnedRegions(state: *OperationState, n: isize, regions: [*]const Region) callconv(.c) void;
pub extern "c" fn mlirOperationStateAddSuccessors(state: *OperationState, n: isize, successors: [*]const Block) callconv(.c) void;
pub extern "c" fn mlirOperationStateAddAttributes(state: *OperationState, n: isize, attrs: [*]const NamedAttribute) callconv(.c) void;
pub extern "c" fn mlirOperationCreate(state: *OperationState) callconv(.c) Operation;
pub extern "c" fn mlirOperationGetResult(op: Operation, pos: isize) callconv(.c) Value;
pub extern "c" fn mlirOperationVerify(op: Operation) callconv(.c) bool;
pub extern "c" fn mlirBlockCreate(n_args: isize, args: [*]const Type, locs: [*]const Location) callconv(.c) Block;
pub extern "c" fn mlirBlockAppendOwnedOperation(block: Block, op: Operation) callconv(.c) void;
pub extern "c" fn mlirBlockGetArgument(block: Block, pos: isize) callconv(.c) Value;
pub extern "c" fn mlirRegionCreate() callconv(.c) Region;
pub extern "c" fn mlirRegionAppendOwnedBlock(region: Region, block: Block) callconv(.c) void;
pub extern "c" fn mlirOperationGetRegion(op: Operation, pos: isize) callconv(.c) Region;
pub extern "c" fn mlirTypeParseGet(ctx: Context, type_str: StringRef) callconv(.c) Type;
pub extern "c" fn mlirIntegerTypeGet(ctx: Context, bitwidth: c_uint) callconv(.c) Type;
pub extern "c" fn mlirF32TypeGet(ctx: Context) callconv(.c) Type;
pub extern "c" fn mlirF64TypeGet(ctx: Context) callconv(.c) Type;
pub extern "c" fn mlirFunctionTypeGet(ctx: Context, n_inputs: isize, inputs: [*]const Type, n_results: isize, results: [*]const Type) callconv(.c) Type;
pub extern "c" fn mlirIntegerAttrGet(ty: Type, value: i64) callconv(.c) Attribute;
pub extern "c" fn mlirStringAttrGet(ctx: Context, str: StringRef) callconv(.c) Attribute;
pub extern "c" fn mlirIdentifierGet(ctx: Context, str: StringRef) callconv(.c) Identifier;
pub extern "c" fn mlirNamedAttributeGet(name: Identifier, attr: Attribute) callconv(.c) NamedAttribute;
pub extern "c" fn mlirFlatSymbolRefAttrGet(ctx: Context, symbol: StringRef) callconv(.c) Attribute;
pub extern "c" fn mlirTypeAttrGet(ty: Type) callconv(.c) Attribute;
pub extern "c" fn mlirOperationWriteBytecode(op: Operation, callback: StringCallback, user_data: ?*anyopaque) callconv(.c) void;
pub extern "c" fn mlirBytecodeWriterConfigCreate() callconv(.c) BytecodeWriterConfig;
pub extern "c" fn mlirBytecodeWriterConfigDestroy(config: BytecodeWriterConfig) callconv(.c) void;
pub extern "c" fn mlirBytecodeWriterConfigDesiredEmitVersion(config: BytecodeWriterConfig, version: i64) callconv(.c) void;
pub extern "c" fn mlirOperationWriteBytecodeWithConfig(op: Operation, config: BytecodeWriterConfig, callback: StringCallback, user_data: ?*anyopaque) callconv(.c) LogicalResult;

// Type introspection (for cast ops)
pub extern "c" fn mlirValueGetType(value: Value) callconv(.c) Type;
pub extern "c" fn mlirTypeEqual(t1: Type, t2: Type) callconv(.c) bool;
pub extern "c" fn mlirTypeIsAInteger(ty: Type) callconv(.c) bool;
pub extern "c" fn mlirTypeIsAFloat(ty: Type) callconv(.c) bool;
pub extern "c" fn mlirIntegerTypeGetWidth(ty: Type) callconv(.c) c_uint;
pub extern "c" fn mlirFloatTypeGetWidth(ty: Type) callconv(.c) c_uint;

// Operation attribute manipulation (for cir.generic_params)
pub extern "c" fn mlirOperationSetAttributeByName(op: Operation, name: StringRef, attr: Attribute) callconv(.c) void;

// Array attribute (for cir.generic_params array of string attrs)
pub extern "c" fn mlirArrayAttrGet(ctx: Context, numElements: isize, elements: [*]const Attribute) callconv(.c) Attribute;

// ============================================================
// CIR C API (from libcir/c-api/CIRCApi.h)
// ============================================================

// Dialect
pub extern "c" fn cirRegisterDialect(ctx: Context) callconv(.c) void;

// Type constructors
pub extern "c" fn cirPointerTypeGet(ctx: Context) callconv(.c) Type;
pub extern "c" fn cirRefTypeGet(ctx: Context, pointee: Type) callconv(.c) Type;
pub extern "c" fn cirStructTypeGet(ctx: Context, name: StringRef, n: isize, names: [*]const StringRef, types: [*]const Type) callconv(.c) Type;
pub extern "c" fn cirArrayTypeGet(ctx: Context, size: i64, elem: Type) callconv(.c) Type;
pub extern "c" fn cirSliceTypeGet(ctx: Context, elem: Type) callconv(.c) Type;

// Type queries
pub extern "c" fn cirTypeIsPointer(ty: Type) callconv(.c) bool;
pub extern "c" fn cirTypeIsRef(ty: Type) callconv(.c) bool;
pub extern "c" fn cirRefTypeGetPointee(ty: Type) callconv(.c) Type;
pub extern "c" fn cirTypeIsStruct(ty: Type) callconv(.c) bool;
pub extern "c" fn cirStructTypeGetNumFields(ty: Type) callconv(.c) isize;
pub extern "c" fn cirStructTypeGetFieldIndex(ty: Type, name: StringRef) callconv(.c) c_int;
pub extern "c" fn cirTypeIsArray(ty: Type) callconv(.c) bool;
pub extern "c" fn cirArrayTypeGetSize(ty: Type) callconv(.c) i64;
pub extern "c" fn cirArrayTypeGetElementType(ty: Type) callconv(.c) Type;
pub extern "c" fn cirTypeIsSlice(ty: Type) callconv(.c) bool;
pub extern "c" fn cirSliceTypeGetElementType(ty: Type) callconv(.c) Type;

// Constants
pub extern "c" fn cirBuildConstantInt(block: Block, loc: Location, ty: Type, value: i64) callconv(.c) Value;
pub extern "c" fn cirBuildConstantFloat(block: Block, loc: Location, ty: Type, value: f64) callconv(.c) Value;
pub extern "c" fn cirBuildConstantBool(block: Block, loc: Location, value: bool) callconv(.c) Value;
pub extern "c" fn cirBuildStringConstant(block: Block, loc: Location, value: StringRef) callconv(.c) Value;

// Arithmetic
pub extern "c" fn cirBuildAdd(block: Block, loc: Location, ty: Type, lhs: Value, rhs: Value) callconv(.c) Value;
pub extern "c" fn cirBuildSub(block: Block, loc: Location, ty: Type, lhs: Value, rhs: Value) callconv(.c) Value;
pub extern "c" fn cirBuildMul(block: Block, loc: Location, ty: Type, lhs: Value, rhs: Value) callconv(.c) Value;
pub extern "c" fn cirBuildDiv(block: Block, loc: Location, ty: Type, lhs: Value, rhs: Value) callconv(.c) Value;
pub extern "c" fn cirBuildRem(block: Block, loc: Location, ty: Type, lhs: Value, rhs: Value) callconv(.c) Value;
pub extern "c" fn cirBuildNeg(block: Block, loc: Location, ty: Type, operand: Value) callconv(.c) Value;

// Bitwise
pub extern "c" fn cirBuildBitAnd(block: Block, loc: Location, ty: Type, lhs: Value, rhs: Value) callconv(.c) Value;
pub extern "c" fn cirBuildBitOr(block: Block, loc: Location, ty: Type, lhs: Value, rhs: Value) callconv(.c) Value;
pub extern "c" fn cirBuildBitXor(block: Block, loc: Location, ty: Type, lhs: Value, rhs: Value) callconv(.c) Value;
pub extern "c" fn cirBuildBitNot(block: Block, loc: Location, ty: Type, operand: Value) callconv(.c) Value;
pub extern "c" fn cirBuildShl(block: Block, loc: Location, ty: Type, lhs: Value, rhs: Value) callconv(.c) Value;
pub extern "c" fn cirBuildShr(block: Block, loc: Location, ty: Type, lhs: Value, rhs: Value) callconv(.c) Value;

// Comparison
pub extern "c" fn cirBuildCmp(block: Block, loc: Location, pred: c_int, lhs: Value, rhs: Value) callconv(.c) Value;
pub extern "c" fn cirBuildSelect(block: Block, loc: Location, ty: Type, cond: Value, t: Value, f: Value) callconv(.c) Value;

// Casts
pub extern "c" fn cirBuildExtSI(block: Block, loc: Location, dst: Type, input: Value) callconv(.c) Value;
pub extern "c" fn cirBuildExtUI(block: Block, loc: Location, dst: Type, input: Value) callconv(.c) Value;
pub extern "c" fn cirBuildTruncI(block: Block, loc: Location, dst: Type, input: Value) callconv(.c) Value;
pub extern "c" fn cirBuildSIToFP(block: Block, loc: Location, dst: Type, input: Value) callconv(.c) Value;
pub extern "c" fn cirBuildFPToSI(block: Block, loc: Location, dst: Type, input: Value) callconv(.c) Value;
pub extern "c" fn cirBuildExtF(block: Block, loc: Location, dst: Type, input: Value) callconv(.c) Value;
pub extern "c" fn cirBuildTruncF(block: Block, loc: Location, dst: Type, input: Value) callconv(.c) Value;

// Memory
pub extern "c" fn cirBuildAlloca(block: Block, loc: Location, elem: Type) callconv(.c) Value;
pub extern "c" fn cirBuildStore(block: Block, loc: Location, value: Value, addr: Value) callconv(.c) void;
pub extern "c" fn cirBuildLoad(block: Block, loc: Location, result: Type, addr: Value) callconv(.c) Value;

// References
pub extern "c" fn cirBuildAddrOf(block: Block, loc: Location, refTy: Type, addr: Value) callconv(.c) Value;
pub extern "c" fn cirBuildDeref(block: Block, loc: Location, result: Type, ref: Value) callconv(.c) Value;

// Structs
pub extern "c" fn cirBuildStructInit(block: Block, loc: Location, ty: Type, n: isize, fields: [*]const Value) callconv(.c) Value;
pub extern "c" fn cirBuildFieldVal(block: Block, loc: Location, result: Type, input: Value, idx: i64) callconv(.c) Value;
pub extern "c" fn cirBuildFieldPtr(block: Block, loc: Location, base: Value, idx: i64, elem: Type) callconv(.c) Value;

// Arrays
pub extern "c" fn cirBuildArrayInit(block: Block, loc: Location, ty: Type, n: isize, elems: [*]const Value) callconv(.c) Value;
pub extern "c" fn cirBuildElemVal(block: Block, loc: Location, result: Type, input: Value, idx: i64) callconv(.c) Value;
pub extern "c" fn cirBuildElemPtr(block: Block, loc: Location, base: Value, idx: Value, elem: Type) callconv(.c) Value;

// Control flow
pub extern "c" fn cirBuildBr(block: Block, loc: Location, dest: Block, n: isize, args: [*]const Value) callconv(.c) void;
pub extern "c" fn cirBuildCondBr(block: Block, loc: Location, cond: Value, t: Block, f: Block) callconv(.c) void;
pub extern "c" fn cirBuildTrap(block: Block, loc: Location) callconv(.c) void;

// Optional type + ops
pub extern "c" fn cirOptionalTypeGet(ctx: Context, payload: Type) callconv(.c) Type;
pub extern "c" fn cirTypeIsOptional(ty: Type) callconv(.c) bool;
pub extern "c" fn cirOptionalTypeGetPayload(ty: Type) callconv(.c) Type;
pub extern "c" fn cirBuildNone(block: Block, loc: Location, ty: Type) callconv(.c) Value;
pub extern "c" fn cirBuildWrapOptional(block: Block, loc: Location, ty: Type, val: Value) callconv(.c) Value;
pub extern "c" fn cirBuildIsNonNull(block: Block, loc: Location, opt: Value) callconv(.c) Value;
pub extern "c" fn cirBuildOptionalPayload(block: Block, loc: Location, payload: Type, opt: Value) callconv(.c) Value;

// Slice ops
pub extern "c" fn cirBuildSlicePtr(block: Block, loc: Location, slice: Value) callconv(.c) Value;
pub extern "c" fn cirBuildSliceLen(block: Block, loc: Location, slice: Value) callconv(.c) Value;
pub extern "c" fn cirBuildSliceElem(block: Block, loc: Location, elem: Type, slice: Value, idx: Value) callconv(.c) Value;

// Error union type + ops
pub extern "c" fn cirErrorUnionTypeGet(ctx: Context, payload: Type) callconv(.c) Type;
pub extern "c" fn cirTypeIsErrorUnion(ty: Type) callconv(.c) bool;
pub extern "c" fn cirErrorUnionTypeGetPayload(ty: Type) callconv(.c) Type;
pub extern "c" fn cirBuildWrapResult(block: Block, loc: Location, euType: Type, value: Value) callconv(.c) Value;
pub extern "c" fn cirBuildWrapError(block: Block, loc: Location, euType: Type, errorCode: Value) callconv(.c) Value;
pub extern "c" fn cirBuildIsError(block: Block, loc: Location, errorUnion: Value) callconv(.c) Value;
pub extern "c" fn cirBuildErrorPayload(block: Block, loc: Location, payloadType: Type, errorUnion: Value) callconv(.c) Value;
pub extern "c" fn cirBuildErrorCode(block: Block, loc: Location, errorUnion: Value) callconv(.c) Value;

// Exception-based error handling
pub extern "c" fn cirBuildThrow(block: Block, loc: Location, value: Value) callconv(.c) void;
pub extern "c" fn cirBuildInvoke(block: Block, loc: Location, callee: StringRef, nOperands: isize, operands: [*]const Value, resultType: Type, normalDest: Block, unwindDest: Block) callconv(.c) Value;
pub extern "c" fn cirBuildLandingPad(block: Block, loc: Location, resultType: Type) callconv(.c) Value;

// Enum type + ops
pub extern "c" fn cirEnumTypeGet(ctx: Context, name: StringRef, tagType: Type, nVariants: isize, variantNames: [*]const StringRef, variantValues: [*]const i64) callconv(.c) Type;
pub extern "c" fn cirTypeIsEnum(ty: Type) callconv(.c) bool;
pub extern "c" fn cirEnumTypeGetTagType(enumType: Type) callconv(.c) Type;
pub extern "c" fn cirEnumTypeGetVariantValue(enumType: Type, name: StringRef) callconv(.c) i64;
pub extern "c" fn cirBuildEnumConstant(block: Block, loc: Location, enumType: Type, variant: StringRef) callconv(.c) Value;
pub extern "c" fn cirBuildEnumValue(block: Block, loc: Location, tagType: Type, enumVal: Value) callconv(.c) Value;

// Tagged union type + ops
pub extern "c" fn cirTaggedUnionTypeGet(ctx: Context, name: StringRef, nVariants: isize, variantNames: [*]const StringRef, variantTypes: [*]const Type) callconv(.c) Type;
pub extern "c" fn cirTypeIsTaggedUnion(ty: Type) callconv(.c) bool;
pub extern "c" fn cirBuildUnionInit(block: Block, loc: Location, unionType: Type, variant: StringRef, payload: Value) callconv(.c) Value;
pub extern "c" fn cirBuildUnionInitVoid(block: Block, loc: Location, unionType: Type, variant: StringRef) callconv(.c) Value;
pub extern "c" fn cirBuildUnionTag(block: Block, loc: Location, unionVal: Value) callconv(.c) Value;
pub extern "c" fn cirBuildUnionPayload(block: Block, loc: Location, payloadType: Type, variant: StringRef, unionVal: Value) callconv(.c) Value;

// Source Locations
pub extern "c" fn cirLocationFileLineCol(ctx: Context, filename: StringRef, line: c_uint, col: c_uint) callconv(.c) Location;

// Switch
pub extern "c" fn cirBuildSwitch(block: Block, loc: Location, value: Value, nCases: isize, caseValues: [*]const i64, caseDests: [*]const Block, defaultDest: Block) callconv(.c) void;

// Generic types + operations
pub extern "c" fn cirTypeParamGet(ctx: Context, name: StringRef) callconv(.c) Type;
pub extern "c" fn cirTypeIsTypeParam(ty: Type) callconv(.c) bool;
pub extern "c" fn cirBuildGenericApply(block: Block, loc: Location, callee: StringRef, nOperands: isize, operands: [*]const Value, resultType: Type, nSubs: isize, subsKeys: [*]const StringRef, subsTypes: [*]const Type) callconv(.c) Value;

// ============================================================
// Convenience API (ported from cot-failed/libzc/mlir.zig)
// ============================================================

pub fn createContext() Context {
    const ctx = mlirContextCreate();
    cirRegisterDialect(ctx);
    mlirContextSetAllowUnregisteredDialects(ctx, true);
    return ctx;
}

pub fn createModule(ctx: Context) Module {
    return mlirModuleCreateEmpty(mlirLocationUnknownGet(ctx));
}

pub fn serializeToBytecode(allocator: std.mem.Allocator, module: Module) ![]u8 {
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    errdefer buf.deinit(allocator);
    const Ctx = struct {
        buf: *std.ArrayListUnmanaged(u8),
        alloc: std.mem.Allocator,
        fn callback(chunk: StringRef, user_data: ?*anyopaque) callconv(.c) void {
            const self: *@This() = @ptrCast(@alignCast(user_data.?));
            self.buf.appendSlice(self.alloc, chunk.toSlice()) catch {};
        }
    };
    var ctx = Ctx{ .buf = &buf, .alloc = allocator };
    const op = mlirModuleGetOperation(module);
    const config = mlirBytecodeWriterConfigCreate();
    defer mlirBytecodeWriterConfigDestroy(config);
    mlirBytecodeWriterConfigDesiredEmitVersion(config, 1);
    const result = mlirOperationWriteBytecodeWithConfig(op, config, Ctx.callback, @ptrCast(&ctx));
    if (!result.isSuccess()) {
        mlirOperationWriteBytecode(op, Ctx.callback, @ptrCast(&ctx));
    }
    return buf.toOwnedSlice(allocator);
}

/// CIR operation builder — ported from cot-failed/libzc/mlir.zig CirBuilder.
pub const Builder = struct {
    ctx: Context,
    loc: Location,

    pub fn init(ctx: Context) Builder {
        return .{ .ctx = ctx, .loc = mlirLocationUnknownGet(ctx) };
    }

    pub fn intType(self: Builder, bits: c_uint) Type { return mlirIntegerTypeGet(self.ctx, bits); }
    pub fn parseType(self: Builder, type_str: []const u8) Type {
        return mlirTypeParseGet(self.ctx, StringRef.fromSlice(type_str));
    }

    pub fn attr(self: Builder, name: []const u8, value: Attribute) NamedAttribute {
        return mlirNamedAttributeGet(mlirIdentifierGet(self.ctx, StringRef.fromSlice(name)), value);
    }
    pub fn intAttr(_: Builder, ty: Type, value: i64) Attribute { return mlirIntegerAttrGet(ty, value); }
    pub fn strAttr(self: Builder, value: []const u8) Attribute { return mlirStringAttrGet(self.ctx, StringRef.fromSlice(value)); }
    pub fn typeAttr(_: Builder, ty: Type) Attribute { return mlirTypeAttrGet(ty); }

    pub fn emit(self: Builder, block: Block, name: []const u8, result_types: []const Type, operands: []const Value, attrs: []const NamedAttribute) Value {
        var state = mlirOperationStateGet(StringRef.fromSlice(name), self.loc);
        if (result_types.len > 0) mlirOperationStateAddResults(&state, @intCast(result_types.len), result_types.ptr);
        if (operands.len > 0) mlirOperationStateAddOperands(&state, @intCast(operands.len), operands.ptr);
        if (attrs.len > 0) mlirOperationStateAddAttributes(&state, @intCast(attrs.len), attrs.ptr);
        const operation = mlirOperationCreate(&state);
        mlirBlockAppendOwnedOperation(block, operation);
        if (result_types.len > 0) return mlirOperationGetResult(operation, 0);
        return Value{ .ptr = null };
    }

    /// Emit a terminator op with successor blocks (cir.br, cir.condbr).
    pub fn emitBranch(self: Builder, block: Block, name: []const u8, operands: []const Value, successors: []const Block) void {
        var state = mlirOperationStateGet(StringRef.fromSlice(name), self.loc);
        if (operands.len > 0) mlirOperationStateAddOperands(&state, @intCast(operands.len), operands.ptr);
        if (successors.len > 0) mlirOperationStateAddSuccessors(&state, @intCast(successors.len), successors.ptr);
        const operation = mlirOperationCreate(&state);
        mlirBlockAppendOwnedOperation(block, operation);
    }

    pub fn createBlock(self: Builder, arg_types: []const Type) Block {
        var locs_buf: [64]Location = undefined;
        for (0..arg_types.len) |j| locs_buf[j] = self.loc;
        return mlirBlockCreate(@intCast(arg_types.len), if (arg_types.len > 0) arg_types.ptr else undefined, if (arg_types.len > 0) &locs_buf else undefined);
    }

    pub fn createFunc(self: Builder, module: Module, name: []const u8, param_types: []const Type, return_types: []const Type) struct { func_op: Operation, entry_block: Block } {
        const func_type = mlirFunctionTypeGet(self.ctx, @intCast(param_types.len), if (param_types.len > 0) param_types.ptr else undefined, @intCast(return_types.len), if (return_types.len > 0) return_types.ptr else undefined);
        const region = mlirRegionCreate();
        var locs_buf: [64]Location = undefined;
        for (0..param_types.len) |j| locs_buf[j] = self.loc;
        const entry_block = mlirBlockCreate(@intCast(param_types.len), if (param_types.len > 0) param_types.ptr else undefined, if (param_types.len > 0) &locs_buf else undefined);
        mlirRegionAppendOwnedBlock(region, entry_block);
        var state = mlirOperationStateGet(StringRef.fromSlice("func.func"), self.loc);
        mlirOperationStateAddOwnedRegions(&state, 1, &[_]Region{region});
        const attrs = [_]NamedAttribute{ self.attr("sym_name", self.strAttr(name)), self.attr("function_type", self.typeAttr(func_type)) };
        mlirOperationStateAddAttributes(&state, attrs.len, &attrs);
        const func_op = mlirOperationCreate(&state);
        mlirBlockAppendOwnedOperation(mlirModuleGetBody(module), func_op);
        return .{ .func_op = func_op, .entry_block = entry_block };
    }

    /// Emit cir.struct_init with variadic field operands and struct result type.
    pub fn emitStructInit(self: Builder, block: Block, struct_type: Type, field_values: []const Value) Value {
        return self.emit(block, "cir.struct_init", &.{struct_type}, field_values, &.{});
    }
};
