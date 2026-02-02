//! Bridge from FuncTranslator output to CLIF Function.
//!
//! Converts the EmittedInst sequence from the translator to a proper
//! CLIF Function that can be lowered to native code.

const std = @import("std");
const clif = @import("../../../ir/clif/mod.zig");
const translator_mod = @import("translator.zig");
const func_translator_mod = @import("func_translator.zig");

pub const ClifOpcode = translator_mod.ClifOpcode;
pub const IntCC = translator_mod.IntCC;
pub const EmittedInst = translator_mod.Translator.EmittedInst;
pub const Value = translator_mod.Value;
pub const Block = translator_mod.Block;

/// Build a CLIF Function from translated instructions.
pub const ClifBuilder = struct {
    allocator: std.mem.Allocator,
    func: clif.Function,
    value_map: std.AutoHashMapUnmanaged(u32, clif.Value),
    block_map: std.AutoHashMapUnmanaged(u32, clif.Block),
    /// Store immediate values for iconst instructions
    immediates: std.ArrayListUnmanaged(i64),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .func = clif.Function.init(allocator),
            .value_map = .{},
            .block_map = .{},
            .immediates = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.func.deinit();
        self.value_map.deinit(self.allocator);
        self.block_map.deinit(self.allocator);
        self.immediates.deinit(self.allocator);
    }

    /// Build from a list of emitted instructions.
    pub fn build(self: *Self, instructions: []const EmittedInst, result_type: clif.Type) !*clif.Function {
        // Create entry block
        const entry_block = try self.func.dfg.makeBlock();
        try self.func.layout.appendBlock(self.allocator, entry_block);

        // Map block 0 to entry
        try self.block_map.put(self.allocator, 0, entry_block);

        // Process instructions
        for (instructions) |inst| {
            try self.emitInstruction(inst, result_type, entry_block);
        }

        return &self.func;
    }

    fn emitInstruction(self: *Self, inst: EmittedInst, result_type: clif.Type, entry_block: clif.Block) !void {
        switch (inst.opcode) {
            .iconst => {
                // Store immediate value
                const imm_idx = self.immediates.items.len;
                try self.immediates.append(self.allocator, inst.imm);

                // Create instruction
                const clif_inst = try self.func.dfg.makeInstWithData(.{
                    .opcode = .iconst,
                    .args = clif.ValueList.EMPTY,
                    .ctrl_type = result_type,
                });

                // Store the immediate index in the instruction (using a reserved mechanism)
                // For now, we'll track it separately
                _ = imm_idx;

                // Append to entry block
                try self.func.layout.appendInst(self.allocator, clif_inst, entry_block);

                // Create result value
                const clif_value = try self.func.dfg.makeInstResult(clif_inst, result_type);

                if (inst.result) |result| {
                    try self.value_map.put(self.allocator, result.asU32(), clif_value);
                }
            },

            .iadd, .isub, .imul, .sdiv, .udiv, .srem, .urem,
            .band, .bor, .bxor, .ishl, .ushr, .sshr,
            => {
                const opcode = clifOpcodeFromTranslator(inst.opcode);
                const args = inst.args;

                if (args[0] != null and args[1] != null) {
                    const arg0 = self.mapValue(args[0].?);
                    const arg1 = self.mapValue(args[1].?);

                    // Build args list
                    var args_list = clif.ValueList.EMPTY;
                    args_list = try self.func.dfg.value_lists.push(args_list, arg0);
                    args_list = try self.func.dfg.value_lists.push(args_list, arg1);

                    const clif_inst = try self.func.dfg.makeInstWithData(.{
                        .opcode = opcode,
                        .args = args_list,
                        .ctrl_type = result_type,
                    });

                    try self.func.layout.appendInst(self.allocator, clif_inst, entry_block);

                    const clif_value = try self.func.dfg.makeInstResult(clif_inst, result_type);

                    if (inst.result) |result| {
                        try self.value_map.put(self.allocator, result.asU32(), clif_value);
                    }
                }
            },

            .icmp => {
                const args = inst.args;
                if (args[0] != null and args[1] != null) {
                    const arg0 = self.mapValue(args[0].?);
                    const arg1 = self.mapValue(args[1].?);

                    var args_list = clif.ValueList.EMPTY;
                    args_list = try self.func.dfg.value_lists.push(args_list, arg0);
                    args_list = try self.func.dfg.value_lists.push(args_list, arg1);

                    const clif_inst = try self.func.dfg.makeInstWithData(.{
                        .opcode = .icmp,
                        .args = args_list,
                        .ctrl_type = clif.Type.I8, // Boolean result
                    });

                    try self.func.layout.appendInst(self.allocator, clif_inst, entry_block);

                    const clif_value = try self.func.dfg.makeInstResult(clif_inst, clif.Type.I8);

                    if (inst.result) |result| {
                        try self.value_map.put(self.allocator, result.asU32(), clif_value);
                    }
                }
            },

            .jump => {
                if (inst.block_target) |target| {
                    const dest = try self.getOrCreateBlock(target.asU32());

                    const clif_inst = try self.func.dfg.makeInstWithData(.{
                        .opcode = .jump,
                        .args = clif.ValueList.EMPTY,
                        .ctrl_type = clif.Type.INVALID,
                    });

                    try self.func.layout.appendInst(self.allocator, clif_inst, entry_block);
                    _ = dest;
                }
            },

            .brif => {
                const args = inst.args;
                if (args[0] != null) {
                    const cond_val = self.mapValue(args[0].?);

                    var args_list = clif.ValueList.EMPTY;
                    args_list = try self.func.dfg.value_lists.push(args_list, cond_val);

                    const clif_inst = try self.func.dfg.makeInstWithData(.{
                        .opcode = .brif,
                        .args = args_list,
                        .ctrl_type = clif.Type.INVALID,
                    });

                    try self.func.layout.appendInst(self.allocator, clif_inst, entry_block);
                }
            },

            .return_op => {
                const clif_inst = try self.func.dfg.makeInstWithData(.{
                    .opcode = .@"return",
                    .args = clif.ValueList.EMPTY,
                    .ctrl_type = clif.Type.INVALID,
                });

                try self.func.layout.appendInst(self.allocator, clif_inst, entry_block);
            },

            .ireduce, .sextend, .uextend => {
                const opcode = clifOpcodeFromTranslator(inst.opcode);
                const args = inst.args;

                if (args[0] != null) {
                    const arg0 = self.mapValue(args[0].?);

                    var args_list = clif.ValueList.EMPTY;
                    args_list = try self.func.dfg.value_lists.push(args_list, arg0);

                    const clif_inst = try self.func.dfg.makeInstWithData(.{
                        .opcode = opcode,
                        .args = args_list,
                        .ctrl_type = result_type,
                    });

                    try self.func.layout.appendInst(self.allocator, clif_inst, entry_block);

                    const clif_value = try self.func.dfg.makeInstResult(clif_inst, result_type);

                    if (inst.result) |result| {
                        try self.value_map.put(self.allocator, result.asU32(), clif_value);
                    }
                }
            },

            .select => {
                const args = inst.args;
                if (args[0] != null and args[1] != null and args[2] != null) {
                    const arg0 = self.mapValue(args[0].?);
                    const arg1 = self.mapValue(args[1].?);
                    const arg2 = self.mapValue(args[2].?);

                    var args_list = clif.ValueList.EMPTY;
                    args_list = try self.func.dfg.value_lists.push(args_list, arg0);
                    args_list = try self.func.dfg.value_lists.push(args_list, arg1);
                    args_list = try self.func.dfg.value_lists.push(args_list, arg2);

                    const clif_inst = try self.func.dfg.makeInstWithData(.{
                        .opcode = .select,
                        .args = args_list,
                        .ctrl_type = result_type,
                    });

                    try self.func.layout.appendInst(self.allocator, clif_inst, entry_block);

                    const clif_value = try self.func.dfg.makeInstResult(clif_inst, result_type);

                    if (inst.result) |result| {
                        try self.value_map.put(self.allocator, result.asU32(), clif_value);
                    }
                }
            },

            // Other opcodes are no-ops for now
            else => {},
        }
    }

    fn mapValue(self: *Self, val: Value) clif.Value {
        return self.value_map.get(val.asU32()) orelse clif.Value.fromIndex(val.asU32());
    }

    fn getOrCreateBlock(self: *Self, idx: u32) !clif.Block {
        if (self.block_map.get(idx)) |b| {
            return b;
        }

        const new_block = try self.func.dfg.makeBlock();
        try self.block_map.put(self.allocator, idx, new_block);
        try self.func.layout.appendBlock(self.allocator, new_block);
        return new_block;
    }

    /// Get the immediate value for an iconst instruction.
    pub fn getImmediate(self: *const Self, idx: usize) ?i64 {
        if (idx < self.immediates.items.len) {
            return self.immediates.items[idx];
        }
        return null;
    }
};

