//! Wasm to CLIF code translator.
//!
//! Port of wasmtime/crates/cranelift/src/translate/code_translator.rs
//!
//! This module translates WebAssembly operators into CLIF IR instructions.
//! The translation is done in one pass, opcode by opcode. Two main data structures
//! are used: the value stack and the control stack.

const std = @import("std");
const stack_mod = @import("stack.zig");

pub const Block = stack_mod.Block;
pub const Value = stack_mod.Value;
pub const Inst = stack_mod.Inst;
pub const TranslationState = stack_mod.TranslationState;
pub const ControlStackFrame = stack_mod.ControlStackFrame;
pub const ElseData = stack_mod.ElseData;

// ============================================================================
// Wasm Opcode
// Subset of Wasm opcodes we translate
// ============================================================================

pub const WasmOpcode = enum(u8) {
    // Control flow
    unreachable_op = 0x00,
    nop = 0x01,
    block = 0x02,
    loop = 0x03,
    if_op = 0x04,
    else_op = 0x05,
    end = 0x0B,
    br = 0x0C,
    br_if = 0x0D,
    br_table = 0x0E,
    return_op = 0x0F,
    call = 0x10,
    call_indirect = 0x11,

    // Parametric
    drop = 0x1A,
    select = 0x1B,

    // Variable
    local_get = 0x20,
    local_set = 0x21,
    local_tee = 0x22,
    global_get = 0x23,
    global_set = 0x24,

    // Memory
    i32_load = 0x28,
    i64_load = 0x29,
    f32_load = 0x2A,
    f64_load = 0x2B,
    i32_load8_s = 0x2C,
    i32_load8_u = 0x2D,
    i32_load16_s = 0x2E,
    i32_load16_u = 0x2F,
    i64_load8_s = 0x30,
    i64_load8_u = 0x31,
    i64_load16_s = 0x32,
    i64_load16_u = 0x33,
    i64_load32_s = 0x34,
    i64_load32_u = 0x35,
    i32_store = 0x36,
    i64_store = 0x37,
    f32_store = 0x38,
    f64_store = 0x39,
    i32_store8 = 0x3A,
    i32_store16 = 0x3B,
    i64_store8 = 0x3C,
    i64_store16 = 0x3D,
    i64_store32 = 0x3E,

    // Constants
    i32_const = 0x41,
    i64_const = 0x42,
    f32_const = 0x43,
    f64_const = 0x44,

    // Comparison
    i32_eqz = 0x45,
    i32_eq = 0x46,
    i32_ne = 0x47,
    i32_lt_s = 0x48,
    i32_lt_u = 0x49,
    i32_gt_s = 0x4A,
    i32_gt_u = 0x4B,
    i32_le_s = 0x4C,
    i32_le_u = 0x4D,
    i32_ge_s = 0x4E,
    i32_ge_u = 0x4F,
    i64_eqz = 0x50,
    i64_eq = 0x51,
    i64_ne = 0x52,
    i64_lt_s = 0x53,
    i64_lt_u = 0x54,
    i64_gt_s = 0x55,
    i64_gt_u = 0x56,
    i64_le_s = 0x57,
    i64_le_u = 0x58,
    i64_ge_s = 0x59,
    i64_ge_u = 0x5A,

    // Numeric i32
    i32_clz = 0x67,
    i32_ctz = 0x68,
    i32_popcnt = 0x69,
    i32_add = 0x6A,
    i32_sub = 0x6B,
    i32_mul = 0x6C,
    i32_div_s = 0x6D,
    i32_div_u = 0x6E,
    i32_rem_s = 0x6F,
    i32_rem_u = 0x70,
    i32_and = 0x71,
    i32_or = 0x72,
    i32_xor = 0x73,
    i32_shl = 0x74,
    i32_shr_s = 0x75,
    i32_shr_u = 0x76,
    i32_rotl = 0x77,
    i32_rotr = 0x78,

    // Numeric i64
    i64_clz = 0x79,
    i64_ctz = 0x7A,
    i64_popcnt = 0x7B,
    i64_add = 0x7C,
    i64_sub = 0x7D,
    i64_mul = 0x7E,
    i64_div_s = 0x7F,
    i64_div_u = 0x80,
    i64_rem_s = 0x81,
    i64_rem_u = 0x82,
    i64_and = 0x83,
    i64_or = 0x84,
    i64_xor = 0x85,
    i64_shl = 0x86,
    i64_shr_s = 0x87,
    i64_shr_u = 0x88,
    i64_rotl = 0x89,
    i64_rotr = 0x8A,

    // Conversions
    i32_wrap_i64 = 0xA7,
    i64_extend_i32_s = 0xAC,
    i64_extend_i32_u = 0xAD,
};

