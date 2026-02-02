//! WebAssembly bytecode decoder.
//!
//! Decodes raw Wasm bytecode into WasmOperator sequence for translation.
//! Port of wasmtime's wasm-encoder/wasm-parser bytecode reading.

const std = @import("std");
const func_translator = @import("func_translator.zig");

pub const WasmOperator = func_translator.WasmOperator;
pub const BlockData = func_translator.BlockData;
pub const BrTableData = func_translator.BrTableData;
pub const WasmValType = func_translator.WasmValType;

/// Wasm block type (void or value type).
pub const BlockType = union(enum) {
    empty,
    val_type: WasmValType,
    type_index: u32,
};

pub const DecodeError = error{
    UnexpectedEnd,
    InvalidOpcode,
    OutOfMemory,
};

/// Decode a sequence of Wasm operators from bytecode.
pub const Decoder = struct {
    allocator: std.mem.Allocator,
    bytes: []const u8,
    pos: usize,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, bytes: []const u8) Self {
        return .{
            .allocator = allocator,
            .bytes = bytes,
            .pos = 0,
        };
    }

    /// Decode all operators from the bytecode.
    pub fn decodeAll(self: *Self) ![]WasmOperator {
        var operators = std.ArrayListUnmanaged(WasmOperator){};
        errdefer operators.deinit(self.allocator);

        while (self.pos < self.bytes.len) {
            const op = try self.decodeOne();
            try operators.append(self.allocator, op);

            // End opcode terminates function body
            if (op == .end and operators.items.len > 0) {
                // Check if we're at function end (control stack would be empty)
                // For simplicity, continue until all bytes consumed
            }
        }

        return operators.toOwnedSlice(self.allocator);
    }

    /// Decode a single operator.
    pub fn decodeOne(self: *Self) !WasmOperator {
        const opcode = self.readByte() orelse return DecodeError.UnexpectedEnd;

        return switch (opcode) {
            // Control flow
            0x00 => .unreachable_op,
            0x01 => .nop,
            0x02 => blk: {
                const bt = try self.readBlockType();
                break :blk .{ .block = blockTypeToData(bt) };
            },
            0x03 => blk: {
                const bt = try self.readBlockType();
                break :blk .{ .loop = blockTypeToData(bt) };
            },
            0x04 => blk: {
                const bt = try self.readBlockType();
                break :blk .{ .if_op = blockTypeToData(bt) };
            },
            0x05 => .else_op,
            0x0B => .end,
            0x0C => .{ .br = @intCast(self.readULEB128()) },
            0x0D => .{ .br_if = @intCast(self.readULEB128()) },
            0x0E => blk: {
                // br_table: read count, then targets, then default
                const count = self.readULEB128();
                var targets = try self.allocator.alloc(u32, @intCast(count));
                for (0..@intCast(count)) |i| {
                    targets[i] = @intCast(self.readULEB128());
                }
                const default: u32 = @intCast(self.readULEB128());
                break :blk .{ .br_table = .{ .targets = targets, .default = default } };
            },
            0x0F => .return_op,

            // Parametric
            0x1A => .drop,
            0x1B => .select,

            // Variable
            0x20 => .{ .local_get = @intCast(self.readULEB128()) },
            0x21 => .{ .local_set = @intCast(self.readULEB128()) },
            0x22 => .{ .local_tee = @intCast(self.readULEB128()) },

            // Constants
            0x41 => .{ .i32_const = self.readSLEB128i32() },
            0x42 => .{ .i64_const = self.readSLEB128() },

            // Comparison i32
            0x45 => .i32_eqz,
            0x46 => .i32_eq,
            0x47 => .i32_ne,
            0x48 => .i32_lt_s,
            0x49 => .i32_lt_u,
            0x4A => .i32_gt_s,
            0x4B => .i32_gt_u,
            0x4C => .i32_le_s,
            0x4D => .i32_le_u,
            0x4E => .i32_ge_s,
            0x4F => .i32_ge_u,

            // Numeric i32
            0x6A => .i32_add,
            0x6B => .i32_sub,
            0x6C => .i32_mul,
            0x6D => .i32_div_s,
            0x6E => .i32_div_u,
            0x6F => .i32_rem_s,
            0x70 => .i32_rem_u,
            0x71 => .i32_and,
            0x72 => .i32_or,
            0x73 => .i32_xor,
            0x74 => .i32_shl,
            0x75 => .i32_shr_s,
            0x76 => .i32_shr_u,
            0x77 => .i32_rotl,
            0x78 => .i32_rotr,

            // Conversions
            0xA7 => .i32_wrap_i64,
            0xAC => .i64_extend_i32_s,
            0xAD => .i64_extend_i32_u,

            else => {
                // Skip unknown opcodes for now
                return DecodeError.InvalidOpcode;
            },
        };
    }

    fn readByte(self: *Self) ?u8 {
        if (self.pos >= self.bytes.len) return null;
        const b = self.bytes[self.pos];
        self.pos += 1;
        return b;
    }

    fn readULEB128(self: *Self) u64 {
        var result: u64 = 0;
        var shift: u6 = 0;
        while (true) {
            const byte = self.readByte() orelse break;
            result |= @as(u64, byte & 0x7F) << shift;
            if (byte & 0x80 == 0) break;
            shift += 7;
        }
        return result;
    }

    fn readSLEB128(self: *Self) i64 {
        var result: i64 = 0;
        var shift: u6 = 0;
        var byte: u8 = 0;
        while (true) {
            byte = self.readByte() orelse break;
            result |= @as(i64, byte & 0x7F) << shift;
            shift += 7;
            if (byte & 0x80 == 0) break;
        }
        // Sign extend
        if (shift < 64 and (byte & 0x40) != 0) {
            result |= @as(i64, -1) << shift;
        }
        return result;
    }

    fn readSLEB128i32(self: *Self) i32 {
        return @truncate(self.readSLEB128());
    }

    fn readBlockType(self: *Self) !BlockType {
        const byte = self.readByte() orelse return DecodeError.UnexpectedEnd;
        return switch (byte) {
            0x40 => .empty,
            0x7F => .{ .val_type = .i32 },
            0x7E => .{ .val_type = .i64 },
            0x7D => .{ .val_type = .f32 },
            0x7C => .{ .val_type = .f64 },
            0x7B => .{ .val_type = .v128 },
            0x70 => .{ .val_type = .funcref },
            0x6F => .{ .val_type = .externref },
            else => blk: {
                // Treat as type index (LEB128)
                self.pos -= 1; // Unread the byte
                const idx = self.readULEB128();
                break :blk .{ .type_index = @intCast(idx) };
            },
        };
    }
};

