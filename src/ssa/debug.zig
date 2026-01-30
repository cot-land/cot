//! Debug and Visualization Support for SSA - text dump, DOT graph, verification.

const std = @import("std");
const Func = @import("func.zig").Func;
const Block = @import("block.zig").Block;
const Value = @import("value.zig").Value;
const Op = @import("op.zig").Op;
const TypeRegistry = @import("../frontend/types.zig").TypeRegistry;
const core_types = @import("../core/types.zig");
const ID = core_types.ID;

pub const Format = enum { text, dot };

// ============================================================================
// Dump Functions
// ============================================================================

pub fn dump(f: *const Func, format: Format, writer: anytype) !void {
    switch (format) {
        .text => try dumpText(f, writer),
        .dot => try dumpDot(f, writer),
    }
}

pub fn dumpText(f: *const Func, writer: anytype) !void {
    try writer.print("func {s}:\n", .{f.name});

    for (f.blocks.items) |b| {
        try writer.print("  b{d} ({s}):\n", .{ b.id, @tagName(b.kind) });

        if (b.preds.len > 0) {
            try writer.writeAll("    preds: ");
            for (b.preds, 0..) |pred, i| {
                if (i > 0) try writer.writeAll(", ");
                try writer.print("b{d}", .{pred.b.id});
            }
            try writer.writeAll("\n");
        }

        for (b.values.items) |v| try dumpValue(v, writer);

        if (b.numControls() > 0) {
            try writer.writeAll("    control: ");
            for (b.controlValues(), 0..) |cv, i| {
                if (i > 0) try writer.writeAll(", ");
                try writer.print("v{d}", .{cv.id});
            }
            try writer.writeAll("\n");
        }

        if (b.succs.len > 0) {
            try writer.writeAll("    succs: ");
            for (b.succs, 0..) |succ, i| {
                if (i > 0) try writer.writeAll(", ");
                try writer.print("b{d}", .{succ.b.id});
            }
            try writer.writeAll("\n");
        }
        try writer.writeAll("\n");
    }
}

fn dumpValue(v: *const Value, writer: anytype) !void {
    const dead = if (v.uses == 0 and !v.hasSideEffects()) " (dead)" else "";
    const type_name = TypeRegistry.basicTypeName(v.type_idx);
    const size = TypeRegistry.basicTypeSize(v.type_idx);

    try writer.print("    v{d}: {s}({d}B){s} = {s}", .{ v.id, type_name, size, dead, @tagName(v.op) });

    if (v.args.len > 0) {
        try writer.writeAll(" ");
        for (v.args, 0..) |arg, i| {
            if (i > 0) try writer.writeAll(", ");
            try writer.print("v{d}", .{arg.id});
        }
    }

    switch (v.aux) {
        .none => {},
        .string => |s| try writer.print(" \"{s}\"", .{s}),
        .symbol => |sym| try writer.print(" @{*}", .{sym}),
        .symbol_off => |so| try writer.print(" @{*}+{d}", .{ so.sym, so.offset }),
        .call => try writer.writeAll(" <call>"),
        .type_ref => |t| try writer.print(" type({d})", .{t}),
        .cond => |c| try writer.print(" cond({s})", .{@tagName(c)}),
    }

    if (v.aux_int != 0) try writer.print(" [{d}]", .{v.aux_int});
    try writer.print(" : uses={d}\n", .{v.uses});
}

pub fn dumpDot(f: *const Func, writer: anytype) !void {
    try writer.print("digraph \"{s}\" {{\n", .{f.name});
    try writer.writeAll("  rankdir=TB;\n  node [shape=box, fontname=\"Courier\"];\n\n");

    for (f.blocks.items) |b| {
        try writer.print("  b{d} [label=\"b{d} ({s})\\l", .{ b.id, b.id, @tagName(b.kind) });
        for (b.values.items) |v| {
            try writer.print("v{d} = {s}", .{ v.id, @tagName(v.op) });
            if (v.args.len > 0) {
                try writer.writeAll(" ");
                for (v.args, 0..) |arg, i| {
                    if (i > 0) try writer.writeAll(", ");
                    try writer.print("v{d}", .{arg.id});
                }
            }
            if (v.aux_int != 0) try writer.print(" [{d}]", .{v.aux_int});
            try writer.writeAll("\\l");
        }
        try writer.writeAll("\"];\n");
    }

    try writer.writeAll("\n");
    for (f.blocks.items) |b| {
        for (b.succs, 0..) |succ, i| {
            const label = if (b.kind == .if_) (if (i == 0) "T" else "F") else "";
            if (label.len > 0) {
                try writer.print("  b{d} -> b{d} [label=\"{s}\"];\n", .{ b.id, succ.b.id, label });
            } else {
                try writer.print("  b{d} -> b{d};\n", .{ b.id, succ.b.id });
            }
        }
    }
    try writer.writeAll("}\n");
}

