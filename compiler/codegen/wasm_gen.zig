//! Wasm Code Generator - Emit bytecode for Wasm SSA ops.
//!
//! Go reference: cmd/compile/internal/wasm/ssa.go (ssaGenValue)
//!
//! This module translates lowered SSA (with wasm_* ops) to Wasm bytecode.
//! It follows Go's pattern of walking the SSA in scheduled order and
//! emitting instructions for each value.
//!
//! Key difference from register machines: Wasm is a stack machine.
//! Values flow through the operand stack, not registers.

const std = @import("std");
const SsaValue = @import("../ssa/value.zig").Value;
const SsaBlock = @import("../ssa/block.zig").Block;
const BlockKind = @import("../ssa/block.zig").BlockKind;
const SsaFunc = @import("../ssa/func.zig").Func;
const SsaOp = @import("../ssa/op.zig").Op;
const wasm = @import("wasm.zig");
const Op = wasm.Op;
const ValType = wasm.ValType;
const debug = @import("../pipeline_debug.zig");

/// Generator state for a single function.
pub const FuncGen = struct {
    allocator: std.mem.Allocator,
    ssa_func: *const SsaFunc,
    code: wasm.CodeBuilder,

    /// Maps SSA value IDs to local indices (for values that need locals).
    /// In a stack machine, most values stay on the operand stack.
    /// We only need locals for:
    /// - Function parameters (args)
    /// - Values used multiple times
    /// - Values used across basic blocks (phi nodes)
    value_to_local: std.AutoHashMapUnmanaged(u32, u32),

    /// Next available local index.
    next_local: u32,

    /// Number of function parameters.
    param_count: u32,

    pub fn init(allocator: std.mem.Allocator, ssa_func: *const SsaFunc) FuncGen {
        return .{
            .allocator = allocator,
            .ssa_func = ssa_func,
            .code = wasm.CodeBuilder.init(allocator),
            .value_to_local = .{},
            .next_local = 0,
            .param_count = 0,
        };
    }

    pub fn deinit(self: *FuncGen) void {
        self.code.deinit();
        self.value_to_local.deinit(self.allocator);
    }

    /// Generate code for the entire function.
    pub fn generate(self: *FuncGen) ![]const u8 {
        debug.log(.codegen, "wasm_gen: generating '{s}'", .{self.ssa_func.name});

        // Count parameters from arg ops
        self.param_count = self.countParams();
        self.next_local = self.param_count;

        debug.log(.codegen, "  params: {d}, blocks: {d}", .{ self.param_count, self.ssa_func.blocks.items.len });

        // Generate code for each block
        for (self.ssa_func.blocks.items) |block| {
            try self.genBlock(block);
        }

        // Finish and return body
        return self.code.finish();
    }

    fn countParams(self: *const FuncGen) u32 {
        var max_arg: u32 = 0;
        var has_args = false;
        for (self.ssa_func.blocks.items) |block| {
            for (block.values.items) |v| {
                if (v.op == .arg) {
                    has_args = true;
                    const arg_idx: u32 = @intCast(v.aux_int);
                    if (arg_idx >= max_arg) max_arg = arg_idx + 1;
                }
            }
        }
        return if (has_args) max_arg else 0;
    }

    /// Generate code for a basic block.
    fn genBlock(self: *FuncGen, block: *const SsaBlock) !void {
        debug.log(.codegen, "  block b{d} ({s})", .{ block.id, @tagName(block.kind) });

        // Generate values in order (assumes scheduled)
        for (block.values.items) |v| {
            try self.genValue(v);
        }

        // Generate block terminator
        try self.genBlockEnd(block);
    }

    /// Generate block terminator (branch, return, etc.)
    fn genBlockEnd(self: *FuncGen, block: *const SsaBlock) !void {
        switch (block.kind) {
            .ret => {
                // Return value should be on stack from control value
                // (In simple cases, nothing extra needed - value is already on stack)
            },
            .exit => {
                try self.code.emitReturn();
            },
            else => {
                // Plain/first blocks just fall through
            },
        }
    }

    /// Generate code for a single SSA value (ssaGenValue pattern).
    fn genValue(self: *FuncGen, v: *const SsaValue) !void {
        // Skip values with no uses (dead code) unless they have side effects
        if (v.uses == 0 and !v.hasSideEffects()) {
            // Still need to generate args and control values
            if (v.op != .arg and v.op != .wasm_return) return;
        }

        switch (v.op) {
            // ================================================================
            // Arguments (function parameters)
            // ================================================================
            .arg => {
                // Args map to Wasm locals 0..n-1
                // We don't emit anything here - local.get emitted when used
                const arg_idx: u32 = @intCast(v.aux_int);
                try self.value_to_local.put(self.allocator, v.id, arg_idx);
            },

            // ================================================================
            // Constants
            // ================================================================
            .wasm_i64_const => try self.code.emitI64Const(v.aux_int),
            .wasm_i32_const => try self.code.emitI32Const(@truncate(v.aux_int)),
            .wasm_f64_const => try self.code.emitF64Const(@bitCast(v.aux_int)),

            // ================================================================
            // Integer Arithmetic (i64)
            // ================================================================
            .wasm_i64_add => {
                try self.emitOperands(v);
                try self.code.emitI64Add();
            },
            .wasm_i64_sub => {
                try self.emitOperands(v);
                try self.code.emitI64Sub();
            },
            .wasm_i64_mul => {
                try self.emitOperands(v);
                try self.code.emitI64Mul();
            },
            .wasm_i64_div_s => {
                try self.emitOperands(v);
                try self.code.emitI64DivS();
            },
            .wasm_i64_rem_s => {
                try self.emitOperands(v);
                try self.code.emitI64RemS();
            },

            // ================================================================
            // Integer Bitwise (i64)
            // ================================================================
            .wasm_i64_and => {
                try self.emitOperands(v);
                try self.code.emitI64And();
            },
            .wasm_i64_or => {
                try self.emitOperands(v);
                try self.code.emitI64Or();
            },
            .wasm_i64_xor => {
                try self.emitOperands(v);
                try self.code.emitI64Xor();
            },
            .wasm_i64_shl => {
                try self.emitOperands(v);
                try self.code.emitI64Shl();
            },
            .wasm_i64_shr_s => {
                try self.emitOperands(v);
                try self.code.emitI64ShrS();
            },

            // ================================================================
            // Integer Comparisons (i64)
            // ================================================================
            .wasm_i64_eq => {
                try self.emitOperands(v);
                try self.code.emitI64Eq();
            },
            .wasm_i64_ne => {
                try self.emitOperands(v);
                try self.code.emitI64Ne();
            },
            .wasm_i64_lt_s => {
                try self.emitOperands(v);
                try self.code.emitI64LtS();
            },
            .wasm_i64_le_s => {
                try self.emitOperands(v);
                try self.code.emitI64LeS();
            },
            .wasm_i64_gt_s => {
                try self.emitOperands(v);
                try self.code.emitI64GtS();
            },
            .wasm_i64_ge_s => {
                try self.emitOperands(v);
                try self.code.emitI64GeS();
            },
            .wasm_i64_eqz => {
                try self.emitOperands(v);
                try self.code.emitI64Eqz();
            },

            // ================================================================
            // Float Arithmetic (f64)
            // ================================================================
            .wasm_f64_add => {
                try self.emitOperands(v);
                try self.code.emitF64Add();
            },
            .wasm_f64_sub => {
                try self.emitOperands(v);
                try self.code.emitF64Sub();
            },
            .wasm_f64_mul => {
                try self.emitOperands(v);
                try self.code.emitF64Mul();
            },
            .wasm_f64_div => {
                try self.emitOperands(v);
                try self.code.emitF64Div();
            },
            .wasm_f64_neg => {
                try self.emitOperands(v);
                try self.code.emitF64Neg();
            },

            // ================================================================
            // Float Comparisons (f64)
            // ================================================================
            .wasm_f64_eq => {
                try self.emitOperands(v);
                try self.code.emitF64Eq();
            },
            .wasm_f64_ne => {
                try self.emitOperands(v);
                try self.code.emitF64Ne();
            },
            .wasm_f64_lt => {
                try self.emitOperands(v);
                try self.code.emitF64Lt();
            },
            .wasm_f64_le => {
                try self.emitOperands(v);
                try self.code.emitF64Le();
            },
            .wasm_f64_gt => {
                try self.emitOperands(v);
                try self.code.emitF64Gt();
            },
            .wasm_f64_ge => {
                try self.emitOperands(v);
                try self.code.emitF64Ge();
            },

            // ================================================================
            // Variables
            // ================================================================
            .wasm_local_get => {
                const idx: u32 = @intCast(v.aux_int);
                try self.code.emitLocalGet(idx);
            },
            .wasm_local_set => {
                try self.emitOperands(v);
                const idx: u32 = @intCast(v.aux_int);
                try self.code.emitLocalSet(idx);
            },

            // ================================================================
            // Control Flow
            // ================================================================
            .wasm_call => {
                try self.emitOperands(v);
                const func_idx: u32 = @intCast(v.aux_int);
                try self.code.emitCall(func_idx);
            },
            .wasm_drop => {
                try self.emitOperands(v);
                try self.code.emitDrop();
            },
            .wasm_return => {
                try self.emitOperands(v);
                try self.code.emitReturn();
            },

            // ================================================================
            // Lowered Operations
            // ================================================================
            .wasm_lowered_static_call => {
                try self.emitOperands(v);
                // For now, assume function index is in aux_int
                const func_idx: u32 = @intCast(v.aux_int);
                try self.code.emitCall(func_idx);
            },

            // ================================================================
            // Copy/Move (emit operand, result stays on stack)
            // ================================================================
            .copy => try self.emitOperands(v),
            .wasm_lowered_move => try self.emitOperands(v),

            // ================================================================
            // Phi nodes (handled at block boundaries - not in linear codegen)
            // ================================================================
            .phi => {},

            // ================================================================
            // Control flow ops handled elsewhere
            // ================================================================
            .init_mem, .fwd_ref => {},

            // Many ops not yet implemented - add as needed
            else => {
                debug.log(.codegen, "  WARNING: unhandled op {s} for v{d}", .{ @tagName(v.op), v.id });
            },
        }
    }

    /// Emit operands (push them onto the stack).
    /// For args, emit local.get. For other values, they should already be on stack
    /// or we need to emit them recursively.
    fn emitOperands(self: *FuncGen, v: *const SsaValue) !void {
        for (v.args) |arg| {
            try self.emitValueRef(arg);
        }
    }

    /// Emit a reference to a value (get it onto the stack).
    fn emitValueRef(self: *FuncGen, v: *const SsaValue) !void {
        // Check if this value is a local (arg or stored value)
        if (self.value_to_local.get(v.id)) |local_idx| {
            try self.code.emitLocalGet(local_idx);
            return;
        }

        // For constants, re-emit them inline
        switch (v.op) {
            .wasm_i64_const, .const_int, .const_64 => try self.code.emitI64Const(v.aux_int),
            .wasm_i32_const, .const_32 => try self.code.emitI32Const(@truncate(v.aux_int)),
            .wasm_f64_const, .const_float => try self.code.emitF64Const(@bitCast(v.aux_int)),
            .arg => {
                // Arg should have been registered - register it now
                const arg_idx: u32 = @intCast(v.aux_int);
                try self.code.emitLocalGet(arg_idx);
            },
            else => {
                // For other ops, the value should have been computed and still on stack
                // This is a simplification - real codegen tracks stack state
                debug.log(.codegen, "  WARNING: emitValueRef for non-const {s} v{d}", .{ @tagName(v.op), v.id });
            },
        }
    }
};

