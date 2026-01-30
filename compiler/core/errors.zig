//! Compilation error types with context.

const std = @import("std");
const types = @import("types.zig");

const ID = types.ID;
const Pos = types.Pos;

/// Compilation error with context - follows builder pattern.
pub const CompileError = struct {
    kind: ErrorKind,
    context: []const u8,
    block_id: ?ID = null,
    value_id: ?ID = null,
    source_pos: ?Pos = null,
    pass_name: ?[]const u8 = null,

    pub const ErrorKind = enum {
        // SSA structure
        invalid_block_id,
        invalid_value_id,
        edge_invariant_violated,
        use_count_mismatch,
        block_membership_error,
        // Types
        type_mismatch,
        invalid_type,
        // Passes
        pass_failed,
        pass_not_found,
        dependency_not_satisfied,
        // Resources
        out_of_memory,
        allocation_failed,
        // Codegen
        invalid_instruction,
        register_allocation_failed,
        unsupported_operation,
    };

    pub fn init(kind: ErrorKind, context: []const u8) CompileError {
        return .{ .kind = kind, .context = context };
    }

    pub fn withBlock(self: CompileError, block_id: ID) CompileError {
        var e = self;
        e.block_id = block_id;
        return e;
    }

    pub fn withValue(self: CompileError, value_id: ID) CompileError {
        var e = self;
        e.value_id = value_id;
        return e;
    }

    pub fn withPos(self: CompileError, pos: Pos) CompileError {
        var e = self;
        e.source_pos = pos;
        return e;
    }

    pub fn withPass(self: CompileError, pass_name: []const u8) CompileError {
        var e = self;
        e.pass_name = pass_name;
        return e;
    }

    pub fn format(self: CompileError, comptime _: []const u8, _: std.fmt.FormatOptions, w: anytype) !void {
        try w.print("{s}: {s}", .{ @tagName(self.kind), self.context });
        if (self.pass_name) |n| try w.print(" [pass: {s}]", .{n});
        if (self.block_id) |b| try w.print(" (block b{d})", .{b});
        if (self.value_id) |v| try w.print(" (value v{d})", .{v});
        if (self.source_pos) |p| {
            if (p.line > 0) {
                try w.print(" at line {d}", .{p.line});
                if (p.col > 0) try w.print(":{d}", .{p.col});
            }
        }
    }

    pub fn toError(self: CompileError) Error {
        return switch (self.kind) {
            .invalid_block_id => error.InvalidBlockId,
            .invalid_value_id => error.InvalidValueId,
            .edge_invariant_violated => error.EdgeInvariantViolated,
            .use_count_mismatch => error.UseCountMismatch,
            .block_membership_error => error.BlockMembershipError,
            .type_mismatch => error.TypeMismatch,
            .invalid_type => error.InvalidType,
            .pass_failed => error.PassFailed,
            .pass_not_found => error.PassNotFound,
            .dependency_not_satisfied => error.DependencyNotSatisfied,
            .out_of_memory => error.OutOfMemory,
            .allocation_failed => error.AllocationFailed,
            .invalid_instruction => error.InvalidInstruction,
            .register_allocation_failed => error.RegisterAllocationFailed,
            .unsupported_operation => error.UnsupportedOperation,
        };
    }
};

/// Simple error set for Zig error handling compatibility.
pub const Error = error{
    InvalidBlockId,
    InvalidValueId,
    EdgeInvariantViolated,
    UseCountMismatch,
    BlockMembershipError,
    TypeMismatch,
    InvalidType,
    PassFailed,
    PassNotFound,
    DependencyNotSatisfied,
    OutOfMemory,
    AllocationFailed,
    InvalidInstruction,
    RegisterAllocationFailed,
    UnsupportedOperation,
};

/// Result type: value or error with context.
pub fn Result(comptime T: type) type {
    return union(enum) {
        ok: T,
        err: CompileError,

        pub fn unwrap(self: @This()) Error!T {
            return switch (self) {
                .ok => |v| v,
                .err => |e| e.toError(),
            };
        }

        pub fn getError(self: @This()) ?CompileError {
            return switch (self) {
                .ok => null,
                .err => |e| e,
            };
        }
    };
}

/// Verification error for SSA invariant violations.
pub const VerifyError = struct {
    message: []const u8,
    block_id: ?ID = null,
    value_id: ?ID = null,
    expected: ?[]const u8 = null,
    actual: ?[]const u8 = null,

    pub fn format(self: VerifyError, comptime _: []const u8, _: std.fmt.FormatOptions, w: anytype) !void {
        try w.print("verification failed: {s}", .{self.message});
        if (self.block_id) |b| try w.print(" (block b{d})", .{b});
        if (self.value_id) |v| try w.print(" (value v{d})", .{v});
        if (self.expected) |e| try w.print(" expected: {s}", .{e});
        if (self.actual) |a| try w.print(" actual: {s}", .{a});
    }
};

// ============================================================================
// Tests
// ============================================================================

test "CompileError formatting" {
    const err = CompileError.init(.use_count_mismatch, "during dead code elimination")
        .withBlock(5)
        .withValue(10)
        .withPass("early deadcode");

    var buf: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    try err.format("", .{}, stream.writer());

    const output = stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "use_count_mismatch") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "dead code elimination") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "b5") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "v10") != null);
}

test "CompileError to simple error" {
    const err = CompileError.init(.pass_not_found, "unknown pass");
    try std.testing.expectEqual(error.PassNotFound, err.toError());
}

test "Result type" {
    const ResultInt = Result(i32);

    const ok_result = ResultInt{ .ok = 42 };
    try std.testing.expectEqual(@as(i32, 42), try ok_result.unwrap());

    const err_result = ResultInt{ .err = CompileError.init(.out_of_memory, "allocation failed") };
    try std.testing.expectError(error.OutOfMemory, err_result.unwrap());
}
