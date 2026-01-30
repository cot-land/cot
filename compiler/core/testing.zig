//! Testing utilities for allocation tracking.

const std = @import("std");

/// Counting allocator wrapper for tracking allocations in tests.
pub const CountingAllocator = struct {
    inner: std.mem.Allocator,
    alloc_count: usize = 0,
    free_count: usize = 0,
    resize_count: usize = 0,
    bytes_allocated: usize = 0,
    bytes_freed: usize = 0,

    pub fn init(inner: std.mem.Allocator) CountingAllocator {
        return .{ .inner = inner };
    }

    pub fn allocator(self: *CountingAllocator) std.mem.Allocator {
        return .{ .ptr = self, .vtable = &vtable };
    }

    pub fn reset(self: *CountingAllocator) void {
        self.alloc_count = 0;
        self.free_count = 0;
        self.resize_count = 0;
        self.bytes_allocated = 0;
        self.bytes_freed = 0;
    }

    pub fn netBytes(self: CountingAllocator) i64 {
        return @as(i64, @intCast(self.bytes_allocated)) - @as(i64, @intCast(self.bytes_freed));
    }

    const vtable = std.mem.Allocator.VTable{
        .alloc = alloc,
        .resize = resize,
        .remap = remap,
        .free = free,
    };

    fn alloc(ctx: *anyopaque, len: usize, ptr_align: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
        const result = self.inner.rawAlloc(len, ptr_align, ret_addr);
        if (result != null) {
            self.alloc_count += 1;
            self.bytes_allocated += len;
        }
        return result;
    }

    fn resize(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
        const old_len = buf.len;
        const result = self.inner.rawResize(buf, buf_align, new_len, ret_addr);
        if (result) {
            self.resize_count += 1;
            if (new_len > old_len) self.bytes_allocated += new_len - old_len else self.bytes_freed += old_len - new_len;
        }
        return result;
    }

    fn remap(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
        const old_len = buf.len;
        const result = self.inner.rawRemap(buf, buf_align, new_len, ret_addr);
        if (result != null) {
            self.resize_count += 1;
            if (new_len > old_len) self.bytes_allocated += new_len - old_len else self.bytes_freed += old_len - new_len;
        }
        return result;
    }

    fn free(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, ret_addr: usize) void {
        const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
        self.free_count += 1;
        self.bytes_freed += buf.len;
        self.inner.rawFree(buf, buf_align, ret_addr);
    }
};

/// Run a function and count allocations.
pub fn countAllocs(inner: std.mem.Allocator, comptime func: anytype, args: anytype) !struct { result: @typeInfo(@TypeOf(func)).@"fn".return_type.?, allocs: usize } {
    var counting = CountingAllocator.init(inner);
    const alloc = counting.allocator();
    var modified_args = args;
    modified_args[0] = alloc;
    const result = try @call(.auto, func, modified_args);
    return .{ .result = result, .allocs = counting.alloc_count };
}

// ============================================================================
// Tests
// ============================================================================

test "CountingAllocator counts allocations" {
    var counting = CountingAllocator.init(std.testing.allocator);
    const alloc = counting.allocator();

    const slice = try alloc.alloc(u8, 100);
    try std.testing.expectEqual(@as(usize, 1), counting.alloc_count);
    try std.testing.expectEqual(@as(usize, 100), counting.bytes_allocated);

    alloc.free(slice);
    try std.testing.expectEqual(@as(usize, 1), counting.free_count);
    try std.testing.expectEqual(@as(usize, 100), counting.bytes_freed);
    try std.testing.expectEqual(@as(i64, 0), counting.netBytes());
}

test "CountingAllocator reset" {
    var counting = CountingAllocator.init(std.testing.allocator);
    const alloc = counting.allocator();

    const slice = try alloc.alloc(u8, 50);
    alloc.free(slice);
    try std.testing.expect(counting.alloc_count > 0);

    counting.reset();
    try std.testing.expectEqual(@as(usize, 0), counting.alloc_count);
    try std.testing.expectEqual(@as(usize, 0), counting.free_count);
    try std.testing.expectEqual(@as(usize, 0), counting.bytes_allocated);
}