// ============================================================================
// CLIF Opcode
// CLIF IR opcodes that we emit
// ============================================================================

pub const ClifOpcode = enum {
    // Control flow
    jump,
    brif,
    br_table,
    return_op,
    call,
    call_indirect,
    trap,
    trapz,
    trapnz,

    // Constants
    iconst,
    f32const,
    f64const,

    // Integer arithmetic
    iadd,
    isub,
    imul,
    sdiv,
    udiv,
    srem,
    urem,
    ineg,

    // Bitwise
    band,
    bor,
    bxor,
    bnot,
    ishl,
    ushr,
    sshr,
    rotl,
    rotr,
    clz,
    ctz,
    popcnt,

    // Comparison
    icmp,
    fcmp,

    // Memory
    load,
    store,
    stack_load,
    stack_store,

    // Conversions
    uextend,
    sextend,
    ireduce,

    // Other
    copy,
    select,
    nop,
};

// ============================================================================
// Integer Comparison Condition
// ============================================================================

pub const IntCC = enum {
    equal,
    not_equal,
    signed_less_than,
    signed_greater_than_or_equal,
    signed_greater_than,
    signed_less_than_or_equal,
    unsigned_less_than,
    unsigned_greater_than_or_equal,
    unsigned_greater_than,
    unsigned_less_than_or_equal,
};

// ============================================================================
// JumpTableEntry
// For br_table edge splitting
// ============================================================================

pub const JumpTableEntry = struct {
    depth: u32,
    block: Block,
};

// ============================================================================
// Translator
// Main translation context
// ============================================================================

