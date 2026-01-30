//! ABI (Application Binary Interface) - function call parameter/result passing.

const std = @import("std");
const types = @import("../../frontend/types.zig");
const TypeRegistry = types.TypeRegistry;
const TypeIndex = types.TypeIndex;
const FuncType = types.FuncType;
const debug = @import("../../pipeline_debug.zig");

pub const RegIndex = u8;
pub const RegMask = u32;

// ============================================================================
// ARM64 Calling Convention (AAPCS64)
// ============================================================================

pub const ARM64 = struct {
    pub const int_param_regs: u8 = 8;
    pub const int_result_regs: u8 = 2;
    pub const max_reg_aggregate: u32 = 16;
    pub const stack_align: u32 = 16;
    pub const reg_size: u32 = 8;
    pub const hidden_ret_reg: u5 = 8; // x8
    pub const param_regs = [_]RegIndex{ 0, 1, 2, 3, 4, 5, 6, 7 };
    pub const caller_save_mask: RegMask = 0x3FFFF; // x0-x17
    pub const arg_regs_mask: RegMask = 0xFF; // x0-x7

    pub fn regIndexToArm64(idx: RegIndex) u5 { return @intCast(idx); }
    pub fn regMask(reg: u5) RegMask { return @as(RegMask, 1) << reg; }
};

// ============================================================================
// AMD64 Calling Convention (System V)
// ============================================================================

pub const AMD64 = struct {
    pub const int_param_regs: u8 = 6;
    pub const int_result_regs: u8 = 2;
    pub const max_reg_aggregate: u32 = 16;
    pub const stack_align: u32 = 16;
    pub const reg_size: u32 = 8;
    pub const param_regs = [_]RegIndex{ 7, 6, 2, 1, 8, 9 }; // RDI, RSI, RDX, RCX, R8, R9
    pub const result_regs = [_]RegIndex{ 0, 2 }; // RAX, RDX
    pub const caller_save_mask: RegMask = 0xFC7; // RAX, RCX, RDX, RSI, RDI, R8-R11
    pub const arg_regs_mask: RegMask = 0x3C6;

    pub fn regIndexToAmd64(idx: RegIndex) u4 { return @intCast(idx); }
    pub fn regMask(reg: u4) RegMask { return @as(RegMask, 1) << reg; }
};

// ============================================================================
// ABI Parameter Assignment
// ============================================================================

pub const ABIParamAssignment = struct {
    type_idx: TypeIndex,
    registers: []const RegIndex,
    offset: i32,
    size: u32 = 0,

    pub fn inRegs(type_idx: TypeIndex, regs: []const RegIndex) ABIParamAssignment {
        return .{ .type_idx = type_idx, .registers = regs, .offset = 0, .size = @as(u32, @intCast(regs.len)) * 8 };
    }

    pub fn onStack(type_idx: TypeIndex, offset: i32, size: u32) ABIParamAssignment {
        return .{ .type_idx = type_idx, .registers = &[_]RegIndex{}, .offset = offset, .size = size };
    }

    pub fn isRegister(self: ABIParamAssignment) bool { return self.registers.len > 0; }
    pub fn isStack(self: ABIParamAssignment) bool { return self.registers.len == 0; }
};

// ============================================================================
// ABI Parameter/Result Info
// ============================================================================

