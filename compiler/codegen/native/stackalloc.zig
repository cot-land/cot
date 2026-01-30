//! Stack Allocation - assigns stack slots to spilled values with interference-based reuse.

const std = @import("std");
const Func = @import("../../ssa/func.zig").Func;
const Value = @import("../../ssa/value.zig").Value;
const Block = @import("../../ssa/block.zig").Block;
const Op = @import("../../ssa/op.zig").Op;
const ID = @import("../../core/types.zig").ID;
const debug = @import("../../pipeline_debug.zig");

pub const FRAME_HEADER_SIZE: i32 = 16; // Saved FP + LR
pub const SPILL_SLOT_SIZE: i32 = 8;

pub const StackAllocResult = struct {
    frame_size: u32,
    num_spill_slots: u32,
    locals_size: u32,
    num_reused: u32,
};

// ============================================================================
// Per-Value State
// ============================================================================

const UseBlock = struct { block_id: ID, liveout: bool };

const StackValState = struct {
    type_idx: u32 = 0,
    needs_slot: bool = false,
    def_block: ID = 0,
    use_blocks: std.ArrayListUnmanaged(UseBlock) = .{},

    fn addUseBlock(self: *StackValState, allocator: std.mem.Allocator, block_id: ID, liveout: bool) !void {
        if (self.use_blocks.items.len > 0) {
            const last = self.use_blocks.items[self.use_blocks.items.len - 1];
            if (last.block_id == block_id and last.liveout == liveout) return;
        }
        try self.use_blocks.append(allocator, .{ .block_id = block_id, .liveout = liveout });
    }

    fn deinit(self: *StackValState, allocator: std.mem.Allocator) void {
        self.use_blocks.deinit(allocator);
    }
};

// ============================================================================
// Stack Allocator State
// ============================================================================

pub const StackAllocState = struct {
    allocator: std.mem.Allocator,
    f: *Func,
    values: []StackValState,
    live: std.AutoHashMapUnmanaged(ID, std.ArrayListUnmanaged(ID)) = .{},
    interfere: std.AutoHashMapUnmanaged(ID, std.ArrayListUnmanaged(ID)) = .{},

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, f: *Func) !Self {
        const values = try allocator.alloc(StackValState, f.vid.next_id);
        for (values) |*v| v.* = .{};
        return .{ .allocator = allocator, .f = f, .values = values };
    }

    pub fn deinit(self: *Self) void {
        for (self.values) |*v| v.deinit(self.allocator);
        self.allocator.free(self.values);

        var live_it = self.live.valueIterator();
        while (live_it.next()) |list| list.deinit(self.allocator);
        self.live.deinit(self.allocator);

        var int_it = self.interfere.valueIterator();
        while (int_it.next()) |list| list.deinit(self.allocator);
        self.interfere.deinit(self.allocator);
    }

    fn initValues(self: *Self) void {
        for (self.f.blocks.items) |block| {
            for (block.values.items) |v| {
                self.values[v.id].type_idx = v.type_idx;
                self.values[v.id].def_block = block.id;
                // Only store_reg with uses > 0 needs a slot
                if (v.op == .store_reg and v.uses > 0)
                    self.values[v.id].needs_slot = true;
            }
        }
    }

    fn computeLive(self: *Self, spill_live: *const std.AutoHashMapUnmanaged(ID, std.ArrayListUnmanaged(ID))) !void {
        // Seed from spillLive (values live at block ends but not in registers)
        var spill_it = spill_live.iterator();
        while (spill_it.next()) |entry| {
            for (entry.value_ptr.items) |spill_vid| {
                if (spill_vid < self.values.len)
                    try self.values[spill_vid].addUseBlock(self.allocator, entry.key_ptr.*, true);
            }
        }

        // Record where each value is used
        for (self.f.blocks.items) |block| {
            for (block.values.items) |v| {
                for (v.args) |arg| {
                    if (self.values[arg.id].needs_slot)
                        try self.values[arg.id].addUseBlock(self.allocator, block.id, false);
                }
            }
        }

        // Backward propagation from uses to definitions
        for (self.values, 0..) |*val, vid| {
            if (!val.needs_slot) continue;

            var seen = std.AutoHashMapUnmanaged(ID, void){};
            defer seen.deinit(self.allocator);
            var worklist = std.ArrayListUnmanaged(ID){};
            defer worklist.deinit(self.allocator);

            for (val.use_blocks.items) |ub| {
                if (ub.liveout) try self.pushLive(ub.block_id, @intCast(vid));
                try worklist.append(self.allocator, ub.block_id);
            }

            while (worklist.items.len > 0) {
                const work_id = worklist.pop().?;
                if (seen.contains(work_id) or work_id == val.def_block) continue;
                try seen.put(self.allocator, work_id, {});

                for (self.f.blocks.items) |block| {
                    if (block.id == work_id) {
                        for (block.preds) |pred| {
                            try self.pushLive(pred.b.id, @intCast(vid));
                            try worklist.append(self.allocator, pred.b.id);
                        }
                        break;
                    }
                }
            }
        }
    }

    fn pushLive(self: *Self, block_id: ID, vid: ID) !void {
        var list = self.live.get(block_id) orelse std.ArrayListUnmanaged(ID){};
        if (list.items.len > 0 and list.items[list.items.len - 1] == vid) return;
        try list.append(self.allocator, vid);
        try self.live.put(self.allocator, block_id, list);
    }

    fn buildInterference(self: *Self) !void {
        for (self.f.blocks.items) |block| {
            var live = std.AutoHashMapUnmanaged(ID, void){};
            defer live.deinit(self.allocator);

            if (self.live.get(block.id)) |live_list|
                for (live_list.items) |vid| try live.put(self.allocator, vid, {});

            var i: usize = block.values.items.len;
            while (i > 0) {
                i -= 1;
                const v = block.values.items[i];

                if (self.values[v.id].needs_slot) {
                    _ = live.remove(v.id);
                    var live_it = live.keyIterator();
                    while (live_it.next()) |live_id| try self.addInterference(v.id, live_id.*);
                }

                for (v.args) |arg|
                    if (self.values[arg.id].needs_slot) try live.put(self.allocator, arg.id, {});
            }
        }
    }

    fn addInterference(self: *Self, a: ID, b: ID) !void {
        try self.addInterfereOne(a, b);
        try self.addInterfereOne(b, a);
    }

    fn addInterfereOne(self: *Self, from: ID, to: ID) !void {
        var list = self.interfere.get(from) orelse std.ArrayListUnmanaged(ID){};
        for (list.items) |id| if (id == to) {
            try self.interfere.put(self.allocator, from, list);
            return;
        };
        try list.append(self.allocator, to);
        try self.interfere.put(self.allocator, from, list);
    }
};