pub fn dumpToFile(f: *const Func, format: Format, path: []const u8) !void {
    const file = try std.fs.cwd().createFile(path, .{});
    defer file.close();
    try dump(f, format, file.writer());
}

// ============================================================================
// Verification
// ============================================================================

pub fn verify(f: *const Func, allocator: std.mem.Allocator) ![]const []const u8 {
    var errors = std.ArrayListUnmanaged([]const u8){};

    for (f.blocks.items) |b| {
        for (b.values.items) |v| {
            if (v.block != b) {
                try errors.append(allocator, try std.fmt.allocPrint(allocator, "v{d}: block pointer mismatch (expected b{d}, got b{d})", .{ v.id, b.id, if (v.block) |vb| vb.id else 0 }));
            }
            for (v.args) |arg| {
                if (arg.id == 0) {
                    try errors.append(allocator, try std.fmt.allocPrint(allocator, "v{d}: has invalid arg (id=0)", .{v.id}));
                }
            }
        }

        for (b.succs, 0..) |succ, i| {
            if (succ.i >= succ.b.preds.len or succ.b.preds[succ.i].b != b) {
                try errors.append(allocator, try std.fmt.allocPrint(allocator, "b{d}: succ[{d}] edge invariant violated", .{ b.id, i }));
            }
        }

        for (b.preds, 0..) |pred, i| {
            if (pred.i >= pred.b.succs.len or pred.b.succs[pred.i].b != b) {
                try errors.append(allocator, try std.fmt.allocPrint(allocator, "b{d}: pred[{d}] edge invariant violated", .{ b.id, i }));
            }
        }
    }

    return errors.toOwnedSlice(allocator);
}

pub fn freeErrors(errors: []const []const u8, allocator: std.mem.Allocator) void {
    for (errors) |err| allocator.free(err);
    allocator.free(errors);
}

// ============================================================================
// Phase Snapshot (GOSSAFUNC-style comparison)
// ============================================================================

pub const ValueSnapshot = struct { id: ID, op: Op, arg_ids: []ID, uses: i32, aux_int: i64 };
pub const BlockSnapshot = struct { id: ID, kind: @import("block.zig").BlockKind, values: []ValueSnapshot, succ_ids: []ID };

pub const PhaseSnapshot = struct {
    name: []const u8,
    blocks: []BlockSnapshot,
    allocator: std.mem.Allocator,

    pub fn capture(allocator: std.mem.Allocator, f: *const Func, name: []const u8) !PhaseSnapshot {
        var blocks = try allocator.alloc(BlockSnapshot, f.blocks.items.len);

        for (f.blocks.items, 0..) |b, i| {
            var values = try allocator.alloc(ValueSnapshot, b.values.items.len);
            for (b.values.items, 0..) |v, j| {
                var arg_ids = try allocator.alloc(ID, v.args.len);
                for (v.args, 0..) |arg, k| arg_ids[k] = arg.id;
                values[j] = .{ .id = v.id, .op = v.op, .arg_ids = arg_ids, .uses = v.uses, .aux_int = v.aux_int };
            }

            var succ_ids = try allocator.alloc(ID, b.succs.len);
            for (b.succs, 0..) |succ, k| succ_ids[k] = succ.b.id;

            blocks[i] = .{ .id = b.id, .kind = b.kind, .values = values, .succ_ids = succ_ids };
        }

        return .{ .name = try allocator.dupe(u8, name), .blocks = blocks, .allocator = allocator };
    }

    pub fn deinit(self: *PhaseSnapshot) void {
        for (self.blocks) |b| {
            for (b.values) |v| self.allocator.free(v.arg_ids);
            self.allocator.free(b.values);
            self.allocator.free(b.succ_ids);
        }
        self.allocator.free(self.blocks);
        self.allocator.free(self.name);
    }

    pub fn compare(before: *const PhaseSnapshot, after: *const PhaseSnapshot) ChangeStats {
        var stats = ChangeStats{};

        var before_values = std.AutoHashMap(ID, void).init(before.allocator);
        defer before_values.deinit();
        var before_blocks = std.AutoHashMap(ID, void).init(before.allocator);
        defer before_blocks.deinit();

        for (before.blocks) |b| {
            before_blocks.put(b.id, {}) catch {};
            for (b.values) |v| before_values.put(v.id, {}) catch {};
        }

        for (after.blocks) |b| {
            if (!before_blocks.contains(b.id)) stats.blocks_added += 1;
            for (b.values) |v| if (!before_values.contains(v.id)) { stats.values_added += 1; };
        }

        var after_values = std.AutoHashMap(ID, void).init(after.allocator);
        defer after_values.deinit();
        var after_blocks = std.AutoHashMap(ID, void).init(after.allocator);
        defer after_blocks.deinit();

        for (after.blocks) |b| {
            after_blocks.put(b.id, {}) catch {};
            for (b.values) |v| after_values.put(v.id, {}) catch {};
        }

        for (before.blocks) |b| {
            if (!after_blocks.contains(b.id)) stats.blocks_removed += 1;
            for (b.values) |v| if (!after_values.contains(v.id)) { stats.values_removed += 1; };
        }

        return stats;
    }
};