pub const ABIParamResultInfo = struct {
    in_params: []const ABIParamAssignment,
    out_params: []const ABIParamAssignment,
    in_registers_used: u32,
    out_registers_used: u32,
    uses_hidden_return: bool = false,
    hidden_return_size: u32 = 0,

    pub fn inParam(self: *const ABIParamResultInfo, n: usize) ABIParamAssignment {
        return if (n < self.in_params.len) self.in_params[n] else .{ .type_idx = types.invalid_type, .registers = &[_]RegIndex{}, .offset = 0, .size = 0 };
    }

    pub fn outParam(self: *const ABIParamResultInfo, n: usize) ABIParamAssignment {
        return if (n < self.out_params.len) self.out_params[n] else .{ .type_idx = types.invalid_type, .registers = &[_]RegIndex{}, .offset = 0, .size = 0 };
    }

    pub fn regsOfArg(self: *const ABIParamResultInfo, n: usize) []const RegIndex {
        return if (n < self.in_params.len) self.in_params[n].registers else &[_]RegIndex{};
    }

    pub fn regsOfResult(self: *const ABIParamResultInfo, n: usize) []const RegIndex {
        return if (n < self.out_params.len) self.out_params[n].registers else &[_]RegIndex{};
    }

    pub fn offsetOfArg(self: *const ABIParamResultInfo, n: usize) i32 {
        return if (n < self.in_params.len) self.in_params[n].offset else 0;
    }

    pub fn offsetOfResult(self: *const ABIParamResultInfo, n: usize) i32 {
        return if (n < self.out_params.len) self.out_params[n].offset else 0;
    }

    pub fn typeOfArg(self: *const ABIParamResultInfo, n: usize) TypeIndex {
        return if (n < self.in_params.len) self.in_params[n].type_idx else types.invalid_type;
    }

    pub fn typeOfResult(self: *const ABIParamResultInfo, n: usize) TypeIndex {
        return if (n < self.out_params.len) self.out_params[n].type_idx else types.invalid_type;
    }

    pub fn numArgs(self: *const ABIParamResultInfo) usize { return self.in_params.len; }
    pub fn numResults(self: *const ABIParamResultInfo) usize { return self.out_params.len; }

    pub fn argWidth(self: *const ABIParamResultInfo) u32 {
        var max_offset: u32 = 0;
        for (self.in_params) |p| {
            if (p.isStack()) {
                const end = @as(u32, @intCast(@max(0, p.offset))) + p.size;
                if (end > max_offset) max_offset = end;
            }
        }
        return alignUp(max_offset, ARM64.stack_align);
    }
};

// ============================================================================
// Register Info (for register allocator)
// ============================================================================

pub const InputInfo = struct { idx: u8, regs: RegMask };
pub const OutputInfo = struct { idx: u8, regs: RegMask };

pub const RegInfo = struct {
    inputs: []const InputInfo,
    outputs: []const OutputInfo,
    clobbers: RegMask,

    pub const empty = RegInfo{ .inputs = &[_]InputInfo{}, .outputs = &[_]OutputInfo{}, .clobbers = 0 };
};

pub fn buildCallRegInfo(allocator: std.mem.Allocator, abi_info: *const ABIParamResultInfo) !RegInfo {
    var inputs = std.ArrayList(InputInfo).init(allocator);
    var outputs = std.ArrayList(OutputInfo).init(allocator);

    var arg_idx: u8 = 0;
    for (abi_info.in_params) |param| {
        for (param.registers) |reg_idx| {
            try inputs.append(.{ .idx = arg_idx, .regs = ARM64.regMask(ARM64.regIndexToArm64(reg_idx)) });
            arg_idx += 1;
        }
    }

    var out_idx: u8 = 0;
    for (abi_info.out_params) |param| {
        for (param.registers) |reg_idx| {
            try outputs.append(.{ .idx = out_idx, .regs = ARM64.regMask(ARM64.regIndexToArm64(reg_idx)) });
            out_idx += 1;
        }
    }

    return .{ .inputs = try inputs.toOwnedSlice(), .outputs = try outputs.toOwnedSlice(), .clobbers = ARM64.caller_save_mask };
}

// ============================================================================
// Pre-built ABI Info for Runtime Calls
// ============================================================================

pub const str_concat_abi_arm64 = ABIParamResultInfo{
    .in_params = &[_]ABIParamAssignment{
        ABIParamAssignment.inRegs(TypeRegistry.I64, &[_]RegIndex{0}),
        ABIParamAssignment.inRegs(TypeRegistry.I64, &[_]RegIndex{1}),
        ABIParamAssignment.inRegs(TypeRegistry.I64, &[_]RegIndex{2}),
        ABIParamAssignment.inRegs(TypeRegistry.I64, &[_]RegIndex{3}),
    },
    .out_params = &[_]ABIParamAssignment{
        ABIParamAssignment.inRegs(TypeRegistry.I64, &[_]RegIndex{0}),
        ABIParamAssignment.inRegs(TypeRegistry.I64, &[_]RegIndex{1}),
    },
    .in_registers_used = 4,
    .out_registers_used = 2,
};

pub const str_concat_abi_amd64 = ABIParamResultInfo{
    .in_params = &[_]ABIParamAssignment{
        ABIParamAssignment.inRegs(TypeRegistry.I64, &[_]RegIndex{7}),
        ABIParamAssignment.inRegs(TypeRegistry.I64, &[_]RegIndex{6}),
        ABIParamAssignment.inRegs(TypeRegistry.I64, &[_]RegIndex{2}),
        ABIParamAssignment.inRegs(TypeRegistry.I64, &[_]RegIndex{1}),
    },
    .out_params = &[_]ABIParamAssignment{
        ABIParamAssignment.inRegs(TypeRegistry.I64, &[_]RegIndex{0}),
        ABIParamAssignment.inRegs(TypeRegistry.I64, &[_]RegIndex{2}),
    },
    .in_registers_used = 4,
    .out_registers_used = 2,
};