pub const Translator = struct {
    /// Translation state (value stack, control stack, reachability).
    state: TranslationState,
    /// Allocator for dynamic storage.
    allocator: std.mem.Allocator,
    /// Next block index to allocate.
    next_block: u32,
    /// Next value index to allocate.
    next_value: u32,
    /// Local variable values (indexed by local index).
    locals: std.ArrayListUnmanaged(Value),
    /// Emitted instructions (for testing/debugging).
    instructions: std.ArrayListUnmanaged(EmittedInst),

    const Self = @This();

    /// An emitted instruction (for recording what was translated).
    pub const EmittedInst = struct {
        opcode: ClifOpcode,
        result: ?Value,
        args: [3]?Value,
        imm: i64,
        block_target: ?Block,
        cond: ?IntCC,
    };

    /// Create a new translator.
    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .state = TranslationState.init(allocator),
            .allocator = allocator,
            .next_block = 0,
            .next_value = 0,
            .locals = .{},
            .instructions = .{},
        };
    }

    /// Deallocate storage.
    pub fn deinit(self: *Self) void {
        self.state.deinit();
        self.locals.deinit(self.allocator);
        self.instructions.deinit(self.allocator);
    }

    /// Create a new block.
    pub fn createBlock(self: *Self) Block {
        const b = Block.fromIndex(self.next_block);
        self.next_block += 1;
        return b;
    }

    /// Create a new value.
    pub fn createValue(self: *Self) Value {
        const v = Value.fromIndex(self.next_value);
        self.next_value += 1;
        return v;
    }

    /// Initialize for translating a function.
    pub fn initializeFunction(self: *Self, num_locals: u32, num_returns: usize) !void {
        // Create exit block
        const exit_block = self.createBlock();
        try self.state.initialize(exit_block, num_returns);

        // Initialize locals
        self.locals.clearRetainingCapacity();
        try self.locals.ensureTotalCapacity(self.allocator, num_locals);
        for (0..num_locals) |_| {
            // Each local starts as an undefined value
            self.locals.appendAssumeCapacity(self.createValue());
        }
    }

    /// Emit an instruction and return its result value.
    fn emit(self: *Self, opcode: ClifOpcode, args: [3]?Value, imm: i64, block_target: ?Block, cond: ?IntCC) !Value {
        const result = self.createValue();
        try self.instructions.append(self.allocator, .{
            .opcode = opcode,
            .result = result,
            .args = args,
            .imm = imm,
            .block_target = block_target,
            .cond = cond,
        });
        return result;
    }

    /// Emit an instruction with no result.
    pub fn emitVoid(self: *Self, opcode: ClifOpcode, args: [3]?Value, imm: i64, block_target: ?Block, cond: ?IntCC) !void {
        try self.instructions.append(self.allocator, .{
            .opcode = opcode,
            .result = null,
            .args = args,
            .imm = imm,
            .block_target = block_target,
            .cond = cond,
        });
    }

    // ========================================================================
    // Control Flow Translation
    // ========================================================================

    /// Translate a block instruction.
    pub fn translateBlock(self: *Self, num_params: usize, num_results: usize) !void {
        const next = self.createBlock();
        try self.state.pushBlock(next, num_params, num_results);
    }

    /// Translate a loop instruction.
    pub fn translateLoop(self: *Self, num_params: usize, num_results: usize) !void {
        const loop_body = self.createBlock();
        const next = self.createBlock();

        // Jump to loop header with current params
        const params = self.state.peekn(num_params);
        try self.emitVoid(.jump, .{ null, null, null }, 0, loop_body, null);
        _ = params;

        try self.state.pushLoop(loop_body, next, num_params, num_results);

        // Pop and replace with block params
        self.state.popn(num_params);
        // In real translation, we'd get block params here
        for (0..num_params) |_| {
            try self.state.push1(self.createValue());
        }
    }

    /// Translate an if instruction.
    pub fn translateIf(self: *Self, num_params: usize, num_results: usize) !void {
        const condition = self.state.pop1();

        const next_block = self.createBlock();
        const destination = self.createBlock();

        // Emit conditional branch
        // If params == results, we might not have an else
        const else_data = if (num_params == num_results) blk: {
            // Branch: if true -> next_block, if false -> destination
            try self.emitVoid(.brif, .{ condition, null, null }, 0, destination, null);
            break :blk ElseData{ .no_else = .{
                .branch_inst = Inst.fromIndex(@intCast(self.instructions.items.len - 1)),
                .placeholder = destination,
            } };
        } else blk: {
            // Must have an else, pre-allocate it
            const else_block = self.createBlock();
            try self.emitVoid(.brif, .{ condition, null, null }, 0, else_block, null);
            break :blk ElseData{ .with_else = .{ .else_block = else_block } };
        };

        try self.state.pushIf(destination, else_data, num_params, num_results);
        _ = next_block;
    }

    /// Translate an else instruction.
    pub fn translateElse(self: *Self) !void {
        const frame = self.state.getFrameMut(0);
        switch (frame.*) {
            .if_frame => |*f| {
                // Record that consequent is ending
                f.consequent_ends_reachable = self.state.reachable;

                if (f.head_is_reachable) {
                    self.state.reachable = true;

                    // Jump to destination
                    try self.emitVoid(.jump, .{ null, null, null }, 0, f.destination, null);

                    // Pop return values
                    self.state.popn(f.num_return_values);
                }
            },
            else => unreachable,
        }
    }

    /// Translate an end instruction.
    pub fn translateEnd(self: *Self) !void {
        const frame = self.state.popFrame();
        const next_block = frame.followingCode();
        const return_count = frame.numReturnValues();

        // Jump to next block with return values
        try self.emitVoid(.jump, .{ null, null, null }, 0, next_block, null);

        // Truncate stack to original size
        frame.truncateValueStackToOriginalSize(&self.state.stack);

        // Push block results
        for (0..return_count) |_| {
            try self.state.push1(self.createValue());
        }
    }

    /// Translate a br instruction.
    pub fn translateBr(self: *Self, relative_depth: u32) !void {
        const frame = self.state.getFrameMut(relative_depth);
        frame.setBranchedToExit();

        const return_count = if (frame.isLoop())
            frame.numParamValues()
        else
            frame.numReturnValues();

        const destination = frame.brDestination();

        // Get args and jump
        _ = self.state.peekn(return_count);
        try self.emitVoid(.jump, .{ null, null, null }, 0, destination, null);

        self.state.popn(return_count);
        self.state.reachable = false;
    }

    /// Translate a br_if instruction.
    pub fn translateBrIf(self: *Self, relative_depth: u32) !void {
        const condition = self.state.pop1();

        const frame = self.state.getFrameMut(relative_depth);
        frame.setBranchedToExit();

        const return_count = if (frame.isLoop())
            frame.numParamValues()
        else
            frame.numReturnValues();

        const destination = frame.brDestination();

        // Get args for branch
        _ = self.state.peekn(return_count);

        // Emit conditional branch
        try self.emitVoid(.brif, .{ condition, null, null }, 0, destination, null);
        // Values stay on stack (branch is conditional)
    }

    /// Translate a br_table instruction.
    /// This is the CRITICAL algorithm from Cranelift.
    pub fn translateBrTable(self: *Self, targets: []const u32, default: u32) !void {
        const val = self.state.pop1();

        // 1. Compute minimum depth to determine jump args count
        var min_depth = default;
        for (targets) |depth| {
            if (depth < min_depth) {
                min_depth = depth;
            }
        }

        // 2. Get return count from min depth frame
        const min_depth_frame = self.state.getFrame(min_depth);
        const jump_args_count = if (min_depth_frame.isLoop())
            min_depth_frame.numParamValues()
        else
            min_depth_frame.numReturnValues();

        if (jump_args_count == 0) {
            // Simple case: no jump arguments, direct br_table
            for (targets) |depth| {
                const frame = self.state.getFrameMut(depth);
                frame.setBranchedToExit();
            }
            const default_frame = self.state.getFrameMut(default);
            default_frame.setBranchedToExit();

            try self.emitVoid(.br_table, .{ val, null, null }, 0, null, null);
        } else {
            // Edge splitting: create intermediate blocks
            var dest_block_map = std.AutoHashMap(u32, Block).init(self.allocator);
            defer dest_block_map.deinit();

            var dest_block_sequence: std.ArrayListUnmanaged(JumpTableEntry) = .{};
            defer dest_block_sequence.deinit(self.allocator);

            // Create intermediate blocks for each unique depth
            for (targets) |depth| {
                const result = try dest_block_map.getOrPut(depth);
                if (!result.found_existing) {
                    const block = self.createBlock();
                    result.value_ptr.* = block;
                    try dest_block_sequence.append(self.allocator, .{ .depth = depth, .block = block });
                }
            }

            // Handle default
            const default_result = try dest_block_map.getOrPut(default);
            if (!default_result.found_existing) {
                const block = self.createBlock();
                default_result.value_ptr.* = block;
                try dest_block_sequence.append(self.allocator, .{ .depth = default, .block = block });
            }

            // Emit br_table to intermediates
            try self.emitVoid(.br_table, .{ val, null, null }, 0, null, null);

            // Fill intermediate blocks with jumps to real targets
            for (dest_block_sequence.items) |entry| {
                const real_frame = self.state.getFrameMut(entry.depth);
                real_frame.setBranchedToExit();
                const real_dest = real_frame.brDestination();

                // Emit jump from intermediate to real destination
                try self.emitVoid(.jump, .{ null, null, null }, 0, real_dest, null);
            }

            self.state.popn(jump_args_count);
        }

        self.state.reachable = false;
    }

    /// Translate a return instruction.
    pub fn translateReturn(self: *Self) !void {
        // The function frame is always at index 0
        if (self.state.controlStackLen() == 0) {
            // No control frames - just emit return
            try self.emitVoid(.return_op, .{ null, null, null }, 0, null, null);
            self.state.reachable = false;
            return;
        }

        // Get function frame (bottom of control stack)
        const func_frame_idx = self.state.controlStackLen() - 1;
        var frame_idx: u32 = 0;
        while (frame_idx < func_frame_idx) : (frame_idx += 1) {}
        // Access frame 0 which is the function frame
        const frame = &self.state.control_stack.items[0];
        const return_count = frame.numReturnValues();

        _ = self.state.peekn(return_count);
        try self.emitVoid(.return_op, .{ null, null, null }, 0, null, null);

        self.state.popn(return_count);
        self.state.reachable = false;
    }

    // ========================================================================
    // Local Variable Translation
    // ========================================================================

    /// Translate local.get
    pub fn translateLocalGet(self: *Self, local_index: u32) !void {
        const val = self.locals.items[local_index];
        try self.state.push1(val);
    }

    /// Translate local.set
    pub fn translateLocalSet(self: *Self, local_index: u32) !void {
        const val = self.state.pop1();
        self.locals.items[local_index] = val;
    }

    /// Translate local.tee
    pub fn translateLocalTee(self: *Self, local_index: u32) !void {
        const val = self.state.peek1();
        self.locals.items[local_index] = val;
    }

    // ========================================================================
    // Constant Translation
    // ========================================================================

    /// Translate i32.const
    pub fn translateI32Const(self: *Self, value: i32) !void {
        const result = try self.emit(.iconst, .{ null, null, null }, value, null, null);
        try self.state.push1(result);
    }

    /// Translate i64.const
    pub fn translateI64Const(self: *Self, value: i64) !void {
        const result = try self.emit(.iconst, .{ null, null, null }, value, null, null);
        try self.state.push1(result);
    }

    // ========================================================================
    // Binary Arithmetic Translation
    // ========================================================================

    fn translateBinaryOp(self: *Self, opcode: ClifOpcode) !void {
        const args = self.state.pop2();
        const result = try self.emit(opcode, .{ args[0], args[1], null }, 0, null, null);
        try self.state.push1(result);
    }

    pub fn translateI32Add(self: *Self) !void {
        try self.translateBinaryOp(.iadd);
    }

    pub fn translateI32Sub(self: *Self) !void {
        try self.translateBinaryOp(.isub);
    }

    pub fn translateI32Mul(self: *Self) !void {
        try self.translateBinaryOp(.imul);
    }

    pub fn translateI32DivS(self: *Self) !void {
        try self.translateBinaryOp(.sdiv);
    }

    pub fn translateI32DivU(self: *Self) !void {
        try self.translateBinaryOp(.udiv);
    }

    pub fn translateI32RemS(self: *Self) !void {
        try self.translateBinaryOp(.srem);
    }

    pub fn translateI32RemU(self: *Self) !void {
        try self.translateBinaryOp(.urem);
    }

    pub fn translateI32And(self: *Self) !void {
        try self.translateBinaryOp(.band);
    }

    pub fn translateI32Or(self: *Self) !void {
        try self.translateBinaryOp(.bor);
    }

    pub fn translateI32Xor(self: *Self) !void {
        try self.translateBinaryOp(.bxor);
    }

    pub fn translateI32Shl(self: *Self) !void {
        try self.translateBinaryOp(.ishl);
    }

    pub fn translateI32ShrS(self: *Self) !void {
        try self.translateBinaryOp(.sshr);
    }

    pub fn translateI32ShrU(self: *Self) !void {
        try self.translateBinaryOp(.ushr);
    }

    pub fn translateI32Rotl(self: *Self) !void {
        try self.translateBinaryOp(.rotl);
    }

    pub fn translateI32Rotr(self: *Self) !void {
        try self.translateBinaryOp(.rotr);
    }

    // ========================================================================
    // Comparison Translation
    // ========================================================================

    fn translateCompare(self: *Self, cond: IntCC) !void {
        const args = self.state.pop2();
        const result = try self.emit(.icmp, .{ args[0], args[1], null }, 0, null, cond);
        try self.state.push1(result);
    }

    pub fn translateI32Eq(self: *Self) !void {
        try self.translateCompare(.equal);
    }

    pub fn translateI32Ne(self: *Self) !void {
        try self.translateCompare(.not_equal);
    }

    pub fn translateI32LtS(self: *Self) !void {
        try self.translateCompare(.signed_less_than);
    }

    pub fn translateI32LtU(self: *Self) !void {
        try self.translateCompare(.unsigned_less_than);
    }

    pub fn translateI32GtS(self: *Self) !void {
        try self.translateCompare(.signed_greater_than);
    }

    pub fn translateI32GtU(self: *Self) !void {
        try self.translateCompare(.unsigned_greater_than);
    }

    pub fn translateI32LeS(self: *Self) !void {
        try self.translateCompare(.signed_less_than_or_equal);
    }

    pub fn translateI32LeU(self: *Self) !void {
        try self.translateCompare(.unsigned_less_than_or_equal);
    }

    pub fn translateI32GeS(self: *Self) !void {
        try self.translateCompare(.signed_greater_than_or_equal);
    }

    pub fn translateI32GeU(self: *Self) !void {
        try self.translateCompare(.unsigned_greater_than_or_equal);
    }

    /// Translate i32.eqz (compare equal to zero)
    pub fn translateI32Eqz(self: *Self) !void {
        const arg = self.state.pop1();
        const zero = try self.emit(.iconst, .{ null, null, null }, 0, null, null);
        const result = try self.emit(.icmp, .{ arg, zero, null }, 0, null, .equal);
        try self.state.push1(result);
    }

    // ========================================================================
    // Conversion Translation
    // ========================================================================

    pub fn translateI32WrapI64(self: *Self) !void {
        const arg = self.state.pop1();
        const result = try self.emit(.ireduce, .{ arg, null, null }, 0, null, null);
        try self.state.push1(result);
    }

    pub fn translateI64ExtendI32S(self: *Self) !void {
        const arg = self.state.pop1();
        const result = try self.emit(.sextend, .{ arg, null, null }, 0, null, null);
        try self.state.push1(result);
    }

    pub fn translateI64ExtendI32U(self: *Self) !void {
        const arg = self.state.pop1();
        const result = try self.emit(.uextend, .{ arg, null, null }, 0, null, null);
        try self.state.push1(result);
    }

    // ========================================================================
    // Parametric Translation
    // ========================================================================

    pub fn translateDrop(self: *Self) !void {
        _ = self.state.pop1();
    }

    pub fn translateSelect(self: *Self) !void {
        const args = self.state.pop3();
        const result = try self.emit(.select, .{ args[0], args[1], args[2] }, 0, null, null);
        try self.state.push1(result);
    }
};

