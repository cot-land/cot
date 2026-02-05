//! End-to-end Native AOT compilation tests.
//!
//! Tests the full pipeline: Cot source -> Wasm -> CLIF -> Machine Code -> Executable -> Run
//!
//! Each test compiles a single Cot program, links it, runs it, and checks exit code.
//! Returns 0 on success or a unique error code identifying which check failed.
//!
//! KNOWN BUG: Function calls produce infinite loops in native code due to the
//! dispatch loop (br_table) not correctly re-reading PC_B on loop iteration.
//! All tests here avoid function calls until this is fixed.

const std = @import("std");
const Driver = @import("../driver.zig").Driver;
const Target = @import("../core/target.zig").Target;

const NativeResult = struct {
    exit_code: ?u32,
    compile_error: bool,
    link_error: bool,
    run_error: bool,
    error_msg: []const u8,

    pub fn success(code: u32) NativeResult {
        return .{ .exit_code = code, .compile_error = false, .link_error = false, .run_error = false, .error_msg = "" };
    }
    pub fn compileErr(msg: []const u8) NativeResult {
        return .{ .exit_code = null, .compile_error = true, .link_error = false, .run_error = false, .error_msg = msg };
    }
    pub fn linkErr(msg: []const u8) NativeResult {
        return .{ .exit_code = null, .compile_error = false, .link_error = true, .run_error = false, .error_msg = msg };
    }
    pub fn runErr(msg: []const u8) NativeResult {
        return .{ .exit_code = null, .compile_error = false, .link_error = false, .run_error = true, .error_msg = msg };
    }
};

fn compileAndRun(allocator: std.mem.Allocator, code: []const u8, test_name: []const u8) NativeResult {
    const tmp_dir = "/tmp/cot_native_test";
    std.fs.cwd().makePath(tmp_dir) catch {};

    const obj_path = std.fmt.allocPrint(allocator, "{s}/{s}.o", .{ tmp_dir, test_name }) catch
        return NativeResult.compileErr("allocPrint failed");
    defer allocator.free(obj_path);

    const exe_path = std.fmt.allocPrint(allocator, "{s}/{s}", .{ tmp_dir, test_name }) catch
        return NativeResult.compileErr("allocPrint failed");
    defer allocator.free(exe_path);

    var driver = Driver.init(allocator);
    driver.setTarget(Target.native());

    const obj_code = driver.compileSource(code) catch |e| {
        const msg = std.fmt.allocPrint(allocator, "compile error: {any}", .{e}) catch "compile error";
        return NativeResult.compileErr(msg);
    };
    defer allocator.free(obj_code);

    std.fs.cwd().writeFile(.{ .sub_path = obj_path, .data = obj_code }) catch
        return NativeResult.compileErr("failed to write .o file");

    const link_result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "zig", "cc", "-o", exe_path, obj_path },
    }) catch return NativeResult.linkErr("failed to spawn linker");
    defer allocator.free(link_result.stdout);
    defer allocator.free(link_result.stderr);

    if (link_result.term.Exited != 0) return NativeResult.linkErr("linker failed");

    const run_result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{exe_path},
    }) catch return NativeResult.runErr("failed to spawn executable");
    defer allocator.free(run_result.stdout);
    defer allocator.free(run_result.stderr);

    return switch (run_result.term) {
        .Exited => |exit_code| NativeResult.success(exit_code),
        .Signal => |sig| blk: {
            const msg = std.fmt.allocPrint(allocator, "signal {d}", .{sig}) catch "signal";
            break :blk NativeResult.runErr(msg);
        },
        else => NativeResult.runErr("unknown termination"),
    };
}

