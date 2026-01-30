//! Core types used throughout the compiler.
//! Reference: Go cmd/compile/internal/ssa/ and types/

const std = @import("std");

/// Unique identifier for SSA values and blocks. 0 = invalid.
pub const ID = u32;
pub const INVALID_ID: ID = 0;

/// Type index into type registry. 0 = invalid.
pub const TypeIndex = u32;
pub const INVALID_TYPE: TypeIndex = 0;

/// Type category.
pub const TypeKind = enum {
    // Language types
    invalid,
    void_type,
    bool_type,
    int_type, // i8, i16, i32, i64
    uint_type, // u8, u16, u32, u64
    float_type, // f32, f64
    string_type, // ptr + len (16 bytes)
    pointer_type,
    optional_type,
    array_type,
    slice_type, // ptr + len
    struct_type,
    enum_type,
    union_type,
    function_type,
    // SSA pseudo-types (for regalloc)
    ssa_mem,
    ssa_flags,
    ssa_tuple,
    ssa_results,
};

/// Field in a struct type.
pub const FieldInfo = struct {
    name: []const u8,
    type_idx: TypeIndex,
    offset: u32,
    size: u32,
};

/// Complete type information.
pub const TypeInfo = struct {
    kind: TypeKind,
    size: u32,
    alignment: u32,
    element_type: TypeIndex = INVALID_TYPE,
    array_len: u32 = 0,
    fields: ?[]const FieldInfo = null,
    backing_type: TypeIndex = INVALID_TYPE,
    param_types: ?[]const TypeIndex = null,
    return_type: TypeIndex = INVALID_TYPE,

    pub inline fn sizeOf(self: TypeInfo) u32 {
        return self.size;
    }

    pub inline fn alignOf(self: TypeInfo) u32 {
        return self.alignment;
    }

    pub inline fn fitsInRegs(self: TypeInfo) bool {
        return self.size <= 16;
    }

    pub inline fn needsReg(self: TypeInfo) bool {
        return self.kind != .ssa_mem and self.kind != .ssa_flags and self.kind != .void_type;
    }

    /// How many registers for parameter passing (string/slice = 2)
    pub fn registerCount(self: TypeInfo) u32 {
        if (self.kind == .string_type or self.kind == .slice_type) return 2;
        if (self.size <= 8) return 1;
        if (self.size <= 16) return 2;
        return 1; // >16 bytes passed by pointer
    }

    pub fn getField(self: TypeInfo, name: []const u8) ?FieldInfo {
        const fields = self.fields orelse return null;
        for (fields) |f| if (std.mem.eql(u8, f.name, name)) return f;
        return null;
    }

    pub fn getFieldByIndex(self: TypeInfo, index: usize) ?FieldInfo {
        const fields = self.fields orelse return null;
        return if (index < fields.len) fields[index] else null;
    }
};

/// Source position.
pub const Pos = struct {
    line: u32 = 0,
    col: u32 = 0,
    file: u16 = 0,
};

/// Register mask - bit i means register i is in set.
pub const RegMask = u64;
pub const RegNum = u6;

pub inline fn regMaskSet(mask: RegMask, reg: RegNum) RegMask {
    return mask | (@as(RegMask, 1) << reg);
}

pub inline fn regMaskClear(mask: RegMask, reg: RegNum) RegMask {
    return mask & ~(@as(RegMask, 1) << reg);
}

pub inline fn regMaskContains(mask: RegMask, reg: RegNum) bool {
    return (mask & (@as(RegMask, 1) << reg)) != 0;
}

pub inline fn regMaskCount(mask: RegMask) u32 {
    return @popCount(mask);
}

pub inline fn regMaskFirst(mask: RegMask) ?RegNum {
    return if (mask == 0) null else @truncate(@ctz(mask));
}

pub const RegMaskIterator = struct {
    mask: RegMask,

    pub fn next(self: *RegMaskIterator) ?RegNum {
        if (self.mask == 0) return null;
        const reg: RegNum = @truncate(@ctz(self.mask));
        self.mask &= self.mask - 1;
        return reg;
    }
};

pub inline fn regMaskIterator(mask: RegMask) RegMaskIterator {
    return .{ .mask = mask };
}

