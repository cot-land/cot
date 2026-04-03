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

// CIR dialect registration (from libcir/c-api/CIRCApi.h)
pub extern "c" fn cirRegisterDialect(ctx: Context) callconv(.c) void;

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
};