fn expectExitCode(backing_allocator: std.mem.Allocator, code: []const u8, expected: u32, test_name: []const u8) !void {
    std.debug.print("[native] {s}...", .{test_name});
    var arena = std.heap.ArenaAllocator.init(backing_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const result = compileAndRun(allocator, code, test_name);

    if (result.compile_error) {
        std.debug.print("COMPILE ERROR: {s}\n", .{result.error_msg});
        return error.CompileError;
    }
    if (result.link_error) {
        std.debug.print("LINK ERROR: {s}\n", .{result.error_msg});
        return error.LinkError;
    }
    if (result.run_error) {
        std.debug.print("RUN ERROR: {s}\n", .{result.error_msg});
        return error.RunError;
    }

    const actual = result.exit_code orelse return error.NoExitCode;
    if (actual != expected) {
        std.debug.print("WRONG EXIT CODE: expected {d}, got {d}\n", .{ expected, actual });
        return error.WrongExitCode;
    }
    std.debug.print("ok\n", .{});
}

// ============================================================================
// Baseline: constants, arithmetic, variables, control flow (NO function calls)
// ============================================================================

test "native: baseline" {
    const code =
        \\fn main() i64 {
        \\    // Constants
        \\    if 42 != 42 { return 1; }
        \\    if 10 + 5 != 15 { return 2; }
        \\    if 20 - 8 != 12 { return 3; }
        \\    if 6 * 7 != 42 { return 4; }
        \\    if 2 + 3 * 4 != 14 { return 5; }
        \\
        \\    // Variables
        \\    let x = 10;
        \\    let y = 5;
        \\    if x + y != 15 { return 10; }
        \\
        \\    // If/else
        \\    if 10 > 5 {
        \\        let ok = 1;
        \\        if ok != 1 { return 30; }
        \\    } else {
        \\        return 31;
        \\    }
        \\
        \\    // While loop
        \\    let sum = 0;
        \\    let i = 1;
        \\    while i <= 10 {
        \\        sum = sum + i;
        \\        i = i + 1;
        \\    }
        \\    if sum != 55 { return 40; }
        \\
        \\    return 0;
        \\}
    ;
    try expectExitCode(std.testing.allocator, code, 0, "baseline");
}

// ============================================================================
// Phase 3: All features in one program (NO function calls - dispatch loop bug)
// ============================================================================

test "native: phase 3 language features" {
    const code =
        \\struct Point {
        \\    x: i64,
        \\    y: i64,
        \\}
        \\
        \\type Coord = Point;
        \\
        \\enum Color {
        \\    Red,
        \\    Green,
        \\    Blue,
        \\}
        \\
        \\enum Status {
        \\    Ok = 0,
        \\    Warning = 50,
        \\    Error = 100,
        \\}
        \\
        \\enum Level {
        \\    Low = 10,
        \\    Medium = 50,
        \\    High = 100,
        \\}
        \\
        \\union State {
        \\    Init,
        \\    Running,
        \\    Done,
        \\}
        \\
        \\fn main() i64 {
        \\    // Char literals
        \\    let c1 = 'A';
        \\    if c1 != 65 { return 100; }
        \\    let c2 = '\n';
        \\    if c2 != 10 { return 101; }
        \\
        \\    // Type alias + struct
        \\    let coord: Coord = Coord { .x = 10, .y = 20 };
        \\    if coord.x + coord.y != 30 { return 102; }
        \\
        \\    // Builtins
        \\    if @sizeOf(i64) != 8 { return 103; }
        \\    if @sizeOf(Point) != 16 { return 104; }
        \\    if @alignOf(i64) != 8 { return 105; }
        \\    let big: i64 = 42;
        \\    let small = @intCast(i32, big);
        \\    if small != 42 { return 106; }
        \\
        \\    // Enums (return value directly - frontend doesn't support enum != int comparison)
        \\    let color: i64 = Color.Green;
        \\    if color != 1 { return 107; }
        \\    let status: i64 = Status.Error;
        \\    if status != 100 { return 108; }
        \\
        \\    // Union (return value directly - frontend doesn't support union != int comparison)
        \\    let state: i64 = State.Running;
        \\    if state != 1 { return 109; }
        \\
        \\    // Bitwise ops (inline, no function calls)
        \\    let a = 255;
        \\    let b = 15;
        \\    if (a & b) != 15 { return 110; }
        \\    if ((240 | 15) - 200) != 55 { return 111; }
        \\    if ((a ^ b) & 255) != 240 { return 112; }
        \\    if ((~0) & 255) != 255 { return 113; }
        \\    if (1 << 4) != 16 { return 114; }
        \\    if (64 >> 2) != 16 { return 115; }
        \\
        \\    // Compound assignment
        \\    var x = 10;
        \\    x += 5;
        \\    if x != 15 { return 120; }
        \\    x -= 3;
        \\    if x != 12 { return 121; }
        \\    x *= 2;
        \\    if x != 24 { return 122; }
        \\    var y = 255;
        \\    y &= 15;
        \\    if y != 15 { return 123; }
        \\
        \\    // Optional types
        \\    let opt1: ?i64 = 42;
        \\    if opt1.? != 42 { return 140; }
        \\    let opt2: ?i64 = null;
        \\    if (opt2 ?? 99) != 99 { return 141; }
        \\    let opt3: ?i64 = 42;
        \\    if (opt3 ?? 99) != 42 { return 142; }
        \\
        \\    // Switch
        \\    let sw1 = switch 2 {
        \\        1 => 10,
        \\        2 => 20,
        \\        3 => 30,
        \\        else => 0,
        \\    };
        \\    if sw1 != 20 { return 150; }
        \\
        \\    let level = Level.Medium;
        \\    let sw2 = switch level {
        \\        Level.Low => 1,
        \\        Level.Medium => 50,
        \\        Level.High => 99,
        \\        else => 0,
        \\    };
        \\    if sw2 != 50 { return 151; }
        \\
        \\    return 0;
        \\}
    ;
    try expectExitCode(std.testing.allocator, code, 0, "phase3_all");
}

// ============================================================================
// Function calls (fixed: is_aarch64 was declared at file scope instead of
// inside the Inst union, causing @hasDecl to return false and skipping
// prologue/epilogue generation for ARM64)
// ============================================================================

test "native: function call" {
    const code =
        \\fn double(x: i64) i64 { return x + x; }
        \\fn main() i64 { return double(10); }
    ;
    try expectExitCode(std.testing.allocator, code, 20, "func_call");
}