/// ID allocator for values and blocks.
pub const IDAllocator = struct {
    next_id: ID = 1,

    pub fn next(self: *IDAllocator) ID {
        const id = self.next_id;
        self.next_id += 1;
        return id;
    }

    pub fn reset(self: *IDAllocator) void {
        self.next_id = 1;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "IDAllocator" {
    var alloc = IDAllocator{};
    try std.testing.expectEqual(@as(ID, 1), alloc.next());
    try std.testing.expectEqual(@as(ID, 2), alloc.next());
    try std.testing.expectEqual(@as(ID, 3), alloc.next());
    alloc.reset();
    try std.testing.expectEqual(@as(ID, 1), alloc.next());
}

test "RegMask operations" {
    var mask: RegMask = 0;
    mask = regMaskSet(mask, 0);
    try std.testing.expect(regMaskContains(mask, 0));
    try std.testing.expect(!regMaskContains(mask, 1));

    mask = regMaskSet(mask, 5);
    try std.testing.expectEqual(@as(u32, 2), regMaskCount(mask));

    mask = regMaskClear(mask, 0);
    try std.testing.expect(!regMaskContains(mask, 0));
    try std.testing.expect(regMaskContains(mask, 5));
}

test "RegMaskIterator" {
    var mask: RegMask = 0;
    mask = regMaskSet(mask, 0);
    mask = regMaskSet(mask, 3);
    mask = regMaskSet(mask, 7);

    var it = regMaskIterator(mask);
    try std.testing.expectEqual(@as(?RegNum, 0), it.next());
    try std.testing.expectEqual(@as(?RegNum, 3), it.next());
    try std.testing.expectEqual(@as(?RegNum, 7), it.next());
    try std.testing.expectEqual(@as(?RegNum, null), it.next());
}

test "TypeInfo sizes" {
    const void_t = TypeInfo{ .kind = .void_type, .size = 0, .alignment = 1 };
    const bool_t = TypeInfo{ .kind = .bool_type, .size = 1, .alignment = 1 };
    const i64_t = TypeInfo{ .kind = .int_type, .size = 8, .alignment = 8 };
    const string_t = TypeInfo{ .kind = .string_type, .size = 16, .alignment = 8 };

    try std.testing.expectEqual(@as(u32, 0), void_t.sizeOf());
    try std.testing.expectEqual(@as(u32, 1), bool_t.sizeOf());
    try std.testing.expectEqual(@as(u32, 8), i64_t.sizeOf());
    try std.testing.expectEqual(@as(u32, 16), string_t.sizeOf());
}

test "TypeInfo registerCount" {
    const i64_t = TypeInfo{ .kind = .int_type, .size = 8, .alignment = 8 };
    const string_t = TypeInfo{ .kind = .string_type, .size = 16, .alignment = 8 };
    const large_t = TypeInfo{ .kind = .struct_type, .size = 24, .alignment = 8 };

    try std.testing.expectEqual(@as(u32, 1), i64_t.registerCount());
    try std.testing.expectEqual(@as(u32, 2), string_t.registerCount()); // ptr + len
    try std.testing.expectEqual(@as(u32, 1), large_t.registerCount()); // passed by pointer
}

test "TypeInfo fitsInRegs" {
    const small = TypeInfo{ .kind = .int_type, .size = 8, .alignment = 8 };
    const medium = TypeInfo{ .kind = .struct_type, .size = 16, .alignment = 8 };
    const large = TypeInfo{ .kind = .struct_type, .size = 24, .alignment = 8 };

    try std.testing.expect(small.fitsInRegs());
    try std.testing.expect(medium.fitsInRegs());
    try std.testing.expect(!large.fitsInRegs());
}

test "TypeInfo needsReg" {
    const int_t = TypeInfo{ .kind = .int_type, .size = 8, .alignment = 8 };
    const mem_t = TypeInfo{ .kind = .ssa_mem, .size = 0, .alignment = 1 };
    const void_t = TypeInfo{ .kind = .void_type, .size = 0, .alignment = 1 };

    try std.testing.expect(int_t.needsReg());
    try std.testing.expect(!mem_t.needsReg());
    try std.testing.expect(!void_t.needsReg());
}

test "TypeInfo getField" {
    const fields = [_]FieldInfo{
        .{ .name = "x", .type_idx = 5, .offset = 0, .size = 8 },
        .{ .name = "y", .type_idx = 5, .offset = 8, .size = 8 },
    };
    const point = TypeInfo{
        .kind = .struct_type,
        .size = 16,
        .alignment = 8,
        .fields = &fields,
    };

    try std.testing.expectEqual(@as(u32, 0), point.getField("x").?.offset);
    try std.testing.expectEqual(@as(u32, 8), point.getField("y").?.offset);
    try std.testing.expect(point.getField("z") == null);
}

test "TypeInfo getFieldByIndex" {
    const fields = [_]FieldInfo{
        .{ .name = "a", .type_idx = 6, .offset = 0, .size = 1 },
        .{ .name = "b", .type_idx = 5, .offset = 8, .size = 8 },
    };
    const s = TypeInfo{ .kind = .struct_type, .size = 16, .alignment = 8, .fields = &fields };

    try std.testing.expectEqual(@as(u32, 0), s.getFieldByIndex(0).?.offset);
    try std.testing.expectEqual(@as(u32, 8), s.getFieldByIndex(1).?.offset);
    try std.testing.expect(s.getFieldByIndex(2) == null);
}
