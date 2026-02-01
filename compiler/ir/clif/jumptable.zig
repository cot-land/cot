//! Jump table representation.
//!
//! Port of cranelift/codegen/src/ir/jumptable.rs
//!
//! Jump tables are declared in the preamble and assigned a `JumpTable` reference.
//! The actual table of destinations is stored in a `JumpTableData` struct.

const std = @import("std");
const dfg_mod = @import("dfg.zig");

pub const Block = dfg_mod.Block;
pub const Value = dfg_mod.Value;
pub const JumpTable = dfg_mod.JumpTable;
pub const ValueList = dfg_mod.ValueList;
pub const ValueListPool = dfg_mod.ValueListPool;

// ============================================================================
// BlockCall
// Port of cranelift/codegen/src/ir/instructions.rs BlockCall
// Simplified to just store block target and arguments as a value list.
// ============================================================================

/// A block reference with optional arguments.
///
/// Used in jump tables and branch instructions to represent
/// a target block with block parameters.
pub const BlockCall = struct {
    /// Target block.
    block: Block,
    /// Block arguments.
    args: ValueList,

    const Self = @This();

    /// Create a new block call with no arguments.
    pub fn init(block: Block) Self {
        return .{
            .block = block,
            .args = ValueList.init(),
        };
    }

    /// Create a new block call with arguments.
    pub fn withArgs(block: Block, args_list: ValueList) Self {
        return .{
            .block = block,
            .args = args_list,
        };
    }

    /// Create a new block call with arguments from a slice.
    pub fn withArgsSlice(block: Block, args: []const Value, pool: *ValueListPool) !Self {
        var args_list = ValueList.init();
        for (args) |v| {
            args_list = try pool.push(args_list, v);
        }
        return .{
            .block = block,
            .args = args_list,
        };
    }

    /// Get the target block.
    pub fn getBlock(self: Self) Block {
        return self.block;
    }

    /// Get the arguments as a slice.
    pub fn getArgs(self: Self, pool: *const ValueListPool) []const Value {
        return pool.getSlice(self.args);
    }

    /// Get the number of arguments.
    pub fn argLen(self: Self, pool: *const ValueListPool) usize {
        return pool.len(self.args);
    }

    /// Format for display.
    pub fn format(
        self: Self,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        try writer.print("block{d}", .{self.block.asU32()});
        // Note: args would need pool to format, simplified here
    }
};

// ============================================================================
// JumpTableData
// Port of cranelift/codegen/src/ir/jumptable.rs JumpTableData
// ============================================================================

/// Contents of a jump table.
///
/// All jump tables use 0-based indexing and are densely populated.
/// The default block is stored separately from the indexed entries.
pub const JumpTableData = struct {
    /// Default block (taken when index is out of bounds).
    default_block: BlockCall,
    /// Table entries (indexed from 0).
    entries: std.ArrayListUnmanaged(BlockCall),

    const Self = @This();

    /// Create a new jump table with the given default block.
    pub fn init(default: BlockCall) Self {
        return .{
            .default_block = default,
            .entries = .{},
        };
    }

    /// Create a new jump table with default block and entries.
    pub fn initWithEntries(allocator: std.mem.Allocator, default: BlockCall, table: []const BlockCall) !Self {
        var entries: std.ArrayListUnmanaged(BlockCall) = .{};
        try entries.appendSlice(allocator, table);
        return .{
            .default_block = default,
            .entries = entries,
        };
    }

    /// Deallocate storage.
    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        self.entries.deinit(allocator);
    }

    /// Get the default block.
    pub fn getDefaultBlock(self: Self) BlockCall {
        return self.default_block;
    }

    /// Set the default block.
    pub fn setDefaultBlock(self: *Self, default: BlockCall) void {
        self.default_block = default;
    }

    /// Get all branches (default + entries).
    pub fn allBranches(self: *const Self) AllBranchesIterator {
        return AllBranchesIterator{
            .data = self,
            .index = 0,
        };
    }

    /// Get table entries (excluding default).
    pub fn asSlice(self: Self) []const BlockCall {
        return self.entries.items;
    }

    /// Get mutable table entries (excluding default).
    pub fn asMutSlice(self: *Self) []BlockCall {
        return self.entries.items;
    }

    /// Get the number of entries (excluding default).
    pub fn len(self: Self) usize {
        return self.entries.items.len;
    }

    /// Check if the table is empty (excluding default).
    pub fn isEmpty(self: Self) bool {
        return self.entries.items.len == 0;
    }

    /// Get entry at index.
    pub fn get(self: Self, index: usize) ?BlockCall {
        if (index >= self.entries.items.len) return null;
        return self.entries.items[index];
    }

    /// Append an entry.
    pub fn push(self: *Self, allocator: std.mem.Allocator, entry: BlockCall) !void {
        try self.entries.append(allocator, entry);
    }

    /// Clear all entries (but keep default).
    pub fn clear(self: *Self) void {
        self.entries.clearRetainingCapacity();
    }
};