/// Generate Wasm code for an SSA function.
pub fn genFunc(allocator: std.mem.Allocator, ssa_func: *const SsaFunc) ![]const u8 {
    var gen = FuncGen.init(allocator, ssa_func);
    defer gen.deinit();
    return gen.generate();
}

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "genFunc - return constant" {
    const allocator = testing.allocator;

    // Create a simple function: return 42
    var f = SsaFunc.init(allocator, "answer");
    defer f.deinit();

    const b = try f.newBlock(.ret);
    const c = try f.newValue(.wasm_i64_const, 0, b, .{});
    c.aux_int = 42;
    c.*.uses = 1;
    try b.addValue(allocator, c);

    // Generate
    const body = try genFunc(allocator, &f);
    defer allocator.free(body);

    // Verify: should contain i64.const 42 and end
    // Body format: [locals_count] [instructions...] [end]
    try testing.expect(body.len >= 3);
    try testing.expectEqual(@as(u8, 0), body[0]); // 0 locals
    try testing.expectEqual(Op.i64_const, body[1]);
    try testing.expectEqual(@as(u8, 42), body[2]); // LEB128(42)
    try testing.expectEqual(Op.end, body[body.len - 1]);
}

test "genFunc - add two args" {
    const allocator = testing.allocator;

    // Create: fn add(a: i64, b: i64) -> i64 { return a + b }
    var f = SsaFunc.init(allocator, "add");
    defer f.deinit();

    const b = try f.newBlock(.ret);

    // v1 = arg[0]
    const arg0 = try f.newValue(.arg, 0, b, .{});
    arg0.aux_int = 0;
    arg0.*.uses = 1;
    try b.addValue(allocator, arg0);

    // v2 = arg[1]
    const arg1 = try f.newValue(.arg, 0, b, .{});
    arg1.aux_int = 1;
    arg1.*.uses = 1;
    try b.addValue(allocator, arg1);

    // v3 = wasm_i64_add v1, v2
    const add = try f.newValue(.wasm_i64_add, 0, b, .{});
    add.addArg(arg0);
    add.addArg(arg1);
    add.*.uses = 1;
    try b.addValue(allocator, add);

    // Generate
    const body = try genFunc(allocator, &f);
    defer allocator.free(body);

    // Verify structure:
    // [0] = 0 locals
    // [1] = local.get 0
    // [2] = 0
    // [3] = local.get 1
    // [4] = 1
    // [5] = i64.add
    // [6] = end
    try testing.expect(body.len >= 7);
    try testing.expectEqual(@as(u8, 0), body[0]); // 0 locals
    try testing.expectEqual(Op.local_get, body[1]);
    try testing.expectEqual(@as(u8, 0), body[2]);
    try testing.expectEqual(Op.local_get, body[3]);
    try testing.expectEqual(@as(u8, 1), body[4]);
    try testing.expectEqual(Op.i64_add, body[5]);
    try testing.expectEqual(Op.end, body[body.len - 1]);
}

test "genFunc - const arithmetic" {
    const allocator = testing.allocator;

    // Create: return 10 + 20
    var f = SsaFunc.init(allocator, "const_add");
    defer f.deinit();

    const b = try f.newBlock(.ret);

    const c1 = try f.newValue(.wasm_i64_const, 0, b, .{});
    c1.aux_int = 10;
    c1.*.uses = 1;
    try b.addValue(allocator, c1);

    const c2 = try f.newValue(.wasm_i64_const, 0, b, .{});
    c2.aux_int = 20;
    c2.*.uses = 1;
    try b.addValue(allocator, c2);

    const add = try f.newValue(.wasm_i64_add, 0, b, .{});
    add.addArg(c1);
    add.addArg(c2);
    add.*.uses = 1;
    try b.addValue(allocator, add);

    const body = try genFunc(allocator, &f);
    defer allocator.free(body);

    // Should have: i64.const 10, i64.const 20, i64.add, end
    var found_add = false;
    for (body) |byte| {
        if (byte == Op.i64_add) found_add = true;
    }
    try testing.expect(found_add);
    try testing.expectEqual(Op.end, body[body.len - 1]);
}
