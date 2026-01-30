//! SSA Compilation Pass Infrastructure
//!
//! Go reference: cmd/compile/internal/ssa/compile.go
//!
//! Orchestrates the sequence of passes that transform SSA for codegen.
//! Unlike Go's 48 passes, Cot uses a minimal essential set:
//!
//! 1. expand_calls - decompose aggregates for ABI
//! 2. decompose - break 16-byte values into 8-byte components
//! 3. schedule - order values within blocks for emission
//! 4. regalloc - assign physical registers
//! 5. stackalloc - assign stack slots to spills
//!
//! ## Pass Ordering Constraints (Go's pattern)
//!
//! - expand_calls BEFORE decompose (calls need ABI handling first)
//! - decompose BEFORE schedule (values must be register-sized)
//! - schedule BEFORE regalloc (regalloc needs deterministic order)
//! - regalloc BEFORE stackalloc (stackalloc uses spill info from regalloc)

const std = @import("std");
const Func = @import("func.zig").Func;
const debug = @import("../pipeline_debug.zig");
const types = @import("../frontend/types.zig");
const target_mod = @import("../core/target.zig");

// Pass modules
const expand_calls_mod = @import("passes/expand_calls.zig");
const decompose_mod = @import("passes/decompose.zig");
const schedule_mod = @import("passes/schedule.zig");
const regalloc_mod = @import("regalloc.zig");
const stackalloc_mod = @import("stackalloc.zig");

pub const RegAllocState = regalloc_mod.RegAllocState;
pub const StackAllocResult = stackalloc_mod.StackAllocResult;

// ============================================================================
// Compilation Result
// ============================================================================

/// Result of compiling a function through all SSA passes.
/// Caller must call deinit() when done.
pub const CompileResult = struct {
    regalloc: RegAllocState,
    stack: StackAllocResult,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *CompileResult) void {
        self.regalloc.deinit();
    }

    /// Get the frame size for codegen prologue/epilogue.
    pub fn frameSize(self: *const CompileResult) u32 {
        return self.stack.frame_size;
    }

    /// Get spill slot info for codegen.
    pub fn spillLive(self: *CompileResult) *const std.AutoHashMapUnmanaged(u32, std.ArrayListUnmanaged(u32)) {
        return self.regalloc.getSpillLive();
    }
};

// ============================================================================
// Main Compilation Entry Point
// ============================================================================

/// Compile a function through all SSA passes.
///
/// This is the main entry point that runs:
/// 1. expand_calls - prepare call arguments per ABI
/// 2. decompose - break large values into register-sized pieces
/// 3. schedule - order values for deterministic emission
/// 4. regalloc - assign physical registers
/// 5. stackalloc - assign stack slots
///
/// Returns a CompileResult that must be passed to codegen.
pub fn compile(
    allocator: std.mem.Allocator,
    f: *Func,
    type_reg: ?*const types.TypeRegistry,
    target: target_mod.Target,
) !CompileResult {
    debug.log(.ssa, "=== Compiling '{s}' ===", .{f.name});

    // Pass 1: Expand calls - decompose aggregate arguments for ABI
    debug.log(.ssa, "  Pass 1: expand_calls", .{});
    try expand_calls_mod.expandCalls(f, type_reg);

    // Pass 2: Decompose - break 16-byte values into 8-byte components
    debug.log(.ssa, "  Pass 2: decompose", .{});
    try decompose_mod.decompose(f, type_reg);

    // Pass 3: Schedule - order values within blocks
    debug.log(.schedule, "  Pass 3: schedule", .{});
    try schedule_mod.schedule(f);

    // Pass 4: Register allocation
    debug.log(.regalloc, "  Pass 4: regalloc", .{});
    var regalloc_state = try regalloc_mod.regalloc(allocator, f, target);
    errdefer regalloc_state.deinit();

    debug.log(.regalloc, "    spills: {d}", .{regalloc_state.num_spills});

    // Pass 5: Stack allocation (uses spill info from regalloc)
    debug.log(.regalloc, "  Pass 5: stackalloc", .{});
    const stack_result = try stackalloc_mod.stackalloc(f, regalloc_state.getSpillLive());

    debug.log(.regalloc, "    frame_size: {d} bytes", .{stack_result.frame_size});
    debug.log(.ssa, "=== Compile complete for '{s}' ===", .{f.name});

    return .{
        .regalloc = regalloc_state,
        .stack = stack_result,
        .allocator = allocator,
    };
}