/// Iterator over all branches (default first, then entries).
pub const AllBranchesIterator = struct {
    data: *const JumpTableData,
    index: usize,

    pub fn next(self: *AllBranchesIterator) ?BlockCall {
        if (self.index == 0) {
            self.index = 1;
            return self.data.default_block;
        }
        const entry_index = self.index - 1;
        if (entry_index >= self.data.entries.items.len) {
            return null;
        }
        self.index += 1;
        return self.data.entries.items[entry_index];
    }
};

// ============================================================================
// Jump Tables Collection
// For storing multiple jump tables in a function.
// ============================================================================

/// Collection of jump tables for a function.
pub const JumpTables = struct {
    tables: std.ArrayListUnmanaged(JumpTableData),
    allocator: std.mem.Allocator,

    const Self = @This();

    /// Create a new empty collection.
    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .tables = .{},
            .allocator = allocator,
        };
    }

    /// Deallocate storage.
    pub fn deinit(self: *Self) void {
        for (self.tables.items) |*table| {
            table.deinit(self.allocator);
        }
        self.tables.deinit(self.allocator);
    }

    /// Clear all tables.
    pub fn clear(self: *Self) void {
        for (self.tables.items) |*table| {
            table.deinit(self.allocator);
        }
        self.tables.clearRetainingCapacity();
    }

    /// Create a new jump table.
    pub fn create(self: *Self, data: JumpTableData) !JumpTable {
        const index: u32 = @intCast(self.tables.items.len);
        try self.tables.append(self.allocator, data);
        return JumpTable.fromIndex(index);
    }

    /// Get a jump table by reference.
    pub fn get(self: Self, jt: JumpTable) ?*const JumpTableData {
        const index = jt.asU32();
        if (index >= self.tables.items.len) return null;
        return &self.tables.items[index];
    }

    /// Get a mutable jump table by reference.
    pub fn getMut(self: *Self, jt: JumpTable) ?*JumpTableData {
        const index = jt.asU32();
        if (index >= self.tables.items.len) return null;
        return &self.tables.items[index];
    }

    /// Get the number of jump tables.
    pub fn len(self: Self) usize {
        return self.tables.items.len;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "block call creation" {
    const testing = std.testing;

    const block0 = Block.fromIndex(0);
    const call = BlockCall.init(block0);

    try testing.expectEqual(block0, call.getBlock());
}

test "jump table empty" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const block0 = Block.fromIndex(0);
    const def = BlockCall.init(block0);

    var jt = JumpTableData.init(def);
    defer jt.deinit(allocator);

    try testing.expectEqual(def.block, jt.getDefaultBlock().block);
    try testing.expectEqual(@as(usize, 0), jt.len());
    try testing.expect(jt.isEmpty());

    // Check all branches iterator
    var iter = jt.allBranches();
    const first = iter.next();
    try testing.expect(first != null);
    try testing.expectEqual(block0, first.?.block);
    try testing.expect(iter.next() == null);
}

test "jump table with entries" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const block0 = Block.fromIndex(0);
    const block1 = Block.fromIndex(1);
    const block2 = Block.fromIndex(2);

    const def = BlockCall.init(block0);
    const b1 = BlockCall.init(block1);
    const b2 = BlockCall.init(block2);

    var jt = try JumpTableData.initWithEntries(allocator, def, &[_]BlockCall{ b1, b2 });
    defer jt.deinit(allocator);

    try testing.expectEqual(block0, jt.getDefaultBlock().block);
    try testing.expectEqual(@as(usize, 2), jt.len());
    try testing.expect(!jt.isEmpty());

    // Check entries
    try testing.expectEqual(block1, jt.get(0).?.block);
    try testing.expectEqual(block2, jt.get(1).?.block);
    try testing.expect(jt.get(2) == null);

    // Check as_slice
    const slice = jt.asSlice();
    try testing.expectEqual(@as(usize, 2), slice.len);
    try testing.expectEqual(block1, slice[0].block);
    try testing.expectEqual(block2, slice[1].block);
}

test "jump tables collection" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var tables = JumpTables.init(allocator);
    defer tables.deinit();

    const block0 = Block.fromIndex(0);
    const block1 = Block.fromIndex(1);

    const def = BlockCall.init(block0);
    const b1 = BlockCall.init(block1);

    // Create first table
    const jt0 = try tables.create(JumpTableData.init(def));
    try testing.expectEqual(@as(u32, 0), jt0.asU32());

    // Create second table with entries
    const data = try JumpTableData.initWithEntries(allocator, def, &[_]BlockCall{b1});
    const jt1 = try tables.create(data);
    _ = jt1;
    // Note: data is moved into tables, so we shouldn't deinit it here

    try testing.expectEqual(@as(usize, 2), tables.len());

    // Check retrieval
    const retrieved = tables.get(jt0);
    try testing.expect(retrieved != null);
    try testing.expectEqual(block0, retrieved.?.getDefaultBlock().block);
}