// ============================================================================
// Main Entry Point
// ============================================================================

pub fn stackalloc(f: *Func, spill_live: *const std.AutoHashMapUnmanaged(ID, std.ArrayListUnmanaged(ID))) !StackAllocResult {
    debug.log(.regalloc, "=== Stack Allocation for '{s}' ===", .{f.name});

    var state = try StackAllocState.init(f.allocator, f);
    defer state.deinit();

    state.initValues();
    try state.computeLive(spill_live);
    try state.buildInterference();

    // Allocate locals first
    var current_offset: i32 = FRAME_HEADER_SIZE;
    const locals_start = current_offset;

    if (f.local_sizes.len > 0)
        f.local_offsets = try f.allocator.alloc(i32, f.local_sizes.len);

    for (f.local_sizes, 0..) |size, idx| {
        current_offset = (current_offset + 7) & ~@as(i32, 7);
        f.local_offsets[idx] = current_offset;
        current_offset += @intCast(size);
    }
    const locals_size: u32 = @intCast(current_offset - locals_start);

    // Allocate spill slots with reuse
    const Slot = struct { offset: i32, type_idx: u32 };
    var slots = std.ArrayListUnmanaged(Slot){};
    defer slots.deinit(f.allocator);

    var slots_used = try f.allocator.alloc(i32, f.vid.next_id);
    defer f.allocator.free(slots_used);
    for (slots_used) |*s| s.* = -1;

    var used = std.ArrayListUnmanaged(bool){};
    defer used.deinit(f.allocator);

    var num_spill_slots: u32 = 0;
    var num_reused: u32 = 0;

    for (f.blocks.items) |block| {
        for (block.values.items) |v| {
            if (!state.values[v.id].needs_slot) continue;

            // Mark slots used by interfering values
            used.clearRetainingCapacity();
            try used.resize(f.allocator, slots.items.len);
            for (used.items) |*u| u.* = false;

            if (state.interfere.get(v.id)) |interfering|
                for (interfering.items) |xid| {
                    const slot_idx = slots_used[xid];
                    if (slot_idx >= 0) used.items[@intCast(slot_idx)] = true;
                };

            // Find unused slot of matching type (skip reuse for store_reg)
            var found_slot: ?usize = null;
            if (v.op != .store_reg) {
                for (slots.items, 0..) |slot, i| {
                    if (slot.type_idx == v.type_idx and !used.items[i]) {
                        found_slot = i;
                        num_reused += 1;
                        break;
                    }
                }
            }

            // Allocate new slot if needed
            if (found_slot == null) {
                current_offset = (current_offset + 7) & ~@as(i32, 7);
                try slots.append(f.allocator, .{ .offset = current_offset, .type_idx = v.type_idx });
                found_slot = slots.items.len - 1;
                current_offset += SPILL_SLOT_SIZE;
                num_spill_slots += 1;
            }

            try f.setHome(v, .{ .stack = slots.items[found_slot.?].offset });
            slots_used[v.id] = @intCast(found_slot.?);
        }
    }

    const aligned_frame = (@as(u32, @intCast(current_offset)) + 15) & ~@as(u32, 15);
    debug.log(.regalloc, "  Stack: {d} locals ({d} bytes), {d} slots ({d} reused), frame {d} bytes", .{
        f.local_sizes.len, locals_size, num_spill_slots, num_reused, aligned_frame,
    });
    return .{ .frame_size = aligned_frame, .num_spill_slots = num_spill_slots, .locals_size = locals_size, .num_reused = num_reused };
}