// ============================================================================
// Tests
// ============================================================================

test "translate i32.const and i32.add" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var translator = Translator.init(allocator);
    defer translator.deinit();

    try translator.initializeFunction(0, 1);

    try translator.translateI32Const(10);
    try translator.translateI32Const(20);
    try translator.translateI32Add();

    try testing.expectEqual(@as(usize, 1), translator.state.stackLen());
    try testing.expectEqual(@as(usize, 3), translator.instructions.items.len);

    // Check instructions
    try testing.expectEqual(ClifOpcode.iconst, translator.instructions.items[0].opcode);
    try testing.expectEqual(ClifOpcode.iconst, translator.instructions.items[1].opcode);
    try testing.expectEqual(ClifOpcode.iadd, translator.instructions.items[2].opcode);
}

test "translate block and end" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var translator = Translator.init(allocator);
    defer translator.deinit();

    try translator.initializeFunction(0, 0);

    try testing.expectEqual(@as(usize, 1), translator.state.controlStackLen());

    try translator.translateBlock(0, 0);
    try testing.expectEqual(@as(usize, 2), translator.state.controlStackLen());

    try translator.translateEnd();
    try testing.expectEqual(@as(usize, 1), translator.state.controlStackLen());
}

test "translate loop - br_destination is header" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var translator = Translator.init(allocator);
    defer translator.deinit();

    try translator.initializeFunction(0, 0);

    try translator.translateLoop(0, 0);

    const frame = translator.state.getFrame(0);
    try testing.expect(frame.isLoop());

    // For loop, br_destination should be header (not exit)
    // header is the first block created for the loop
    // exit is the second block
    const header = frame.brDestination();
    const exit = frame.followingCode();
    try testing.expect(header.asU32() != exit.asU32());
}