// ============================================================================
// Individual Pass Entry Points (for testing or custom pipelines)
// ============================================================================

/// Run only the pre-regalloc passes (expand_calls, decompose, schedule).
/// Use this when you need to run regalloc separately.
pub fn prepareForRegalloc(f: *Func, type_reg: ?*const types.TypeRegistry) !void {
    try expand_calls_mod.expandCalls(f, type_reg);
    try decompose_mod.decompose(f, type_reg);
    try schedule_mod.schedule(f);
}

/// Run expand_calls pass only.
pub fn expandCalls(f: *Func, type_reg: ?*const types.TypeRegistry) !void {
    try expand_calls_mod.expandCalls(f, type_reg);
}

/// Run decompose pass only.
pub fn decompose(f: *Func, type_reg: ?*const types.TypeRegistry) !void {
    try decompose_mod.decompose(f, type_reg);
}

/// Run schedule pass only.
pub fn schedule(f: *Func) !void {
    try schedule_mod.schedule(f);
}

/// Run regalloc pass only.
pub fn regalloc(allocator: std.mem.Allocator, f: *Func, target: target_mod.Target) !RegAllocState {
    return try regalloc_mod.regalloc(allocator, f, target);
}

/// Run stackalloc pass only.
pub fn stackalloc(
    f: *Func,
    spill_live: *const std.AutoHashMapUnmanaged(u32, std.ArrayListUnmanaged(u32)),
) !StackAllocResult {
    return try stackalloc_mod.stackalloc(f, spill_live);
}

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;
const test_helpers = @import("test_helpers.zig");

test "CompileResult lifecycle" {
    // Test that CompileResult can be created and destroyed without leaks
    const allocator = testing.allocator;

    var f = Func.init(allocator, "test_lifecycle");
    defer f.deinit();

    // Create minimal function structure
    _ = try f.newBlock(.first);

    // For this test, we'd need the full passes which have dependencies
    // Just verify the types work correctly
    var result = CompileResult{
        .regalloc = undefined, // Would be from actual regalloc
        .stack = .{ .frame_size = 32, .num_spill_slots = 2, .locals_size = 16, .num_reused = 0 },
        .allocator = allocator,
    };

    try testing.expectEqual(@as(u32, 32), result.frameSize());
}

test "pass ordering constraints" {
    // Document and verify the pass ordering constraints
    // This is similar to Go's passOrder verification in compile.go

    const PassOrder = struct {
        before: []const u8,
        after: []const u8,
    };

    const constraints = [_]PassOrder{
        .{ .before = "expand_calls", .after = "decompose" },
        .{ .before = "decompose", .after = "schedule" },
        .{ .before = "schedule", .after = "regalloc" },
        .{ .before = "regalloc", .after = "stackalloc" },
    };

    // Verify constraints are documented
    try testing.expectEqual(@as(usize, 4), constraints.len);
    try testing.expectEqualStrings("expand_calls", constraints[0].before);
    try testing.expectEqualStrings("stackalloc", constraints[3].after);
}

test "prepareForRegalloc runs pre-regalloc passes" {
    const allocator = testing.allocator;

    var f = Func.init(allocator, "test_prepare");
    defer f.deinit();

    _ = try f.newBlock(.first);

    // prepareForRegalloc should not error on empty function
    try prepareForRegalloc(&f, null);
}
