//! Wasm Code Generator - Emit bytecode for Wasm SSA ops.
//!
//! Go reference: cmd/compile/internal/wasm/ssa.go
//!
//! This module translates lowered SSA (with wasm_* ops) to Wasm bytecode.
//! Key functions:
//! - ssaGenValue: emit bytecode for a single SSA value
//! - ssaGenBlock: emit control flow for block transitions
//!
//! Wasm has structured control flow (no arbitrary jumps), so we use:
//! - block/end for forward branches
//! - loop/end for backward branches (loops)
//! - if/else/end for conditionals
//! - br/br_if to branch to enclosing block labels

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

// Block type constants for Wasm structured control flow
const BLOCK_TYPE_VOID: u8 = 0x40;
const BLOCK_TYPE_I32: u8 = 0x7F;
const BLOCK_TYPE_I64: u8 = 0x7E;
const BLOCK_TYPE_F32: u8 = 0x7D;
const BLOCK_TYPE_F64: u8 = 0x7C;

/// Generator state for a single function.
pub const FuncGen = struct {
    allocator: std.mem.Allocator,
    ssa_func: *const SsaFunc,
    code: wasm.CodeBuilder,

    /// Maps SSA value IDs to local indices.
    value_to_local: std.AutoHashMapUnmanaged(u32, u32),

    /// Maps SSA block IDs to their index in the block order.
    block_to_idx: std.AutoHashMapUnmanaged(u32, usize),

    /// Next available local index.
    next_local: u32,

    /// Number of function parameters.
    param_count: u32,

    /// Current nesting depth for branch targets (Go's currentDepth).
    /// Each block/loop/if increases depth, end decreases it.
    block_depth: u32,

    /// Maps block ID to its nesting depth when emitted (Go's blockDepths).
    /// Used to calculate relative branch targets: currentDepth - blockDepth
    block_depths: std.AutoHashMapUnmanaged(u32, u32),

    /// Blocks that are loop headers (have incoming back edges).
    loop_headers: std.AutoHashMapUnmanaged(u32, void),

    pub fn init(allocator: std.mem.Allocator, ssa_func: *const SsaFunc) FuncGen {
        return .{
            .allocator = allocator,
            .ssa_func = ssa_func,
            .code = wasm.CodeBuilder.init(allocator),
            .value_to_local = .{},
            .block_to_idx = .{},
            .next_local = 0,
            .param_count = 0,
            .block_depth = 0,
            .block_depths = .{},
            .loop_headers = .{},
        };
    }

    pub fn deinit(self: *FuncGen) void {
        self.code.deinit();
        self.value_to_local.deinit(self.allocator);
        self.block_to_idx.deinit(self.allocator);
        self.block_depths.deinit(self.allocator);
        self.loop_headers.deinit(self.allocator);
    }

    /// Generate code for the entire function.
    pub fn generate(self: *FuncGen) ![]const u8 {
        debug.log(.codegen, "wasm_gen: generating '{s}'", .{self.ssa_func.name});

        // Build block index map
        for (self.ssa_func.blocks.items, 0..) |b, i| {
            try self.block_to_idx.put(self.allocator, b.id, i);
        }

        // Count parameters
        self.param_count = self.countParams();
        self.next_local = self.param_count;

        debug.log(.codegen, "  params: {d}, blocks: {d}", .{ self.param_count, self.ssa_func.blocks.items.len });

        // Identify loop headers (blocks that are targets of back edges)
        // This follows Go's pattern of tracking blockDepths for branch resolution
        try self.findLoopHeaders();

        // Generate code for each block with "next" tracking
        const blocks = self.ssa_func.blocks.items;
        for (blocks, 0..) |block, i| {
            const next: ?*const SsaBlock = if (i + 1 < blocks.len) blocks[i + 1] else null;
            const is_loop_header = self.loop_headers.contains(block.id);
            try self.genBlockWithNext(block, next, is_loop_header);
        }

        return self.code.finish();
    }

    /// Find blocks that are loop headers (targets of backward edges).
    /// Go's approach: track which blocks need loop wrappers for back edge targets.
    fn findLoopHeaders(self: *FuncGen) !void {
        const blocks = self.ssa_func.blocks.items;
        for (blocks, 0..) |block, block_idx| {
            for (block.succs) |edge| {
                const succ_idx = self.block_to_idx.get(edge.b.id) orelse continue;
                // A back edge is when successor comes before or at current block in layout order
                if (succ_idx <= block_idx) {
                    debug.log(.codegen, "  loop header: b{d} (back edge from b{d})", .{ edge.b.id, block.id });
                    try self.loop_headers.put(self.allocator, edge.b.id, {});
                }
            }
        }
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

    /// Generate code for a block, knowing what the next block is.
    /// Follows Go's pattern: emit loop for loop headers, track depths for branch resolution.
    fn genBlockWithNext(self: *FuncGen, block: *const SsaBlock, next: ?*const SsaBlock, is_loop_header: bool) !void {
        debug.log(.codegen, "  block b{d} ({s}){s} depth={d}", .{
            block.id,
            @tagName(block.kind),
            if (is_loop_header) " [loop header]" else "",
            self.block_depth,
        });

        // If this is a loop header, emit loop instruction (Go's ALoop)
        // When a back edge jumps here, it uses br with relative depth
        if (is_loop_header) {
            try self.code.emitLoop(BLOCK_TYPE_VOID);
            self.block_depth += 1;
            // Record depth AFTER incrementing (Go's blockDepths[p] = currentDepth)
            try self.block_depths.put(self.allocator, block.id, self.block_depth);
            debug.log(.codegen, "    emitted loop, depth now {d}", .{self.block_depth});
        }

        // Generate values in the block
        for (block.values.items) |v| {
            try self.ssaGenValue(v);
        }

        // Generate block terminator (ssaGenBlock pattern from Go)
        try self.ssaGenBlock(block, next);

        // If this was a loop header, we need to close the loop after processing
        // all blocks that are part of the loop body - this is handled by finding
        // where the back edge originates and emitting 'end' there
    }

    /// Generate control flow for block transitions (Go's ssaGenBlock).
    /// Handles branches following Go's pattern: compute relative depth for br instructions.
    fn ssaGenBlock(self: *FuncGen, b: *const SsaBlock, next: ?*const SsaBlock) !void {
        switch (b.kind) {
            .plain, .first => {
                // Plain blocks fall through to successor or jump
                if (b.succs.len > 0) {
                    const succ = b.succs[0].b;
                    if (next == null or next.?.id != succ.id) {
                        // Need to jump - check if this is a back edge (loop continue)
                        if (self.block_depths.get(succ.id)) |target_depth| {
                            // Back edge to loop header - emit br with relative depth
                            // Go's formula: currentDepth - blockDepth
                            const rel_depth = self.block_depth - target_depth;
                            debug.log(.codegen, "    plain: back edge to b{d}, br {d}", .{ succ.id, rel_depth });
                            try self.code.emitBr(rel_depth);
                            // After back edge, we need to close the loop
                            try self.code.emitEnd();
                            self.block_depth -= 1;
                        } else {
                            // Forward jump - for now, fall through and trust layout
                            debug.log(.codegen, "    plain: forward jump to b{d} (not implemented)", .{succ.id});
                        }
                    }
                    // else: fall through, nothing needed
                }
            },

            .if_ => {
                // Conditional branch - Go's BlockIf handling
                if (b.succs.len < 2) {
                    debug.log(.codegen, "    if: missing successors", .{});
                    return;
                }

                const succ_true = b.succs[0].b;
                const succ_false = b.succs[1].b;

                // Get condition value onto stack
                if (b.controls[0]) |cond| {
                    try self.emitValueRef(cond);
                    // Condition is i64, need to convert to i32 for Wasm if
                    try self.code.emitI32WrapI64();
                }

                // Check if either successor is a loop header (back edge target)
                const true_is_loop = self.block_depths.contains(succ_true.id);
                const false_is_loop = self.block_depths.contains(succ_false.id);

                // Emit control flow based on which successor is "next" (Go's pattern)
                if (next != null and next.?.id == succ_true.id) {
                    // True branch is next - emit: if false, jump to false successor
                    try self.code.emitI32Eqz(); // invert condition
                    try self.code.emitIf(BLOCK_TYPE_VOID);
                    self.block_depth += 1;

                    if (false_is_loop) {
                        // Back edge - br to loop header
                        const target_depth = self.block_depths.get(succ_false.id).?;
                        const rel_depth = self.block_depth - target_depth;
                        try self.code.emitBr(rel_depth);
                    } else {
                        try self.code.emitBr(0); // exit if block
                    }

                    try self.code.emitEnd();
                    self.block_depth -= 1;
                    debug.log(.codegen, "    if: true is next, false jump", .{});
                } else if (next != null and next.?.id == succ_false.id) {
                    // False branch is next - emit: if true, jump to true successor
                    try self.code.emitIf(BLOCK_TYPE_VOID);
                    self.block_depth += 1;

                    if (true_is_loop) {
                        // Back edge - br to loop header
                        const target_depth = self.block_depths.get(succ_true.id).?;
                        const rel_depth = self.block_depth - target_depth;
                        try self.code.emitBr(rel_depth);
                    } else {
                        try self.code.emitBr(0); // exit if block
                    }

                    try self.code.emitEnd();
                    self.block_depth -= 1;
                    debug.log(.codegen, "    if: false is next, true jump", .{});
                } else {
                    // Neither is next - emit both jumps
                    try self.code.emitIf(BLOCK_TYPE_VOID);
                    self.block_depth += 1;

                    if (true_is_loop) {
                        const target_depth = self.block_depths.get(succ_true.id).?;
                        const rel_depth = self.block_depth - target_depth;
                        try self.code.emitBr(rel_depth);
                    } else {
                        try self.code.emitBr(0);
                    }

                    try self.code.emitEnd();
                    self.block_depth -= 1;

                    if (false_is_loop) {
                        const target_depth = self.block_depths.get(succ_false.id).?;
                        const rel_depth = self.block_depth - target_depth;
                        try self.code.emitBr(rel_depth);
                    }
                    debug.log(.codegen, "    if: neither is next", .{});
                }
            },

            .ret => {
                // Return block - value should be on stack from control value
                if (b.controls[0]) |ret_val| {
                    try self.emitValueRef(ret_val);
                }
                // Wasm function body implicitly returns top of stack
                // No explicit return needed unless we want early return
            },

            .exit => {
                // Exit without return value
                try self.code.emitReturn();
            },

            else => {
                debug.log(.codegen, "    unhandled block kind: {s}", .{@tagName(b.kind)});
            },
        }
    }

    /// Generate code for a single SSA value (Go's ssaGenValue).
    fn ssaGenValue(self: *FuncGen, v: *const SsaValue) !void {
        // Skip dead values unless they have side effects
        if (v.uses == 0 and !v.hasSideEffects()) {
            if (v.op != .arg and v.op != .wasm_return) return;
        }

        switch (v.op) {
            // ================================================================
            // Arguments (function parameters)
            // ================================================================
            .arg => {
                const arg_idx: u32 = @intCast(v.aux_int);
                try self.value_to_local.put(self.allocator, v.id, arg_idx);
            },

            // ================================================================
            // Constants
            // ================================================================
            .wasm_i64_const, .const_int, .const_64 => try self.code.emitI64Const(v.aux_int),
            .wasm_i32_const, .const_32 => try self.code.emitI32Const(@truncate(v.aux_int)),
            .wasm_f64_const, .const_float => try self.code.emitF64Const(@bitCast(v.aux_int)),

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
                const func_idx: u32 = @intCast(v.aux_int);
                try self.code.emitCall(func_idx);
            },

            // ================================================================
            // Copy/Move
            // ================================================================
            .copy, .wasm_lowered_move => try self.emitOperands(v),

            // ================================================================
            // Control flow ops handled in ssaGenBlock
            // ================================================================
            .phi, .init_mem, .fwd_ref => {},

            else => {
                debug.log(.codegen, "    unhandled op: {s} v{d}", .{ @tagName(v.op), v.id });
            },
        }
    }

    /// Emit operands (push them onto the stack).
    fn emitOperands(self: *FuncGen, v: *const SsaValue) !void {
        for (v.args) |arg| {
            try self.emitValueRef(arg);
        }
    }

    /// Emit a reference to a value (get it onto the stack).
    fn emitValueRef(self: *FuncGen, v: *const SsaValue) !void {
        // Check if this value is a local
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
                const arg_idx: u32 = @intCast(v.aux_int);
                try self.code.emitLocalGet(arg_idx);
            },
            else => {
                // Value should have been computed - emit warning
                debug.log(.codegen, "    WARNING: emitValueRef for {s} v{d}", .{ @tagName(v.op), v.id });
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

    var f = SsaFunc.init(allocator, "answer");
    defer f.deinit();

    const b = try f.newBlock(.ret);
    const c = try f.newValue(.wasm_i64_const, 0, b, .{});
    c.aux_int = 42;
    c.*.uses = 1;
    try b.addValue(allocator, c);
    b.controls[0] = c;

    const body = try genFunc(allocator, &f);
    defer allocator.free(body);

    // Verify: should contain i64.const 42 and end
    try testing.expect(body.len >= 3);
    try testing.expectEqual(@as(u8, 0), body[0]); // 0 locals
    try testing.expectEqual(Op.i64_const, body[1]);
    try testing.expectEqual(@as(u8, 42), body[2]);
    try testing.expectEqual(Op.end, body[body.len - 1]);
}

test "genFunc - add two args" {
    const allocator = testing.allocator;

    var f = SsaFunc.init(allocator, "add");
    defer f.deinit();

    const b = try f.newBlock(.ret);

    const arg0 = try f.newValue(.arg, 0, b, .{});
    arg0.aux_int = 0;
    arg0.*.uses = 1;
    try b.addValue(allocator, arg0);

    const arg1 = try f.newValue(.arg, 0, b, .{});
    arg1.aux_int = 1;
    arg1.*.uses = 1;
    try b.addValue(allocator, arg1);

    const add = try f.newValue(.wasm_i64_add, 0, b, .{});
    add.addArg(arg0);
    add.addArg(arg1);
    add.*.uses = 1;
    try b.addValue(allocator, add);
    b.controls[0] = add;

    const body = try genFunc(allocator, &f);
    defer allocator.free(body);

    try testing.expect(body.len >= 6);
    try testing.expectEqual(@as(u8, 0), body[0]); // 0 locals
    try testing.expectEqual(Op.local_get, body[1]);
    try testing.expectEqual(Op.local_get, body[3]);
    try testing.expectEqual(Op.i64_add, body[5]);
    try testing.expectEqual(Op.end, body[body.len - 1]);
}

test "genFunc - const arithmetic" {
    const allocator = testing.allocator;

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
    b.controls[0] = add;

    const body = try genFunc(allocator, &f);
    defer allocator.free(body);

    var found_add = false;
    for (body) |byte| {
        if (byte == Op.i64_add) found_add = true;
    }
    try testing.expect(found_add);
    try testing.expectEqual(Op.end, body[body.len - 1]);
}

test "genFunc - simple if block" {
    const allocator = testing.allocator;

    var f = SsaFunc.init(allocator, "max");
    defer f.deinit();

    // Create: if (cond) then b2 else b3, merge at b4
    const b1 = try f.newBlock(.if_);
    const b2 = try f.newBlock(.plain);
    const b3 = try f.newBlock(.plain);
    const b4 = try f.newBlock(.ret);

    // Setup edges
    try b1.addEdgeTo(allocator, b2);
    try b1.addEdgeTo(allocator, b3);
    try b2.addEdgeTo(allocator, b4);
    try b3.addEdgeTo(allocator, b4);

    // Add condition to b1
    const cond = try f.newValue(.wasm_i64_const, 0, b1, .{});
    cond.aux_int = 1; // true
    cond.*.uses = 1;
    try b1.addValue(allocator, cond);
    b1.controls[0] = cond;

    // Add return value to b4
    const ret = try f.newValue(.wasm_i64_const, 0, b4, .{});
    ret.aux_int = 42;
    ret.*.uses = 1;
    try b4.addValue(allocator, ret);
    b4.controls[0] = ret;

    const body = try genFunc(allocator, &f);
    defer allocator.free(body);

    // Should compile without error
    try testing.expect(body.len > 0);
    try testing.expectEqual(Op.end, body[body.len - 1]);
}