fn blockTypeToData(bt: BlockType) BlockData {
    return switch (bt) {
        .empty => .{ .params = 0, .results = 0 },
        .val_type => .{ .params = 0, .results = 1 },
        .type_index => .{ .params = 0, .results = 1 }, // Simplified
    };
}

// ============================================================================
// Tests
// ============================================================================

test "decode i32.const" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // i32.const 42
    const bytes = [_]u8{ 0x41, 0x2A };
    var decoder = Decoder.init(allocator, &bytes);

    const op = try decoder.decodeOne();
    try testing.expectEqual(WasmOperator{ .i32_const = 42 }, op);
}

test "decode i32.add" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const bytes = [_]u8{0x6A};
    var decoder = Decoder.init(allocator, &bytes);

    const op = try decoder.decodeOne();
    try testing.expectEqual(WasmOperator.i32_add, op);
}

test "decode local.get" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // local.get 0
    const bytes = [_]u8{ 0x20, 0x00 };
    var decoder = Decoder.init(allocator, &bytes);

    const op = try decoder.decodeOne();
    try testing.expectEqual(WasmOperator{ .local_get = 0 }, op);
}

test "decode block and end" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // block (result i32) ... end
    const bytes = [_]u8{ 0x02, 0x7F, 0x41, 0x2A, 0x0B };
    var decoder = Decoder.init(allocator, &bytes);

    const ops = try decoder.decodeAll();
    defer allocator.free(ops);

    try testing.expectEqual(@as(usize, 3), ops.len);
    try testing.expectEqual(BlockData{ .params = 0, .results = 1 }, ops[0].block);
    try testing.expectEqual(WasmOperator{ .i32_const = 42 }, ops[1]);
    try testing.expectEqual(WasmOperator.end, ops[2]);
}

test "decode simple function: add two params" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // local.get 0, local.get 1, i32.add, end
    const bytes = [_]u8{
        0x20, 0x00, // local.get 0
        0x20, 0x01, // local.get 1
        0x6A, // i32.add
        0x0B, // end
    };
    var decoder = Decoder.init(allocator, &bytes);

    const ops = try decoder.decodeAll();
    defer allocator.free(ops);

    try testing.expectEqual(@as(usize, 4), ops.len);
    try testing.expectEqual(WasmOperator{ .local_get = 0 }, ops[0]);
    try testing.expectEqual(WasmOperator{ .local_get = 1 }, ops[1]);
    try testing.expectEqual(WasmOperator.i32_add, ops[2]);
    try testing.expectEqual(WasmOperator.end, ops[3]);
}