test "translate br" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var translator = Translator.init(allocator);
    defer translator.deinit();

    try translator.initializeFunction(0, 0);
    try translator.translateBlock(0, 0);

    try translator.translateBr(0);

    try testing.expect(!translator.state.reachable);
}

test "translate local.get and local.set" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var translator = Translator.init(allocator);
    defer translator.deinit();

    try translator.initializeFunction(2, 0);

    // local.set 0
    try translator.translateI32Const(42);
    try translator.translateLocalSet(0);

    // local.get 0
    try translator.translateLocalGet(0);

    try testing.expectEqual(@as(usize, 1), translator.state.stackLen());
}

test "translate br_table simple (no args)" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var translator = Translator.init(allocator);
    defer translator.deinit();

    try translator.initializeFunction(0, 0);

    // Create some blocks
    try translator.translateBlock(0, 0);
    try translator.translateBlock(0, 0);

    // Push dispatch index
    try translator.translateI32Const(0);

    // br_table with targets [0, 1] and default 0
    try translator.translateBrTable(&[_]u32{ 0, 1 }, 0);

    try testing.expect(!translator.state.reachable);
}

test "translate comparison" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var translator = Translator.init(allocator);
    defer translator.deinit();

    try translator.initializeFunction(0, 0);

    try translator.translateI32Const(10);
    try translator.translateI32Const(20);
    try translator.translateI32LtS();

    try testing.expectEqual(@as(usize, 1), translator.state.stackLen());
    try testing.expectEqual(ClifOpcode.icmp, translator.instructions.items[2].opcode);
    try testing.expectEqual(IntCC.signed_less_than, translator.instructions.items[2].cond.?);
}
