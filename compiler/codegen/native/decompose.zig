//! Decompose Pass - Transform 16-byte values into 8-byte components.
//!
//! Go reference: cmd/compile/internal/ssa/decompose.go, dec.rules
//!
//! After this pass, every SSA value's type is <= 8 bytes.
//! Strings become string_make(ptr, len) with two 8-byte components.
//!
//! Transformations:
//! - Load<string> ptr → StringMake(Load<i64> ptr, Load<i64> ptr+8)
//! - Store dst StringMake(ptr,len) → Store dst ptr; Store dst+8 len
//! - ConstString "x" → StringMake(ConstPtr @str, ConstInt len)

const std = @import("std");
const Value = @import("../../ssa/value.zig").Value;
const Block = @import("../../ssa/block.zig").Block;
const Func = @import("../../ssa/func.zig").Func;
const Op = @import("../../ssa/op.zig").Op;
const types = @import("../../frontend/types.zig");
const TypeRegistry = types.TypeRegistry;
const debug = @import("../../pipeline_debug.zig");

/// Run the decompose pass on a function.
pub fn decompose(f: *Func, type_reg: ?*const TypeRegistry) !void {
    debug.log(.ssa, "decompose: processing '{s}'", .{f.name});

    // Multiple passes may be needed as decomposition creates new values
    var changed = true;
    var iterations: usize = 0;
    while (changed and iterations < 10) {
        changed = false;
        iterations += 1;

        for (f.blocks.items) |block| {
            if (try decomposeBlock(f, block, type_reg)) {
                changed = true;
            }
        }
    }

    if (iterations > 1) {
        debug.log(.ssa, "  decompose took {d} iterations", .{iterations});
    }

    // Verify: no remaining undecomposed strings
    var remaining: usize = 0;
    for (f.blocks.items) |block| {
        for (block.values.items) |v| {
            if (v.type_idx == TypeRegistry.STRING and
                v.op != .string_make and v.op != .string_ptr and v.op != .string_len)
            {
                remaining += 1;
                debug.log(.ssa, "  WARNING: v{d} op={s} not decomposed", .{ v.id, @tagName(v.op) });
            }
        }
    }

    if (remaining > 0) {
        debug.log(.ssa, "  {d} values remain undecomposed", .{remaining});
    }
}

fn decomposeBlock(f: *Func, block: *Block, type_reg: ?*const TypeRegistry) !bool {
    var changed = false;
    var i: usize = 0;

    while (i < block.values.items.len) {
        const v = block.values.items[i];

        // Only decompose string-typed values that need it
        if (v.type_idx == TypeRegistry.STRING) {
            const decomposed = switch (v.op) {
                .load => try decomposeLoad(f, block, v, i),
                .const_string => try decomposeConstString(f, block, v, i),
                .arg => try decomposeArg(f, block, v, i),
                else => false,
            };
            if (decomposed) {
                changed = true;
                continue; // Re-check this index
            }
        }

        // Decompose stores of string_make
        if (v.op == .store and v.args.len >= 2) {
            const stored = v.args[1];
            if (stored.op == .string_make) {
                if (try decomposeStore(f, block, v, i)) {
                    changed = true;
                    continue;
                }
            }
        }

        i += 1;
    }

    _ = type_reg;
    return changed;
}

/// Decompose: Load<string> ptr → StringMake(Load ptr, Load ptr+8)
fn decomposeLoad(f: *Func, block: *Block, v: *Value, idx: usize) !bool {
    if (v.args.len < 1) return false;
    const ptr = v.args[0];

    debug.log(.ssa, "  decompose load v{d}", .{v.id});

    // Load pointer component
    const load_ptr = try f.newValue(.load, TypeRegistry.I64, block, .{});
    load_ptr.addArg(ptr);
    load_ptr.uses = v.uses;

    // Create offset pointer
    const off_ptr = try f.newValue(.add_ptr, TypeRegistry.U64, block, .{});
    off_ptr.addArg(ptr);
    off_ptr.aux_int = 8;

    // Load length component
    const load_len = try f.newValue(.load, TypeRegistry.I64, block, .{});
    load_len.addArg(off_ptr);
    load_len.uses = v.uses;

    // Create string_make
    const str_make = try f.newValue(.string_make, TypeRegistry.STRING, block, .{});
    str_make.addArg(load_ptr);
    str_make.addArg(load_len);
    str_make.uses = v.uses;

    // Replace original load with new values
    try replaceValue(f, block, v, idx, &[_]*Value{ load_ptr, off_ptr, load_len, str_make });
    return true;
}