pub const ChangeStats = struct {
    values_added: usize = 0,
    values_removed: usize = 0,
    values_modified: usize = 0,
    blocks_added: usize = 0,
    blocks_removed: usize = 0,

    pub fn hasChanges(self: ChangeStats) bool {
        return self.values_added > 0 or self.values_removed > 0 or self.values_modified > 0 or self.blocks_added > 0 or self.blocks_removed > 0;
    }

    pub fn format(self: ChangeStats, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("+{d}/-{d} values, +{d}/-{d} blocks", .{ self.values_added, self.values_removed, self.blocks_added, self.blocks_removed });
    }
};

// ============================================================================
// Tests
// ============================================================================

test "dump text format" {
    const allocator = std.testing.allocator;
    var f = Func.init(allocator, "test");
    defer f.deinit();

    const b = try f.newBlock(.ret);
    const v = try f.newValue(.const_int, 0, b, .{});
    v.aux_int = 42;
    try b.addValue(allocator, v);

    var output = std.ArrayListUnmanaged(u8){};
    defer output.deinit(allocator);

    try dumpText(&f, output.writer(allocator));

    try std.testing.expect(std.mem.indexOf(u8, output.items, "test") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.items, "v1") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.items, "const_int") != null);
}

test "dump dot format" {
    const allocator = std.testing.allocator;
    var f = Func.init(allocator, "test_dot");
    defer f.deinit();

    const entry = try f.newBlock(.if_);
    const left = try f.newBlock(.plain);
    const right = try f.newBlock(.ret);

    try entry.addEdgeTo(allocator, left);
    try entry.addEdgeTo(allocator, right);

    var output = std.ArrayListUnmanaged(u8){};
    defer output.deinit(allocator);

    try dumpDot(&f, output.writer(allocator));

    try std.testing.expect(std.mem.indexOf(u8, output.items, "digraph") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.items, "->") != null);
}

test "verify catches edge invariant violations" {
    const allocator = std.testing.allocator;
    var f = Func.init(allocator, "test_verify");
    defer f.deinit();

    const entry = try f.newBlock(.plain);
    const exit = try f.newBlock(.ret);
    try entry.addEdgeTo(allocator, exit);

    const errors = try verify(&f, allocator);
    defer freeErrors(errors, allocator);

    try std.testing.expectEqual(@as(usize, 0), errors.len);
}

test "PhaseSnapshot capture and deinit" {
    const allocator = std.testing.allocator;
    var f = Func.init(allocator, "test_snapshot");
    defer f.deinit();

    const b = try f.newBlock(.ret);
    const v = try f.newValue(.const_int, 0, b, .{});
    try b.addValue(allocator, v);

    var snapshot = try PhaseSnapshot.capture(allocator, &f, "test");
    defer snapshot.deinit();

    try std.testing.expectEqual(@as(usize, 1), snapshot.blocks.len);
    try std.testing.expectEqual(@as(usize, 1), snapshot.blocks[0].values.len);
}

test "ChangeStats hasChanges" {
    var stats = ChangeStats{};
    try std.testing.expect(!stats.hasChanges());

    stats.values_added = 1;
    try std.testing.expect(stats.hasChanges());
}
