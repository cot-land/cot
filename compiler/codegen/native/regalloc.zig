//! Linear scan register allocator (Go-style: liveness → allocation → shuffle).

const std = @import("std");
const types = @import("../../core/types.zig");
const liveness = @import("liveness.zig");
const Value = @import("../../ssa/value.zig").Value;
const Block = @import("../../ssa/block.zig").Block;
const Func = @import("../../ssa/func.zig").Func;
const Op = @import("../../ssa/op.zig").Op;
const debug = @import("../../pipeline_debug.zig");
const Target = @import("../../core/target.zig").Target;

const ID = types.ID;
const Pos = types.Pos;
const RegMask = types.RegMask;
const RegNum = types.RegNum;

pub const ARM64Regs = struct {
    pub const x0: RegNum = 0;
    pub const x1: RegNum = 1;
    pub const x2: RegNum = 2;
    pub const x3: RegNum = 3;
    pub const x4: RegNum = 4;
    pub const x5: RegNum = 5;
    pub const x6: RegNum = 6;
    pub const x7: RegNum = 7;

    pub const allocatable: RegMask = blk: {
        var mask: RegMask = 0;
        for (0..16) |i| mask |= @as(RegMask, 1) << i;
        for (19..29) |i| mask |= @as(RegMask, 1) << i;
        break :blk mask;
    };

    pub const caller_saved: RegMask = blk: {
        var mask: RegMask = 0;
        for (0..18) |i| mask |= @as(RegMask, 1) << i;
        break :blk mask;
    };

    pub const callee_saved: RegMask = blk: {
        var mask: RegMask = 0;
        for (19..29) |i| mask |= @as(RegMask, 1) << i;
        break :blk mask;
    };

    pub const arg_regs = [_]RegNum{ 0, 1, 2, 3, 4, 5, 6, 7 };
};

pub const AMD64Regs = struct {
    pub const rax: RegNum = 0;
    pub const rcx: RegNum = 1;
    pub const rdx: RegNum = 2;
    pub const rbx: RegNum = 3;
    pub const rsp: RegNum = 4;
    pub const rbp: RegNum = 5;
    pub const rsi: RegNum = 6;
    pub const rdi: RegNum = 7;
    pub const r8: RegNum = 8;
    pub const r9: RegNum = 9;
    pub const r10: RegNum = 10;
    pub const r11: RegNum = 11;
    pub const r12: RegNum = 12;
    pub const r13: RegNum = 13;
    pub const r14: RegNum = 14;
    pub const r15: RegNum = 15;

    pub const allocatable: RegMask = blk: {
        var mask: RegMask = 0;
        for (0..3) |i| mask |= @as(RegMask, 1) << i;
        for (6..12) |i| mask |= @as(RegMask, 1) << i;
        break :blk mask;
    };

    pub const caller_saved: RegMask = (1 << 0) | (1 << 1) | (1 << 2) | (1 << 6) | (1 << 7) | (1 << 8) | (1 << 9) | (1 << 10) | (1 << 11);
    pub const callee_saved: RegMask = (1 << 3) | (1 << 12) | (1 << 13) | (1 << 14) | (1 << 15);
    pub const arg_regs = [_]RegNum{ 7, 6, 2, 1, 8, 9 };
};

pub const EndReg = struct { reg: RegNum, v: *Value, c: *Value };

pub const Use = struct {
    dist: i32,
    pos: Pos,
    next: ?*Use,
};

pub const ValState = struct {
    regs: RegMask = 0,
    spill: ?*Value = null,
    spill_used: bool = false,
    uses: ?*Use = null,
    rematerializeable: bool = false,
    needs_reg: bool = true,

    pub fn inReg(self: *const ValState) bool { return self.regs != 0; }
    pub fn firstReg(self: *const ValState) ?RegNum { return types.regMaskFirst(self.regs); }
};

pub const RegState = struct {
    v: ?*Value = null,
    dirty: bool = false,

    pub fn isFree(self: *const RegState) bool { return self.v == null; }
    pub fn clear(self: *RegState) void { self.v = null; self.dirty = false; }
};

pub const NUM_REGS: usize = 32;

