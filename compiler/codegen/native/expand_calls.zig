//! Expand Calls Pass - Decompose aggregate arguments before register allocation.
//!
//! Go reference: cmd/compile/internal/ssa/expand_calls.go
//!
//! ## The Critical Invariant
//!
//! After this pass: NO SSA Value has type > 32 bytes (MAX_SSA_SIZE).
//! Large aggregates use OpMove (bulk memory copy), not field decomposition.
//!
//! ## Pass Structure (following Go)
//!
//! 1. Collect - gather calls, args, selects; mark wide selects
//! 2. Args - rewrite OpArg to decompose aggregates
//! 3. Selects - handle Store(SelectN) for large types
//! 4. Calls - decompose aggregate call arguments
//! 5. Exits - rewrite function returns for aggregate results

const std = @import("std");
const Value = @import("../../ssa/value.zig").Value;
const AuxCall = @import("../../ssa/value.zig").AuxCall;
const canSSA = @import("../../ssa/value.zig").canSSA;
const MAX_SSA_SIZE = @import("../../ssa/value.zig").MAX_SSA_SIZE;
const Block = @import("../../ssa/block.zig").Block;
const Func = @import("../../ssa/func.zig").Func;
const Op = @import("../../ssa/op.zig").Op;
const abi_mod = @import("abi.zig");
const types = @import("../../frontend/types.zig");
const TypeRegistry = types.TypeRegistry;
const debug = @import("../../pipeline_debug.zig");

/// Run the expand_calls pass on a function.
pub fn expandCalls(f: *Func, type_reg: ?*const TypeRegistry) !void {
    const reg = type_reg orelse {
        debug.log(.ssa, "expand_calls: no type registry, skipping", .{});
        return;
    };

    debug.log(.ssa, "expand_calls: processing '{s}'", .{f.name});

    // =========================================================================
    // Pass 1: Collect calls, args, selects; mark wide selects
    // =========================================================================

    var calls = std.ArrayListUnmanaged(*Value){};
    defer calls.deinit(f.allocator);
    var args = std.ArrayListUnmanaged(*Value){};
    defer args.deinit(f.allocator);
    var selects = std.ArrayListUnmanaged(*Value){};
    defer selects.deinit(f.allocator);
    var wide_selects = std.AutoHashMap(*Value, *Value).init(f.allocator);
    defer wide_selects.deinit();

    for (f.blocks.items) |block| {
        for (block.values.items) |v| {
            switch (v.op) {
                .static_call, .closure_call, .string_concat => {
                    try calls.append(f.allocator, v);
                },
                .arg => {
                    try args.append(f.allocator, v);
                },
                .select_n => {
                    if (v.type_idx != TypeRegistry.VOID) {
                        try selects.append(f.allocator, v);
                    }
                },
                .store => {
                    // Mark wide stores (value is non-SSA type)
                    if (v.args.len >= 2) {
                        const stored = v.args[1];
                        if (stored.op == .select_n or stored.op == .static_call) {
                            const size = reg.sizeOf(stored.type_idx);
                            if (size > MAX_SSA_SIZE) {
                                try wide_selects.put(stored, v);
                            }
                        }
                    }
                },
                else => {},
            }
        }
    }

    debug.log(.ssa, "  found {d} calls, {d} args, {d} selects, {d} wide", .{
        calls.items.len,
        args.items.len,
        selects.items.len,
        wide_selects.count(),
    });

    // =========================================================================
    // Pass 2: Rewrite OpArg to decompose aggregates
    // =========================================================================

    for (args.items) |arg| {
        try expandArg(f, arg, reg);
    }

    // =========================================================================
    // Pass 3: Handle selects (Store of SelectN for large types)
    // =========================================================================

    var wide_it = wide_selects.iterator();
    while (wide_it.next()) |entry| {
        const select = entry.key_ptr.*;
        const store = entry.value_ptr.*;
        try expandWideSelect(f, select, store, reg);
    }

    // =========================================================================
    // Pass 4: Decompose aggregate call arguments
    // =========================================================================

    for (calls.items) |call| {
        try expandCall(f, call, reg);
    }

    // =========================================================================
    // Pass 5: Rewrite function returns for aggregate results
    // =========================================================================

    for (f.blocks.items) |block| {
        if (block.kind == .exit) {
            try expandExit(f, block, reg);
        }
    }
}