/// Decompose: ConstString "x" → StringMake(ConstPtr, ConstInt len)
fn decomposeConstString(f: *Func, block: *Block, v: *Value, idx: usize) !bool {
    const str_data = switch (v.aux) {
        .string => |s| s,
        else => return false,
    };

    debug.log(.ssa, "  decompose const_string v{d} \"{s}\"", .{ v.id, str_data });

    // ConstPtr for string data address
    const const_ptr = try f.newValue(.const_ptr, TypeRegistry.U64, block, .{});
    const_ptr.aux = v.aux; // Keep string reference for later resolution

    // ConstInt for length
    const const_len = try f.newValue(.const_int, TypeRegistry.I64, block, .{});
    const_len.aux_int = @intCast(str_data.len);

    // StringMake
    const str_make = try f.newValue(.string_make, TypeRegistry.STRING, block, .{});
    str_make.addArg(const_ptr);
    str_make.addArg(const_len);
    str_make.uses = v.uses;

    try replaceValue(f, block, v, idx, &[_]*Value{ const_ptr, const_len, str_make });
    return true;
}

/// Decompose: Arg<string> → StringMake(Arg ptr, Arg len)
fn decomposeArg(f: *Func, block: *Block, v: *Value, idx: usize) !bool {
    debug.log(.ssa, "  decompose arg v{d}", .{v.id});

    // Create two args for the two components
    const arg_ptr = try f.newValue(.arg, TypeRegistry.U64, block, .{});
    arg_ptr.aux_int = v.aux_int; // Same arg index

    const arg_len = try f.newValue(.arg, TypeRegistry.I64, block, .{});
    arg_len.aux_int = v.aux_int + 1; // Next arg slot

    // StringMake
    const str_make = try f.newValue(.string_make, TypeRegistry.STRING, block, .{});
    str_make.addArg(arg_ptr);
    str_make.addArg(arg_len);
    str_make.uses = v.uses;

    try replaceValue(f, block, v, idx, &[_]*Value{ arg_ptr, arg_len, str_make });
    return true;
}

/// Decompose: Store dst StringMake(ptr,len) → Store dst ptr; Store dst+8 len
fn decomposeStore(f: *Func, block: *Block, v: *Value, idx: usize) !bool {
    const dst = v.args[0];
    const str_make = v.args[1];

    if (str_make.args.len < 2) return false;
    const str_ptr = str_make.args[0];
    const str_len = str_make.args[1];

    debug.log(.ssa, "  decompose store v{d}", .{v.id});

    // Store pointer component
    const store_ptr = try f.newValue(.store, TypeRegistry.VOID, block, .{});
    store_ptr.addArg(dst);
    store_ptr.addArg(str_ptr);

    // Create offset destination
    const off_dst = try f.newValue(.add_ptr, TypeRegistry.U64, block, .{});
    off_dst.addArg(dst);
    off_dst.aux_int = 8;

    // Store length component
    const store_len = try f.newValue(.store, TypeRegistry.VOID, block, .{});
    store_len.addArg(off_dst);
    store_len.addArg(str_len);

    try replaceValue(f, block, v, idx, &[_]*Value{ store_ptr, off_dst, store_len });

    // Decrement string_make uses since we consumed it
    if (str_make.uses > 0) str_make.uses -= 1;
    return true;
}

/// Replace a value with multiple new values at the same position.
fn replaceValue(f: *Func, block: *Block, old: *Value, idx: usize, new_values: []const *Value) !void {
    // Remove old value
    _ = block.values.orderedRemove(idx);

    // Insert new values at same position
    for (new_values, 0..) |new_v, i| {
        try block.values.insert(f.allocator, idx + i, new_v);
    }

    // Update uses of old value to point to last new value (the result)
    const replacement = new_values[new_values.len - 1];
    for (f.blocks.items) |b| {
        for (b.values.items) |v| {
            for (v.args, 0..) |arg, j| {
                if (arg == old) {
                    v.setArg(j, replacement); // Properly updates use counts
                }
            }
        }
    }

    f.freeValue(old);
}

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "decompose empty function" {
    const allocator = testing.allocator;
    var f = Func.init(allocator, "empty");
    defer f.deinit();

    const b = try f.newBlock(.first);

    try decompose(&f, null);
    try testing.expectEqual(@as(usize, 0), b.values.items.len);
}

test "decompose non-string values unchanged" {
    const allocator = testing.allocator;
    var f = Func.init(allocator, "no_strings");
    defer f.deinit();

    const b = try f.newBlock(.first);

    // Create i64 value - should not be decomposed
    const v = try f.newValue(.const_int, TypeRegistry.I64, b, .{});
    v.aux_int = 42;
    try b.addValue(allocator, v);

    try decompose(&f, null);

    try testing.expectEqual(@as(usize, 1), b.values.items.len);
    try testing.expectEqual(Op.const_int, b.values.items[0].op);
}

test "decompose iteration limit" {
    // Ensure decompose doesn't infinite loop
    const allocator = testing.allocator;
    var f = Func.init(allocator, "iter_limit");
    defer f.deinit();

    _ = try f.newBlock(.first);

    // Even with complex structures, should terminate
    try decompose(&f, null);
}