pub const RegAllocState = struct {
    allocator: std.mem.Allocator,
    f: *Func,
    live: liveness.LivenessResult,
    values: []ValState,
    regs: [NUM_REGS]RegState = [_]RegState{.{}} ** NUM_REGS,
    end_regs: std.AutoHashMapUnmanaged(ID, []EndReg),
    pending_spills: std.ArrayListUnmanaged(*Value) = .{},
    used: RegMask = 0,
    spill_live: std.AutoHashMapUnmanaged(ID, std.ArrayListUnmanaged(ID)) = .{},
    free_use_records: ?*Use = null,
    cur_idx: usize = 0,
    next_call: std.ArrayListUnmanaged(i32) = .{},
    num_spills: u32 = 0,
    allocatable_mask: RegMask,
    caller_saved_mask: RegMask,
    num_arg_regs: u8,
    arg_regs: []const RegNum,
    target: Target,

    pub fn init(allocator: std.mem.Allocator, f: *Func, live: liveness.LivenessResult, target: Target) !RegAllocState {
        const max_id = f.vid.next_id;
        const values = try allocator.alloc(ValState, max_id);
        for (values) |*v| v.* = .{};

        const is_amd64 = target.arch == .amd64;
        return .{
            .allocator = allocator,
            .f = f,
            .live = live,
            .values = values,
            .end_regs = .{},
            .allocatable_mask = if (is_amd64) AMD64Regs.allocatable else ARM64Regs.allocatable,
            .caller_saved_mask = if (is_amd64) AMD64Regs.caller_saved else ARM64Regs.caller_saved,
            .num_arg_regs = @intCast(if (is_amd64) AMD64Regs.arg_regs.len else ARM64Regs.arg_regs.len),
            .arg_regs = if (is_amd64) &AMD64Regs.arg_regs else &ARM64Regs.arg_regs,
            .target = target,
        };
    }

    pub fn deinit(self: *RegAllocState) void {
        var it = self.end_regs.valueIterator();
        while (it.next()) |regs| self.allocator.free(regs.*);
        self.end_regs.deinit(self.allocator);
        self.pending_spills.deinit(self.allocator);
        self.allocator.free(self.values);
        self.live.deinit();

        var spill_it = self.spill_live.valueIterator();
        while (spill_it.next()) |list| list.deinit(self.allocator);
        self.spill_live.deinit(self.allocator);
        self.next_call.deinit(self.allocator);

        var use_ptr = self.free_use_records;
        while (use_ptr) |u| {
            const next = u.next;
            self.allocator.destroy(u);
            use_ptr = next;
        }
    }

    pub fn getSpillLive(self: *const RegAllocState) *const std.AutoHashMapUnmanaged(ID, std.ArrayListUnmanaged(ID)) {
        return &self.spill_live;
    }

    fn addUse(self: *RegAllocState, id: ID, dist: i32, pos: Pos) void {
        if (id >= self.values.len) return;
        const r: *Use = if (self.free_use_records) |free| blk: {
            self.free_use_records = free.next;
            break :blk free;
        } else self.allocator.create(Use) catch return;

        r.* = .{ .dist = dist, .pos = pos, .next = self.values[id].uses };
        self.values[id].uses = r;
    }

    fn advanceUses(self: *RegAllocState, v: *Value) void {
        for (v.args) |arg| {
            if (arg.id >= self.values.len) continue;
            const vi = &self.values[arg.id];
            if (!vi.needs_reg) continue;
            const r = vi.uses orelse continue;
            vi.uses = r.next;

            const next_call_dist = if (self.cur_idx < self.next_call.items.len)
                self.next_call.items[self.cur_idx]
            else
                std.math.maxInt(i32);

            if (r.next == null or r.next.?.dist > next_call_dist) {
                self.freeRegs(vi.regs);
            }
            r.next = self.free_use_records;
            self.free_use_records = r;
        }
    }

    fn clearUses(self: *RegAllocState) void {
        for (self.values) |*vi| {
            var u = vi.uses;
            while (u) |use| {
                const next = use.next;
                use.next = self.free_use_records;
                self.free_use_records = use;
                u = next;
            }
            vi.uses = null;
        }
    }

    fn buildUseLists(self: *RegAllocState, block: *Block) !void {
        self.clearUses();
        const num_values = block.values.items.len;
        try self.next_call.resize(self.allocator, num_values);

        for (self.live.getLiveOut(block.id)) |info| {
            self.addUse(info.id, @intCast(num_values + @as(usize, @intCast(info.dist))), info.pos);
        }

        for (block.controlValues()) |ctrl| {
            if (ctrl.id < self.values.len and self.values[ctrl.id].needs_reg) {
                self.addUse(ctrl.id, @intCast(num_values), block.pos);
            }
        }

        var next_call_dist: i32 = std.math.maxInt(i32);
        var i: usize = num_values;
        while (i > 0) {
            i -= 1;
            const v = block.values.items[i];
            if (v.op.info().call) next_call_dist = @intCast(i);
            self.next_call.items[i] = next_call_dist;

            for (v.args) |arg| {
                if (arg.id >= self.values.len) continue;
                if (!self.values[arg.id].needs_reg) continue;
                self.addUse(arg.id, @intCast(i), v.pos);
            }
        }
        debug.log(.regalloc, "  Built use lists for block b{d}, {d} values", .{ block.id, num_values });
    }

    fn findFreeReg(self: *const RegAllocState, mask: RegMask) ?RegNum {
        var m = mask;
        while (m != 0) {
            const reg = @ctz(m);
            if (reg < NUM_REGS and self.regs[reg].isFree()) return @intCast(reg);
            m &= m - 1;
        }
        return null;
    }

    fn allocReg(self: *RegAllocState, mask: RegMask, block: *Block) !RegNum {
        const available_mask = mask & ~self.used;
        if (self.findFreeReg(available_mask)) |reg| return reg;

        var best_reg: ?RegNum = null;
        var best_dist: i32 = -1;
        var m = available_mask;
        while (m != 0) {
            const reg: RegNum = @intCast(@ctz(m));
            m &= m - 1;
            if (reg >= NUM_REGS) continue;
            const v = self.regs[reg].v orelse continue;
            const vi = &self.values[v.id];
            const dist: i32 = if (vi.uses) |use| use.dist else std.math.maxInt(i32);
            if (dist > best_dist) {
                best_dist = dist;
                best_reg = reg;
            }
        }

        const reg = best_reg orelse return error.NoRegisterAvailable;
        debug.log(.regalloc, "    spilling v{d} from x{d} (dist={d})", .{
            if (self.regs[reg].v) |v| v.id else 0, reg, best_dist,
        });
        if (try self.spillReg(reg, block)) |spill| {
            try self.pending_spills.append(self.allocator, spill);
        }
        return reg;
    }

    fn spillReg(self: *RegAllocState, reg: RegNum, block: *Block) !?*Value {
        const v = self.regs[reg].v orelse return null;
        const vi = &self.values[v.id];
        var result: ?*Value = null;

        if (vi.rematerializeable) {
            debug.log(.regalloc, "    evict v{d} from x{d} (rematerializeable)", .{ v.id, reg });
            self.f.clearHome(v.id);
        } else if (vi.spill == null) {
            const spill = try self.f.newValue(.store_reg, v.type_idx, block, v.pos);
            spill.addArg(v);
            vi.spill = spill;
            self.num_spills += 1;
            debug.log(.regalloc, "    spill v{d} from x{d}", .{ v.id, reg });
            result = spill;
        }
        vi.spill_used = true;
        self.regs[reg].clear();
        vi.regs = types.regMaskClear(vi.regs, reg);
        return result;
    }

    fn assignReg(self: *RegAllocState, v: *Value, reg: RegNum) !void {
        self.regs[reg] = .{ .v = v, .dirty = true };
        self.values[v.id].regs = types.regMaskSet(self.values[v.id].regs, reg);
        try self.f.setHome(v, .{ .register = @intCast(reg) });
        self.used |= @as(RegMask, 1) << @intCast(reg);
        debug.log(.regalloc, "    assign v{d} -> x{d}", .{ v.id, reg });
    }

    fn freeReg(self: *RegAllocState, reg: RegNum) void {
        if (self.regs[reg].v) |v| {
            self.values[v.id].regs = types.regMaskClear(self.values[v.id].regs, reg);
        }
        self.regs[reg].clear();
        self.used &= ~(@as(RegMask, 1) << @intCast(reg));
    }

    fn freeRegs(self: *RegAllocState, mask: RegMask) void {
        var m = mask;
        while (m != 0) {
            const reg: RegNum = @intCast(@ctz(m));
            m &= m - 1;
            if (reg < NUM_REGS) self.freeReg(reg);
        }
    }

    fn loadValue(self: *RegAllocState, v: *Value, block: *Block) !*Value {
        const vi = &self.values[v.id];
        const reg = try self.allocReg(self.allocatable_mask, block);

        if (vi.rematerializeable) {
            const copy = try self.f.newValue(v.op, v.type_idx, block, v.pos);
            copy.aux_int = v.aux_int;
            try self.ensureValState(copy);
            self.values[copy.id].rematerializeable = true;
            try self.assignReg(copy, reg);
            debug.log(.regalloc, "    rematerialize v{d} -> x{d} (v{d})", .{ v.id, reg, copy.id });
            return copy;
        }

        if (vi.spill) |spill| {
            const load = try self.f.newValue(.load_reg, v.type_idx, block, v.pos);
            load.addArg(spill);
            try self.ensureValState(load);
            try self.assignReg(load, reg);
            debug.log(.regalloc, "    load v{d} from spill -> x{d} (v{d})", .{ v.id, reg, load.id });
            return load;
        }

        try self.assignReg(v, reg);
        return v;
    }

    fn saveEndRegs(self: *RegAllocState, block: *Block) !void {
        var count: usize = 0;
        for (&self.regs) |*r| if (r.v != null) { count += 1; };

        const end_regs = try self.allocator.alloc(EndReg, count);
        var i: usize = 0;
        for (&self.regs, 0..) |*r, reg| {
            if (r.v) |v| {
                end_regs[i] = .{ .reg = @intCast(reg), .v = v, .c = v };
                i += 1;
            }
        }
        try self.end_regs.put(self.allocator, block.id, end_regs);
        debug.log(.regalloc, "  saved endRegs[b{d}]: {d} values", .{ block.id, count });
    }

    fn restoreEndRegs(self: *RegAllocState, pred_id: ID) void {
        for (&self.regs) |*r| r.clear();
        if (self.end_regs.get(pred_id)) |regs| {
            for (regs) |er| self.regs[er.reg] = .{ .v = er.v, .dirty = false };
            debug.log(.regalloc, "  restored from endRegs[b{d}]: {d} values", .{ pred_id, regs.len });
        }
    }

    fn allocatePhis(self: *RegAllocState, block: *Block, primary_pred_idx: usize) !void {
        var phis = std.ArrayListUnmanaged(*Value){};
        defer phis.deinit(self.allocator);

        for (block.values.items) |v| {
            if (v.op == .phi) try phis.append(self.allocator, v) else break;
        }
        if (phis.items.len == 0) return;

        debug.log(.regalloc, "  allocating {d} phis", .{phis.items.len});
        var phi_used: RegMask = 0;
        const phi_regs = try self.allocator.alloc(?RegNum, phis.items.len);
        defer self.allocator.free(phi_regs);
        for (phi_regs) |*r| r.* = null;

        // Pass 1: Reuse primary predecessor's register
        for (phis.items, 0..) |phi, i| {
            if (primary_pred_idx < phi.args.len) {
                const arg = phi.args[primary_pred_idx];
                const arg_regs = self.values[arg.id].regs & ~phi_used & self.allocatable_mask;
                if (arg_regs != 0) {
                    const reg = types.regMaskFirst(arg_regs).?;
                    phi_regs[i] = reg;
                    phi_used |= @as(RegMask, 1) << reg;
                    debug.log(.regalloc, "    phi v{d}: reuse x{d} from arg v{d}", .{ phi.id, reg, arg.id });
                }
            }
        }

        // Pass 2: Fresh registers for remaining
        for (phis.items, 0..) |phi, i| {
            if (phi_regs[i] != null) continue;
            const available = self.allocatable_mask & ~phi_used;
            if (self.findFreeReg(available)) |reg| {
                phi_regs[i] = reg;
                phi_used |= @as(RegMask, 1) << reg;
                debug.log(.regalloc, "    phi v{d}: fresh x{d}", .{ phi.id, reg });
            }
        }

        // Pass 3: Assign
        for (phis.items, 0..) |phi, i| {
            if (phi_regs[i]) |reg| {
                if (self.regs[reg].v != null) self.freeReg(reg);
                try self.assignReg(phi, reg);
            }
        }
    }

    fn allocBlock(self: *RegAllocState, block: *Block) !void {
        debug.log(.regalloc, "Processing block b{d}, {d} values, live.blocks.len={d}", .{
            block.id, block.values.items.len, self.live.blocks.len,
        });
        if (block.id > 0 and block.id <= self.live.blocks.len) {
            const bl = &self.live.blocks[block.id - 1];
            debug.log(.regalloc, "  BlockLiveness live_out.len={d}", .{bl.live_out.len});
        }

        // Initialize from predecessor
        if (block.preds.len == 0) {
            for (&self.regs) |*r| r.clear();
        } else if (block.preds.len == 1) {
            self.restoreEndRegs(block.preds[0].b.id);
        } else {
            var best_pred: ?ID = null;
            for (block.preds) |pred| {
                if (self.end_regs.contains(pred.b.id)) { best_pred = pred.b.id; break; }
            }
            if (best_pred) |pid| self.restoreEndRegs(pid);
        }

        var primary_pred_idx: usize = 0;
        for (block.preds, 0..) |pred, i| {
            if (self.end_regs.contains(pred.b.id)) { primary_pred_idx = i; break; }
        }

        try self.allocatePhis(block, primary_pred_idx);
        try self.buildUseLists(block);

        var new_values = std.ArrayListUnmanaged(*Value){};
        defer new_values.deinit(self.allocator);
        const original_values = try self.allocator.dupe(*Value, block.values.items);
        defer self.allocator.free(original_values);

        for (original_values, 0..) |v, idx| {
            self.cur_idx = idx;
            if (v.op == .phi) { try new_values.append(self.allocator, v); continue; }

            debug.log(.regalloc, "  v{d} = {s}", .{ v.id, @tagName(v.op) });
            self.used = 0;

            // Load arguments into registers
            const max_reg_args: usize = if (v.op.info().call) self.arg_regs.len else v.args.len;
            const args_to_load = @min(v.args.len, max_reg_args);

            for (v.args[0..args_to_load], 0..) |arg, i| {
                if (!self.values[arg.id].inReg()) {
                    const loaded = try self.loadValue(arg, block);
                    if (loaded != arg) {
                        for (self.pending_spills.items) |spill| try new_values.append(self.allocator, spill);
                        self.pending_spills.clearRetainingCapacity();
                        try new_values.append(self.allocator, loaded);
                        v.args[i] = loaded;
                        loaded.uses += 1;
                        debug.log(.regalloc, "    updated arg {d} to v{d}", .{ i, loaded.id });
                    }
                }
                if (self.values[v.args[i].id].firstReg()) |reg| {
                    self.used |= @as(RegMask, 1) << @intCast(reg);
                }
            }

            // Spill caller-saved before calls
            if (v.op.info().call) {
                debug.log(.regalloc, "    CALL - spilling caller-saved (mask=0x{x})", .{self.caller_saved_mask});
                var reg: RegNum = 0;
                while (reg < NUM_REGS) : (reg += 1) {
                    const reg_bit = @as(RegMask, 1) << reg;
                    if ((self.caller_saved_mask & reg_bit) != 0 and self.regs[reg].v != null) {
                        if (try self.spillReg(reg, block)) |spill| try new_values.append(self.allocator, spill);
                    }
                }
            }

            // AMD64 div/mod handling
            if ((v.op == .div or v.op == .mod) and self.target.arch == .amd64) {
                try self.handleAMD64DivMod(v, block, &new_values);
            }

            // AMD64 shift handling
            if ((v.op == .shl or v.op == .shr or v.op == .sar) and self.target.arch == .amd64) {
                if (self.regs[AMD64Regs.rcx].v != null) {
                    debug.log(.regalloc, "    SHIFT - spilling RCX", .{});
                    if (try self.spillReg(AMD64Regs.rcx, block)) |spill| try new_values.append(self.allocator, spill);
                }
            }

            try new_values.append(self.allocator, v);

            // Allocate output register
            if (needsOutputReg(v)) {
                if (v.op.info().call) {
                    if (self.regs[0].v != null) self.freeReg(0);
                    try self.assignReg(v, 0);
                } else if (v.op == .arg) {
                    const arg_idx: usize = @intCast(v.aux_int);
                    if (arg_idx < self.arg_regs.len) {
                        const arg_reg = self.arg_regs[arg_idx];
                        if (self.regs[arg_reg].v != null) {
                            if (try self.spillReg(arg_reg, block)) |spill| try new_values.append(self.allocator, spill);
                        }
                        try self.assignReg(v, arg_reg);
                    } else {
                        const reg = try self.allocReg(self.allocatable_mask, block);
                        try self.assignReg(v, reg);
                    }
                } else {
                    const reg = try self.allocReg(self.allocatable_mask, block);
                    try self.assignReg(v, reg);
                }
            }

            // Insert pending spills before the value
            if (self.pending_spills.items.len > 0) {
                var insert_pos = new_values.items.len;
                while (insert_pos > 0 and new_values.items[insert_pos - 1] != v) insert_pos -= 1;
                if (insert_pos > 0 and new_values.items[insert_pos - 1] == v) {
                    insert_pos -= 1;
                    for (self.pending_spills.items) |spill| {
                        try new_values.insert(self.allocator, insert_pos, spill);
                        insert_pos += 1;
                    }
                    self.pending_spills.clearRetainingCapacity();
                }
            }

            self.advanceUses(v);
        }

        // Handle control values
        for (block.controlValues()) |ctrl| {
            if (!self.values[ctrl.id].inReg()) {
                const loaded = try self.loadValue(ctrl, block);
                if (loaded != ctrl) {
                    for (self.pending_spills.items) |spill| try new_values.append(self.allocator, spill);
                    self.pending_spills.clearRetainingCapacity();
                    try new_values.append(self.allocator, loaded);
                    block.setControl(loaded);
                    debug.log(.regalloc, "  updated control to v{d}", .{loaded.id});
                }
            }
        }

        debug.log(.regalloc, "  about to deinit block.values", .{});
        block.values.deinit(self.allocator);
        debug.log(.regalloc, "  about to reset block.values", .{});
        block.values = .{};
        debug.log(.regalloc, "  about to appendSlice, live.blocks.ptr still valid? checking...", .{});
        debug.log(.regalloc, "  live.blocks.len={d}", .{self.live.blocks.len});
        try block.values.appendSlice(self.allocator, new_values.items);
        debug.log(.regalloc, "  appendSlice done, live.blocks.len={d}", .{self.live.blocks.len});
        try self.saveEndRegs(block);
        debug.log(.regalloc, "  saveEndRegs done, live.blocks.len={d}", .{self.live.blocks.len});
        if (block.id > 0 and block.id <= self.live.blocks.len) {
            const bl = &self.live.blocks[block.id - 1];
            debug.log(.regalloc, "  blocks[{d}].live_out.len={d}", .{ block.id - 1, bl.live_out.len });
        }

        // Compute spillLive
        debug.log(.regalloc, "  computing spillLive for b{d}, about to call getLiveOut", .{block.id});
        const spill_live_out = self.live.getLiveOut(block.id);
        debug.log(.regalloc, "  spillLive: got {d} live values", .{spill_live_out.len});
        for (spill_live_out) |info| {
            if (info.id >= self.values.len) continue;
            const vi = &self.values[info.id];
            if (vi.rematerializeable) continue;
            if (vi.spill) |spill| {
                var list = self.spill_live.get(block.id) orelse std.ArrayListUnmanaged(ID){};
                try list.append(self.allocator, spill.id);
                try self.spill_live.put(self.allocator, block.id, list);
            }
        }
    }

    fn handleAMD64DivMod(self: *RegAllocState, v: *Value, block: *Block, new_values: *std.ArrayListUnmanaged(*Value)) !void {
        // Relocate divisor if in RAX
        if (v.args.len >= 2) {
            const divisor = v.args[1];
            const divisor_vi = &self.values[divisor.id];
            if (divisor_vi.inReg() and (divisor_vi.regs & (@as(RegMask, 1) << AMD64Regs.rax)) != 0) {
                const forbidden: RegMask = (@as(RegMask, 1) << AMD64Regs.rax) | (@as(RegMask, 1) << AMD64Regs.rdx);
                const new_reg = try self.allocReg(self.allocatable_mask & ~forbidden, block);
                debug.log(.regalloc, "    DIV/MOD - relocating divisor v{d} from RAX to x{d}", .{ divisor.id, new_reg });

                const copy = try self.f.newValue(.copy, divisor.type_idx, block, divisor.pos);
                copy.addArg(divisor);
                try self.ensureValState(copy);
                try self.f.setHome(copy, .{ .register = @intCast(new_reg) });
                self.values[copy.id].regs = types.regMaskSet(0, new_reg);
                self.regs[new_reg] = .{ .v = copy, .dirty = true };
                self.freeReg(AMD64Regs.rax);
                v.args[1] = copy;
                try new_values.append(self.allocator, copy);
            }
        }

        // Spill RAX if not dividend
        if (self.regs[AMD64Regs.rax].v) |rax_val| {
            if (v.args.len == 0 or v.args[0] != rax_val) {
                debug.log(.regalloc, "    DIV/MOD - spilling RAX", .{});
                if (try self.spillReg(AMD64Regs.rax, block)) |spill| try new_values.append(self.allocator, spill);
            }
        }

        // Spill RDX (clobbered by CQO)
        if (self.regs[AMD64Regs.rdx].v) |rdx_val| {
            if (v.args.len == 0 or v.args[0] != rdx_val) {
                debug.log(.regalloc, "    DIV/MOD - spilling RDX", .{});
                if (try self.spillReg(AMD64Regs.rdx, block)) |spill| try new_values.append(self.allocator, spill);
            }
        }
    }

    fn shuffle(self: *RegAllocState) !void {
        debug.log(.regalloc, "=== Shuffle phase ===", .{});
        for (self.f.blocks.items) |block| {
            if (block.preds.len <= 1) continue;
            debug.log(.regalloc, "Shuffle for merge block b{d}", .{block.id});
            for (block.preds, 0..) |pred, pred_idx| {
                try self.shuffleEdge(pred.b, block, pred_idx);
            }
        }
    }

    fn shuffleEdge(self: *RegAllocState, pred: *Block, succ: *Block, pred_idx: usize) !void {
        const src_regs = self.end_regs.get(pred.id) orelse return;

        var contents: [NUM_REGS]?*Value = [_]?*Value{null} ** NUM_REGS;
        for (src_regs) |er| contents[er.reg] = er.v;

        const Dest = struct { dst_reg: RegNum, src_reg: ?RegNum, value: *Value, satisfied: bool };
        var dests = std.ArrayListUnmanaged(Dest){};
        defer dests.deinit(self.allocator);

        for (succ.values.items) |v| {
            if (v.op != .phi) break;
            const phi_reg = self.values[v.id].firstReg() orelse blk: {
                if (v.args.len > 0 and succ.preds.len > 0) {
                    if (self.end_regs.get(succ.preds[0].b.id)) |first_pred_regs| {
                        for (first_pred_regs) |er| {
                            if (er.v.id == v.args[0].id) break :blk er.reg;
                        }
                    }
                }
                continue;
            };
            if (pred_idx >= v.args.len) continue;

            const arg = v.args[pred_idx];
            var arg_reg: ?RegNum = null;
            for (contents, 0..) |maybe_val, reg_idx| {
                if (maybe_val) |val| if (val.id == arg.id) { arg_reg = @intCast(reg_idx); break; };
            }

            if (arg_reg != phi_reg) {
                try dests.append(self.allocator, .{ .dst_reg = phi_reg, .src_reg = arg_reg, .value = arg, .satisfied = false });
                debug.log(.regalloc, "  need move: v{d} x{?d} -> x{d}", .{ arg.id, arg_reg, phi_reg });
            }
        }

        if (dests.items.len == 0) return;

        var used_regs: RegMask = 0;
        for (dests.items) |d| used_regs |= @as(RegMask, 1) << d.dst_reg;

        var progress = true;
        while (progress) {
            progress = false;
            for (dests.items) |*d| {
                if (d.satisfied) continue;
                var blocked = false;
                for (dests.items) |other| {
                    if (other.satisfied) continue;
                    if (other.src_reg) |src| if (src == d.dst_reg and other.dst_reg != d.dst_reg) { blocked = true; break; };
                }

                if (!blocked) {
                    if (d.src_reg) |src| {
                        try self.emitCopy(pred, d.value, src, d.dst_reg);
                    } else {
                        try self.emitRematerialize(pred, d.value, d.dst_reg);
                    }
                    d.satisfied = true;
                    progress = true;
                }
            }

            if (!progress) {
                for (dests.items) |*d| {
                    if (!d.satisfied) {
                        if (d.src_reg) |src| {
                            const temp_reg = self.findTempReg(used_regs) orelse return error.NoTempRegister;
                            debug.log(.regalloc, "  breaking cycle: x{d} -> x{d} -> x{d}", .{ src, temp_reg, d.dst_reg });

                            const temp_copy = try self.f.newValue(.copy, d.value.type_idx, pred, d.value.pos);
                            temp_copy.addArg(d.value);
                            try self.ensureValState(temp_copy);
                            self.values[temp_copy.id].regs = types.regMaskSet(0, temp_reg);
                            try self.f.setHome(temp_copy, .{ .register = @intCast(temp_reg) });
                            try pred.values.append(self.allocator, temp_copy);
                            contents[temp_reg] = d.value;
                            d.src_reg = temp_reg;
                        } else {
                            try self.emitRematerialize(pred, d.value, d.dst_reg);
                            d.satisfied = true;
                        }
                        progress = true;
                        break;
                    }
                }
            }
        }
    }

    fn emitCopy(self: *RegAllocState, block: *Block, value: *Value, src_reg: RegNum, dst_reg: RegNum) !void {
        if (src_reg == dst_reg) return;
        const copy = try self.f.newValue(.copy, value.type_idx, block, value.pos);
        copy.addArg(value);
        try self.ensureValState(copy);
        self.values[copy.id].regs = types.regMaskSet(0, dst_reg);
        try self.f.setHome(copy, .{ .register = @intCast(dst_reg) });
        try block.values.append(self.allocator, copy);
        debug.log(.regalloc, "  emit copy v{d} -> v{d} (x{d} -> x{d})", .{ value.id, copy.id, src_reg, dst_reg });
    }

    fn emitRematerialize(self: *RegAllocState, block: *Block, value: *Value, dst_reg: RegNum) !void {
        switch (value.op) {
            .const_bool, .const_int, .const_64, .const_nil => {
                const remat = try self.f.newValue(value.op, value.type_idx, block, value.pos);
                remat.aux_int = value.aux_int;
                remat.aux = value.aux;
                try self.ensureValState(remat);
                self.values[remat.id].regs = types.regMaskSet(0, dst_reg);
                try self.f.setHome(remat, .{ .register = @intCast(dst_reg) });
                try block.values.append(self.allocator, remat);
                debug.log(.regalloc, "  emit remat v{d} -> v{d} ({s} -> x{d})", .{ value.id, remat.id, @tagName(value.op), dst_reg });
            },
            else => {
                const copy = try self.f.newValue(.copy, value.type_idx, block, value.pos);
                copy.addArg(value);
                try self.ensureValState(copy);
                self.values[copy.id].regs = types.regMaskSet(0, dst_reg);
                try self.f.setHome(copy, .{ .register = @intCast(dst_reg) });
                try block.values.append(self.allocator, copy);
                debug.log(.regalloc, "  emit fallback copy v{d} -> v{d} (x{d})", .{ value.id, copy.id, dst_reg });
            },
        }
    }

    fn ensureValState(self: *RegAllocState, v: *Value) !void {
        if (v.id >= self.values.len) {
            const old_len = self.values.len;
            self.values = try self.allocator.realloc(self.values, v.id + 1);
            for (old_len..self.values.len) |i| self.values[i] = .{};
        }
    }

    fn findTempReg(self: *const RegAllocState, exclude: RegMask) ?RegNum {
        const available = self.allocatable_mask & ~exclude;
        var m = available;
        while (m != 0) {
            const reg: RegNum = @intCast(@ctz(m));
            m &= m - 1;
            if (reg < NUM_REGS and self.regs[reg].isFree()) return reg;
        }
        if (exclude & (@as(RegMask, 1) << 16) == 0) return 16;
        return null;
    }

    pub fn run(self: *RegAllocState) !void {
        debug.log(.regalloc, "=== Register Allocation ===", .{});

        for (self.f.blocks.items) |block| {
            for (block.values.items) |v| {
                if (v.id < self.values.len) {
                    self.values[v.id].rematerializeable = isRematerializeable(v);
                    self.values[v.id].needs_reg = valueNeedsReg(v);
                }
            }
        }

        for (self.f.blocks.items) |block| try self.allocBlock(block);
        try self.shuffle();
        debug.log(.regalloc, "=== Regalloc complete: {d} spills ===", .{self.num_spills});
    }
};

fn needsOutputReg(v: *Value) bool {
    return switch (v.op) {
        .store, .store_reg => false,
        else => true,
    };
}

fn isRematerializeable(v: *Value) bool {
    return switch (v.op) {
        .const_int, .const_64, .const_bool, .local_addr => true,
        else => false,
    };
}

fn valueNeedsReg(v: *Value) bool {
    return switch (v.op) {
        .store, .store_reg => false,
        else => true,
    };
}

pub fn regalloc(allocator: std.mem.Allocator, f: *Func, target: Target) !RegAllocState {
    var live = try liveness.computeLiveness(allocator, f);
    errdefer live.deinit();
    var state = try RegAllocState.init(allocator, f, live, target);
    errdefer state.deinit();
    try state.run();
    return state;
}

test "basic allocation" {
    // TODO: Add tests
}