pub const str_concat_abi = str_concat_abi_arm64;

// ============================================================================
// ABI Analysis
// ============================================================================

const AssignState = struct {
    int_reg_idx: usize = 0,
    stack_offset: u32 = 0,
    spill_offset: u32 = 0,

    fn resetRegs(self: *AssignState) void { self.int_reg_idx = 0; }

    fn tryAllocRegs(self: *AssignState, type_size: u32) ?[]const RegIndex {
        if (type_size <= 8 and self.int_reg_idx < ARM64.int_param_regs) {
            const start = self.int_reg_idx;
            self.int_reg_idx += 1;
            return ARM64.param_regs[start .. start + 1];
        }
        if (type_size > 8 and type_size <= 16 and self.int_reg_idx + 1 < ARM64.int_param_regs) {
            const start = self.int_reg_idx;
            self.int_reg_idx += 2;
            return ARM64.param_regs[start .. start + 2];
        }
        return null;
    }

    fn allocStack(self: *AssignState, type_size: u32, alignment: u32) i32 {
        self.stack_offset = alignUp(self.stack_offset, alignment);
        const offset = self.stack_offset;
        self.stack_offset += type_size;
        return @intCast(offset);
    }

    fn allocSpill(self: *AssignState, type_size: u32, alignment: u32) i32 {
        self.spill_offset = alignUp(self.spill_offset, alignment);
        const offset = self.spill_offset;
        self.spill_offset += type_size;
        return @intCast(offset);
    }
};

pub fn analyzeFunc(func_type: FuncType, type_reg: *const TypeRegistry, allocator: std.mem.Allocator) !*ABIParamResultInfo {
    debug.log(.abi, "analyzeFunc: {d} params, ret size {d}", .{
        func_type.params.len, type_reg.sizeOf(func_type.return_type),
    });

    var state = AssignState{};
    var in_params = std.ArrayListUnmanaged(ABIParamAssignment){};
    var out_params = std.ArrayListUnmanaged(ABIParamAssignment){};

    // Analyze input parameters
    for (func_type.params) |param| {
        const param_size = type_reg.sizeOf(param.type_idx);
        const param_align = type_reg.alignmentOf(param.type_idx);

        var assignment = ABIParamAssignment{ .type_idx = param.type_idx, .registers = &[_]RegIndex{}, .offset = 0, .size = param_size };

        if (state.tryAllocRegs(param_size)) |regs| {
            assignment.registers = regs;
            assignment.offset = state.allocSpill(param_size, param_align);
            debug.log(.abi, "  param: size={d} -> regs {any}", .{ param_size, regs });
        } else {
            assignment.offset = state.allocStack(param_size, param_align);
            debug.log(.abi, "  param: size={d} -> stack off={d}", .{ param_size, assignment.offset });
        }
        try in_params.append(allocator, assignment);
    }

    const in_regs_used: u32 = @intCast(state.int_reg_idx);
    state.resetRegs();

    // Analyze return type
    const ret_type_idx = func_type.return_type;
    const ret_size = type_reg.sizeOf(ret_type_idx);
    var uses_hidden_return = false;
    var hidden_return_size: u32 = 0;

    if (ret_size > 0 and ret_type_idx != TypeRegistry.VOID) {
        if (ret_size > ARM64.max_reg_aggregate) {
            uses_hidden_return = true;
            hidden_return_size = ret_size;
            try out_params.append(allocator, .{ .type_idx = ret_type_idx, .registers = &[_]RegIndex{}, .offset = 0, .size = ret_size });
        } else {
            var assignment = ABIParamAssignment{ .type_idx = ret_type_idx, .registers = &[_]RegIndex{}, .offset = 0, .size = ret_size };
            if (state.tryAllocRegs(ret_size)) |regs| assignment.registers = regs;
            try out_params.append(allocator, assignment);
        }
    }

    const out_regs_used: u32 = @intCast(state.int_reg_idx);

    const info = try allocator.create(ABIParamResultInfo);
    info.* = .{
        .in_params = try in_params.toOwnedSlice(allocator),
        .out_params = try out_params.toOwnedSlice(allocator),
        .in_registers_used = in_regs_used,
        .out_registers_used = out_regs_used,
        .uses_hidden_return = uses_hidden_return,
        .hidden_return_size = hidden_return_size,
    };
    return info;
}