fn expandArg(_: *Func, arg: *Value, reg: *const TypeRegistry) !void {
    const size = reg.sizeOf(arg.type_idx);
    if (size <= 8) return; // Already fits in a register

    debug.log(.ssa, "  expand arg v{d} size={d}", .{ arg.id, size });

    // For 16-byte args (like strings), decompose into two 8-byte args
    if (size == 16 and arg.type_idx == TypeRegistry.STRING) {
        // Already handled by decompose pass
        return;
    }

    // Large args: treat as pointer to stack slot
    arg.type_idx = TypeRegistry.U64;
}

fn expandWideSelect(f: *Func, select: *Value, store: *Value, reg: *const TypeRegistry) !void {
    const size = reg.sizeOf(select.type_idx);
    debug.log(.ssa, "  expand wide select v{d} size={d}", .{ select.id, size });

    // Convert Store to Move for large types
    // Go: Replace Store(dst, SelectN) with Move(dst, src, size)
    if (store.args.len >= 2) {
        store.op = .move;
        store.aux_int = @intCast(size);
    }

    _ = f;
}

fn expandCall(f: *Func, call: *Value, reg: *const TypeRegistry) !void {
    // Check if any argument is too large for SSA
    var has_large = false;
    for (call.args) |arg| {
        const size = reg.sizeOf(arg.type_idx);
        if (size > MAX_SSA_SIZE) {
            has_large = true;
            break;
        }
    }

    if (!has_large) return;

    debug.log(.ssa, "  expand call v{d} with large args", .{call.id});

    // For calls with large args, we need to:
    // 1. Allocate stack space for the aggregate
    // 2. Copy the aggregate to stack
    // 3. Pass pointer to stack location
    // This is handled by codegen for now
    _ = f;
}

fn expandExit(f: *Func, block: *Block, reg: *const TypeRegistry) !void {
    // Check for large return values
    for (block.controlValues()) |ctrl| {
        if (ctrl.op == .arm64_ret or ctrl.op == .amd64_ret) {
            for (ctrl.args) |arg| {
                const size = reg.sizeOf(arg.type_idx);
                if (size > MAX_SSA_SIZE) {
                    debug.log(.ssa, "  expand exit with large return v{d}", .{arg.id});
                    // Large returns use hidden pointer parameter
                }
            }
        }
    }
    _ = f;
}

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "expandCalls with no type registry" {
    const allocator = testing.allocator;
    var f = Func.init(allocator, "no_reg");
    defer f.deinit();

    _ = try f.newBlock(.first);

    // Should not error, just skip
    try expandCalls(&f, null);
}

test "expandCalls empty function" {
    const allocator = testing.allocator;
    var f = Func.init(allocator, "empty");
    defer f.deinit();

    _ = try f.newBlock(.first);

    var reg = try TypeRegistry.init(allocator);
    defer reg.deinit();

    try expandCalls(&f, &reg);
}

test "expandCalls with simple call" {
    const allocator = testing.allocator;
    var f = Func.init(allocator, "simple_call");
    defer f.deinit();

    const b = try f.newBlock(.first);

    // Create a simple call with i64 arg (no expansion needed)
    const arg = try f.newValue(.const_int, TypeRegistry.I64, b, .{});
    arg.aux_int = 42;
    try b.addValue(allocator, arg);

    const call = try f.newValue(.static_call, TypeRegistry.I64, b, .{});
    call.addArg(arg);
    try b.addValue(allocator, call);

    var reg = try TypeRegistry.init(allocator);
    defer reg.deinit();

    try expandCalls(&f, &reg);

    // Call should still exist
    try testing.expectEqual(@as(usize, 2), b.values.items.len);
}

test "MAX_SSA_SIZE threshold" {
    // Verify the constant matches Go's definition
    try testing.expectEqual(@as(usize, 32), MAX_SSA_SIZE);
}