// ============================================================================
// Tests
// ============================================================================

test "stackalloc empty function" {
    const allocator = std.testing.allocator;
    var f = Func.init(allocator, "test_empty");
    defer f.deinit();

    var spill_live = std.AutoHashMapUnmanaged(ID, std.ArrayListUnmanaged(ID)){};
    defer spill_live.deinit(allocator);

    const result = try stackalloc(&f, &spill_live);
    try std.testing.expectEqual(@as(u32, 16), result.frame_size);
    try std.testing.expectEqual(@as(u32, 0), result.num_spill_slots);
    try std.testing.expectEqual(@as(u32, 0), result.num_reused);
}

test "stackalloc with locals" {
    const allocator = std.testing.allocator;
    var f = Func.init(allocator, "test_locals");
    defer f.deinit();

    // Add some local variables directly
    f.local_sizes = try allocator.dupe(u32, &[_]u32{ 8, 4 });

    var spill_live = std.AutoHashMapUnmanaged(ID, std.ArrayListUnmanaged(ID)){};
    defer spill_live.deinit(allocator);

    const result = try stackalloc(&f, &spill_live);

    // Frame: 16 (header) + 8 (local0) + 4 (local1) = 28, aligned to 32
    try std.testing.expectEqual(@as(u32, 32), result.frame_size);
    try std.testing.expectEqual(@as(u32, 12), result.locals_size); // 8 + 4 = 12
    try std.testing.expectEqual(@as(u32, 0), result.num_spill_slots);

    // Verify local offsets (aligned to 8)
    try std.testing.expectEqual(@as(i32, 16), f.local_offsets[0]);
    try std.testing.expectEqual(@as(i32, 24), f.local_offsets[1]);
}

test "StackValState use block tracking" {
    const allocator = std.testing.allocator;
    var val = StackValState{};
    defer val.deinit(allocator);

    try val.addUseBlock(allocator, 1, false);
    try val.addUseBlock(allocator, 2, true);
    try val.addUseBlock(allocator, 2, true); // Duplicate should be ignored

    try std.testing.expectEqual(@as(usize, 2), val.use_blocks.items.len);
    try std.testing.expectEqual(@as(ID, 1), val.use_blocks.items[0].block_id);
    try std.testing.expect(!val.use_blocks.items[0].liveout);
    try std.testing.expectEqual(@as(ID, 2), val.use_blocks.items[1].block_id);
    try std.testing.expect(val.use_blocks.items[1].liveout);
}

test "StackAllocState init and deinit" {
    const allocator = std.testing.allocator;
    var f = Func.init(allocator, "test_state");
    defer f.deinit();

    var state = try StackAllocState.init(allocator, &f);
    defer state.deinit();

    try std.testing.expectEqual(f.vid.next_id, state.values.len);
}

test "frame alignment" {
    // Verify frame sizes are 16-byte aligned
    const test_cases = [_]struct { input: u32, expected: u32 }{
        .{ .input = 16, .expected = 16 },
        .{ .input = 17, .expected = 32 },
        .{ .input = 31, .expected = 32 },
        .{ .input = 32, .expected = 32 },
        .{ .input = 33, .expected = 48 },
    };

    for (test_cases) |tc| {
        const aligned = (tc.input + 15) & ~@as(u32, 15);
        try std.testing.expectEqual(tc.expected, aligned);
    }
}