pub fn analyzeFuncType(func_type_idx: TypeIndex, type_reg: *const TypeRegistry, allocator: std.mem.Allocator) !*ABIParamResultInfo {
    const t = type_reg.get(func_type_idx);
    if (t != .func) {
        const info = try allocator.create(ABIParamResultInfo);
        info.* = .{ .in_params = &[_]ABIParamAssignment{}, .out_params = &[_]ABIParamAssignment{}, .in_registers_used = 0, .out_registers_used = 0 };
        return info;
    }
    return analyzeFunc(t.func, type_reg, allocator);
}

fn alignUp(value: u32, alignment: u32) u32 {
    if (alignment == 0) return value;
    return (value + alignment - 1) & ~(alignment - 1);
}

// ============================================================================
// Tests
// ============================================================================

test "ARM64 register masks" {
    try std.testing.expectEqual(@as(RegMask, 1), ARM64.regMask(0));
    try std.testing.expectEqual(@as(RegMask, 2), ARM64.regMask(1));
    try std.testing.expectEqual(@as(RegMask, 0x100), ARM64.regMask(8));
}

test "AMD64 register masks" {
    try std.testing.expectEqual(@as(RegMask, 1), AMD64.regMask(0));
    try std.testing.expectEqual(@as(RegMask, 0x80), AMD64.regMask(7));
}

test "str_concat_abi_arm64 structure" {
    try std.testing.expectEqual(@as(usize, 4), str_concat_abi_arm64.in_params.len);
    try std.testing.expectEqual(@as(usize, 2), str_concat_abi_arm64.out_params.len);
    try std.testing.expectEqual(@as(u32, 4), str_concat_abi_arm64.in_registers_used);
    try std.testing.expectEqual(@as(u32, 2), str_concat_abi_arm64.out_registers_used);
    try std.testing.expectEqual(@as(RegIndex, 0), str_concat_abi_arm64.in_params[0].registers[0]);
}

test "str_concat_abi_amd64 structure" {
    try std.testing.expectEqual(@as(usize, 4), str_concat_abi_amd64.in_params.len);
    try std.testing.expectEqual(@as(usize, 2), str_concat_abi_amd64.out_params.len);
    try std.testing.expectEqual(@as(RegIndex, 7), str_concat_abi_amd64.in_params[0].registers[0]); // RDI
    try std.testing.expectEqual(@as(RegIndex, 0), str_concat_abi_amd64.out_params[0].registers[0]); // RAX
}

test "ABIParamAssignment constructors" {
    const reg_param = ABIParamAssignment.inRegs(TypeRegistry.I64, &[_]RegIndex{ 0, 1 });
    try std.testing.expect(reg_param.isRegister());
    try std.testing.expect(!reg_param.isStack());
    try std.testing.expectEqual(@as(u32, 16), reg_param.size);

    const stack_param = ABIParamAssignment.onStack(TypeRegistry.I64, 16, 8);
    try std.testing.expect(!stack_param.isRegister());
    try std.testing.expect(stack_param.isStack());
    try std.testing.expectEqual(@as(i32, 16), stack_param.offset);
}

test "ABIParamResultInfo accessors" {
    const info = str_concat_abi_arm64;
    try std.testing.expectEqual(@as(usize, 4), info.numArgs());
    try std.testing.expectEqual(@as(usize, 2), info.numResults());
    try std.testing.expectEqual(@as(RegIndex, 1), info.regsOfArg(1)[0]);
    try std.testing.expectEqual(@as(RegIndex, 0), info.regsOfResult(0)[0]);
}

test "RegInfo empty" {
    const empty = RegInfo.empty;
    try std.testing.expectEqual(@as(usize, 0), empty.inputs.len);
    try std.testing.expectEqual(@as(usize, 0), empty.outputs.len);
    try std.testing.expectEqual(@as(RegMask, 0), empty.clobbers);
}

test "alignUp" {
    try std.testing.expectEqual(@as(u32, 0), alignUp(0, 8));
    try std.testing.expectEqual(@as(u32, 8), alignUp(1, 8));
    try std.testing.expectEqual(@as(u32, 8), alignUp(8, 8));
    try std.testing.expectEqual(@as(u32, 16), alignUp(9, 8));
    try std.testing.expectEqual(@as(u32, 16), alignUp(16, 16));
    try std.testing.expectEqual(@as(u32, 32), alignUp(17, 16));
}