fn clifOpcodeFromTranslator(op: ClifOpcode) clif.Opcode {
    return switch (op) {
        .iconst => .iconst,
        .iadd => .iadd,
        .isub => .isub,
        .imul => .imul,
        .sdiv => .sdiv,
        .udiv => .udiv,
        .srem => .srem,
        .urem => .urem,
        .band => .band,
        .bor => .bor,
        .bxor => .bxor,
        .ishl => .ishl,
        .ushr => .ushr,
        .sshr => .sshr,
        .icmp => .icmp,
        .jump => .jump,
        .brif => .brif,
        .return_op => .@"return",
        .ireduce => .ireduce,
        .sextend => .sextend,
        .uextend => .uextend,
        .select => .select,
        else => .nop,
    };
}

fn mapIntCC(cc: IntCC) clif.IntCC {
    return switch (cc) {
        .equal => .eq,
        .not_equal => .ne,
        .signed_less_than => .slt,
        .signed_greater_than_or_equal => .sge,
        .signed_greater_than => .sgt,
        .signed_less_than_or_equal => .sle,
        .unsigned_less_than => .ult,
        .unsigned_greater_than_or_equal => .uge,
        .unsigned_greater_than => .ugt,
        .unsigned_less_than_or_equal => .ule,
    };
}

// ============================================================================
// Tests
// ============================================================================

test "build simple iconst" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var builder = ClifBuilder.init(allocator);
    defer builder.deinit();

    const instructions = [_]EmittedInst{
        .{
            .opcode = .iconst,
            .result = Value.fromIndex(0),
            .args = .{ null, null, null },
            .imm = 42,
            .block_target = null,
            .cond = null,
        },
    };

    _ = try builder.build(&instructions, clif.Type.I32);

    // Should have entry block
    try testing.expect(builder.func.layout.entryBlock() != null);
}
