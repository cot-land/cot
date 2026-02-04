# Cot Testing Framework - Detailed Execution Plan

## Executive Summary

This document outlines a production-grade testing framework for Cot, designed to support Test-Driven Development (TDD) for new language features. The framework builds on patterns from `bootstrap-0.2` while adding modern capabilities suited to the Cot → Wasm → Native pipeline.

---

## Design Principles

1. **Copy proven patterns** - Bootstrap-0.2's 166-test tiered suite demonstrates what works
2. **Pretty output** - Developers should see clear, colored feedback
3. **Line numbers in errors** - Runtime errors must trace back to source
4. **Inline test syntax** - Tests alongside code (like Zig's `test "name" {}`)
5. **Dual-target parity** - Same tests run on both Wasm and Native targets
6. **Regression prevention** - E2E suite catches pipeline-wide bugs

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         Testing Framework                               │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────────┐  │
│  │  Inline Tests    │  │  E2E Test Suite  │  │  Parity Tests        │  │
│  │                  │  │                  │  │                      │  │
│  │  test "name" {   │  │  all_tests.cot   │  │  Run same test on    │  │
│  │    assert(...)   │  │  (166+ tests)    │  │  Wasm and Native,    │  │
│  │  }               │  │                  │  │  compare results     │  │
│  └────────┬─────────┘  └────────┬─────────┘  └──────────┬───────────┘  │
│           │                     │                       │              │
│           └─────────────────────┼───────────────────────┘              │
│                                 ▼                                       │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                     Test Runner (testrunner.zig)                 │   │
│  │                                                                   │   │
│  │  • Discovers and runs tests                                      │   │
│  │  • Pretty-prints results with colors                             │   │
│  │  • Captures stdout/stderr                                        │   │
│  │  • Reports line numbers on failure                               │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                 │                                       │
│                                 ▼                                       │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                     Source Maps (sourcemap.zig)                  │   │
│  │                                                                   │   │
│  │  • Maps Wasm instruction offset → Cot source line               │   │
│  │  • Maps Native instruction address → Cot source line            │   │
│  │  • Enables meaningful stack traces                               │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Phase 1: Source Location Tracking Infrastructure

**Goal:** Every SSA value, Wasm instruction, and Native instruction can be traced back to a Cot source line.

### Task 1.1: Add Source Location to IR Values

**Files to modify:**
- `compiler/frontend/ir.zig`
- `compiler/ssa/value.zig`

**Current state:** IR nodes don't track source locations after AST.

**Target state:**

```zig
// compiler/ssa/value.zig

pub const SourceLoc = struct {
    line: u32,      // 1-indexed line number
    column: u32,    // 1-indexed column
    file_idx: u16,  // Index into file name table (for multi-file)

    pub const UNKNOWN: SourceLoc = .{ .line = 0, .column = 0, .file_idx = 0 };
};

pub const Value = struct {
    op: Op,
    type_idx: TypeIdx,
    aux_int: i64,
    args: []const ValueRef,
    loc: SourceLoc,  // NEW: source location
    // ...
};
```

**Checklist:**
- [ ] Add `SourceLoc` struct to `compiler/ssa/value.zig`
- [ ] Add `loc` field to `Value` struct
- [ ] Update `SSABuilder` to propagate locations from AST
- [ ] Update `lower.zig` to preserve locations during IR→SSA
- [ ] Verify locations survive through `lower_wasm.zig`

### Task 1.2: Create Source Map Module

**New file:** `compiler/core/sourcemap.zig`

```zig
//! Source map for mapping compiled offsets back to source lines.
//!
//! The source map is a simple sorted array of (offset, SourceLoc) pairs.
//! For a given offset, binary search finds the most recent source location.

const std = @import("std");
const SourceLoc = @import("../ssa/value.zig").SourceLoc;

pub const SourceMap = struct {
    entries: std.ArrayListUnmanaged(Entry),
    file_names: std.ArrayListUnmanaged([]const u8),
    allocator: std.mem.Allocator,

    pub const Entry = struct {
        offset: u32,      // Wasm byte offset or native code offset
        loc: SourceLoc,
    };

    pub fn init(allocator: std.mem.Allocator) SourceMap {
        return .{
            .entries = .{},
            .file_names = .{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *SourceMap) void {
        self.entries.deinit(self.allocator);
        self.file_names.deinit(self.allocator);
    }

    /// Add a mapping from code offset to source location.
    pub fn add(self: *SourceMap, offset: u32, loc: SourceLoc) !void {
        try self.entries.append(self.allocator, .{ .offset = offset, .loc = loc });
    }

    /// Look up source location for a given offset.
    /// Returns the most recent source location <= offset.
    pub fn lookup(self: *const SourceMap, offset: u32) ?SourceLoc {
        if (self.entries.items.len == 0) return null;

        // Binary search for the largest entry.offset <= offset
        var left: usize = 0;
        var right: usize = self.entries.items.len;

        while (left < right) {
            const mid = left + (right - left) / 2;
            if (self.entries.items[mid].offset <= offset) {
                left = mid + 1;
            } else {
                right = mid;
            }
        }

        if (left == 0) return null;
        return self.entries.items[left - 1].loc;
    }

    /// Format a source location for display.
    pub fn format(self: *const SourceMap, loc: SourceLoc, writer: anytype) !void {
        if (loc.file_idx < self.file_names.items.len) {
            try writer.print("{s}:", .{self.file_names.items[loc.file_idx]});
        }
        try writer.print("{d}:{d}", .{loc.line, loc.column});
    }
};
```

**Checklist:**
- [ ] Create `compiler/core/sourcemap.zig`
- [ ] Add unit tests for binary search lookup
- [ ] Wire into Wasm codegen (`wasm_gen.zig`)
- [ ] Wire into Native codegen (CLIF lowering)

### Task 1.3: Emit Source Maps During Codegen

**Files to modify:**
- `compiler/codegen/wasm_gen.zig`
- `compiler/codegen/native/wasm_to_clif/translator.zig`

**Wasm codegen example:**

```zig
// compiler/codegen/wasm_gen.zig

pub fn genFuncWithIndices(
    allocator: std.mem.Allocator,
    ssa_func: *const Func,
    func_indices: *const FuncIndexMap,
    runtime_funcs: arc.RuntimeFuncs,
    source_map: ?*SourceMap,  // NEW: optional source map output
) ![]const u8 {
    var output: std.ArrayListUnmanaged(u8) = .{};
    // ...

    for (block.values.items) |v| {
        // Record source location before emitting instruction
        if (source_map) |sm| {
            if (v.loc.line != 0) {
                try sm.add(@intCast(output.items.len), v.loc);
            }
        }

        // Emit instruction...
    }
}
```

**Checklist:**
- [ ] Add optional `SourceMap` parameter to `genFuncWithIndices`
- [ ] Record locations before each emitted instruction
- [ ] Store source map in Wasm custom section (name: "cot-sourcemap")
- [ ] Add similar tracking to native codegen

---

## Phase 2: Pretty Test Output Infrastructure

**Goal:** Test output is clear, colored, and informative.

### Task 2.1: Create Pretty Printer Module

**New file:** `compiler/core/pretty.zig`

```zig
//! Pretty-printing utilities for terminal output.

const std = @import("std");

pub const Color = enum(u8) {
    reset = 0,
    red = 31,
    green = 32,
    yellow = 33,
    blue = 34,
    magenta = 35,
    cyan = 36,
    white = 37,
    bold_red = 91,
    bold_green = 92,
    bold_yellow = 93,
};

pub const Style = struct {
    color: ?Color = null,
    bold: bool = false,
    underline: bool = false,
};

/// Pretty-print writer that wraps any writer with color support.
pub fn PrettyWriter(comptime WriterType: type) type {
    return struct {
        inner: WriterType,
        colors_enabled: bool,

        const Self = @This();

        pub fn init(inner: WriterType, colors_enabled: bool) Self {
            return .{ .inner = inner, .colors_enabled = colors_enabled };
        }

        pub fn setColor(self: Self, color: Color) !void {
            if (self.colors_enabled) {
                try self.inner.print("\x1b[{d}m", .{@intFromEnum(color)});
            }
        }

        pub fn reset(self: Self) !void {
            if (self.colors_enabled) {
                try self.inner.writeAll("\x1b[0m");
            }
        }

        pub fn print(self: Self, comptime fmt: []const u8, args: anytype) !void {
            try self.inner.print(fmt, args);
        }

        pub fn writeAll(self: Self, bytes: []const u8) !void {
            try self.inner.writeAll(bytes);
        }

        // Convenience methods
        pub fn success(self: Self, msg: []const u8) !void {
            try self.setColor(.bold_green);
            try self.writeAll("✓ ");
            try self.reset();
            try self.writeAll(msg);
            try self.writeAll("\n");
        }

        pub fn failure(self: Self, msg: []const u8) !void {
            try self.setColor(.bold_red);
            try self.writeAll("✗ ");
            try self.reset();
            try self.writeAll(msg);
            try self.writeAll("\n");
        }

        pub fn info(self: Self, msg: []const u8) !void {
            try self.setColor(.cyan);
            try self.writeAll("• ");
            try self.reset();
            try self.writeAll(msg);
            try self.writeAll("\n");
        }

        pub fn header(self: Self, msg: []const u8) !void {
            try self.setColor(.bold_yellow);
            try self.writeAll("\n═══ ");
            try self.writeAll(msg);
            try self.writeAll(" ═══\n");
            try self.reset();
        }
    };
}

/// Detect if stdout supports colors.
pub fn stdoutSupportsColors() bool {
    // Check for NO_COLOR env var (standard: https://no-color.org/)
    if (std.posix.getenv("NO_COLOR")) |_| return false;

    // Check if stdout is a TTY
    const stdout = std.io.getStdOut();
    return stdout.isTty();
}
```

**Checklist:**
- [ ] Create `compiler/core/pretty.zig`
- [ ] Add unit tests for color output
- [ ] Add `NO_COLOR` environment variable support
- [ ] Add TTY detection

### Task 2.2: Create Test Result Formatter

**New file:** `compiler/test/formatter.zig`

```zig
//! Formats test results with pretty output.

const std = @import("std");
const pretty = @import("../core/pretty.zig");
const SourceMap = @import("../core/sourcemap.zig").SourceMap;
const SourceLoc = @import("../ssa/value.zig").SourceLoc;

pub const TestResult = struct {
    name: []const u8,
    status: Status,
    duration_ns: u64,
    error_msg: ?[]const u8 = null,
    error_loc: ?SourceLoc = null,
    stdout: ?[]const u8 = null,
    stderr: ?[]const u8 = null,

    pub const Status = enum {
        passed,
        failed,
        skipped,
        compile_error,
        runtime_error,
    };
};

pub const TestSuite = struct {
    name: []const u8,
    results: std.ArrayListUnmanaged(TestResult),
    total_duration_ns: u64,

    pub fn countPassed(self: *const TestSuite) usize {
        var count: usize = 0;
        for (self.results.items) |r| {
            if (r.status == .passed) count += 1;
        }
        return count;
    }

    pub fn countFailed(self: *const TestSuite) usize {
        var count: usize = 0;
        for (self.results.items) |r| {
            if (r.status == .failed or r.status == .compile_error or r.status == .runtime_error) {
                count += 1;
            }
        }
        return count;
    }
};

pub fn formatResults(
    writer: anytype,
    suite: *const TestSuite,
    source_map: ?*const SourceMap,
    verbose: bool,
) !void {
    const pw = pretty.PrettyWriter(@TypeOf(writer)).init(writer, pretty.stdoutSupportsColors());

    try pw.header(suite.name);

    for (suite.results.items) |result| {
        switch (result.status) {
            .passed => {
                if (verbose) {
                    try pw.success(result.name);
                }
            },
            .failed, .runtime_error, .compile_error => {
                try pw.failure(result.name);
                if (result.error_msg) |msg| {
                    try pw.setColor(.red);
                    try pw.print("    Error: {s}\n", .{msg});
                    try pw.reset();
                }
                if (result.error_loc) |loc| {
                    if (source_map) |sm| {
                        try pw.setColor(.cyan);
                        try pw.writeAll("    at ");
                        try sm.format(loc, writer);
                        try pw.writeAll("\n");
                        try pw.reset();
                    }
                }
            },
            .skipped => {
                try pw.setColor(.yellow);
                try pw.print("⊘ {s} (skipped)\n", .{result.name});
                try pw.reset();
            },
        }
    }

    // Summary
    try pw.writeAll("\n");
    const passed = suite.countPassed();
    const failed = suite.countFailed();
    const total = suite.results.items.len;

    if (failed == 0) {
        try pw.setColor(.bold_green);
        try pw.print("All {d} tests passed", .{passed});
    } else {
        try pw.setColor(.bold_red);
        try pw.print("{d} failed", .{failed});
        try pw.setColor(.white);
        try pw.print(", {d} passed", .{passed});
    }

    try pw.setColor(.white);
    const duration_ms = suite.total_duration_ns / 1_000_000;
    try pw.print(" ({d}ms)\n", .{duration_ms});
    try pw.reset();
}
```

**Checklist:**
- [ ] Create `compiler/test/formatter.zig`
- [ ] Add verbose/quiet modes
- [ ] Add duration tracking
- [ ] Add source context display (show offending line)

---

## Phase 3: Runtime Error Handling with Line Numbers

**Goal:** When a Cot program crashes or asserts, show the source line.

### Task 3.1: Add Runtime Assertion Support

**New file:** `compiler/runtime/assert.zig`

This will be compiled into the Wasm/Native runtime.

```zig
//! Runtime assertion support for Cot programs.
//!
//! When assert() fails, this module:
//! 1. Looks up the source location from the source map
//! 2. Prints a formatted error message
//! 3. Aborts the program

const std = @import("std");

// This struct will be embedded in the Wasm memory / native data section
pub const AssertInfo = extern struct {
    file_ptr: u32,  // Pointer to file name string
    file_len: u32,
    line: u32,
    column: u32,
    msg_ptr: u32,   // Pointer to assertion message
    msg_len: u32,
};

// Called when assert() fails
pub export fn __cot_assert_fail(info_ptr: u32) noreturn {
    // In Wasm, this will be imported from the host
    // In Native, this will call the formatted printer directly

    // For now, just trap
    @trap();
}
```

**Cot syntax:**

```cot
fn divide(a: int, b: int) int {
    assert(b != 0, "division by zero")  // Compiler embeds line number
    return a / b
}
```

**Compiler transformation:**

```
// Before
assert(b != 0, "division by zero")

// After (SSA)
v1 = ne(b, 0)
br_if v1, continue_block
v2 = const_assert_info { file: "math.cot", line: 2, col: 5, msg: "division by zero" }
call __cot_assert_fail(v2)
continue_block:
```

**Checklist:**
- [ ] Add `assert()` builtin to parser
- [ ] Lower assert to conditional branch + runtime call
- [ ] Embed file/line info in assertion
- [ ] Implement `__cot_assert_fail` for Wasm host
- [ ] Implement `__cot_assert_fail` for native runtime

### Task 3.2: Add Stack Trace Support

**New file:** `compiler/runtime/stacktrace.zig`

```zig
//! Stack trace support for Cot programs.
//!
//! On crash/trap, walks the stack and prints source-mapped locations.

const std = @import("std");
const SourceMap = @import("../core/sourcemap.zig").SourceMap;

pub const StackFrame = struct {
    return_address: usize,
    frame_pointer: usize,
};

pub fn captureStackTrace(frames: []StackFrame) usize {
    // Platform-specific stack walking
    // For native: use frame pointer chain
    // For Wasm: use shadow stack or Wasm exception handling proposal

    var count: usize = 0;
    var fp = @frameAddress();

    while (fp != 0 and count < frames.len) {
        const frame_data: [*]usize = @ptrFromInt(fp);
        frames[count] = .{
            .return_address = frame_data[1],  // Return address is at fp+8
            .frame_pointer = fp,
        };
        fp = frame_data[0];  // Previous frame pointer is at fp+0
        count += 1;
    }

    return count;
}

pub fn printStackTrace(
    writer: anytype,
    frames: []const StackFrame,
    source_map: *const SourceMap,
) !void {
    try writer.writeAll("Stack trace:\n");

    for (frames, 0..) |frame, i| {
        const offset: u32 = @truncate(frame.return_address);
        if (source_map.lookup(offset)) |loc| {
            try writer.print("  {d}: ", .{i});
            try source_map.format(loc, writer);
            try writer.writeAll("\n");
        } else {
            try writer.print("  {d}: <unknown> (0x{x})\n", .{ i, frame.return_address });
        }
    }
}
```

**Checklist:**
- [ ] Create `compiler/runtime/stacktrace.zig`
- [ ] Implement native stack walking (ARM64, x64)
- [ ] Implement Wasm stack walking (shadow stack approach)
- [ ] Wire into `__cot_assert_fail`
- [ ] Wire into signal handlers (SIGSEGV, SIGABRT)

---

## Phase 4: Inline Test Syntax

**Goal:** Tests can be written alongside code, like Zig's `test "name" { }` blocks.

### Task 4.1: Add Test Syntax to Parser

**Files to modify:**
- `compiler/frontend/scanner.zig`
- `compiler/frontend/parser.zig`
- `compiler/frontend/ast.zig`

**Cot syntax:**

```cot
fn factorial(n: int) int {
    if n <= 1 { return 1 }
    return n * factorial(n - 1)
}

test "factorial of 5 is 120" {
    assert(factorial(5) == 120)
}

test "factorial of 0 is 1" {
    assert(factorial(0) == 1)
}
```

**AST representation:**

```zig
// compiler/frontend/ast.zig

pub const NodeKind = enum {
    // ... existing kinds ...
    test_decl,  // NEW
};

pub const TestDecl = struct {
    name: []const u8,      // Test name string
    body: NodeIndex,       // Block containing test code
};
```

**Checklist:**
- [ ] Add `test` keyword to scanner
- [ ] Add `test_decl` node to AST
- [ ] Parse `test "name" { ... }` syntax
- [ ] Skip test blocks in normal compilation
- [ ] Collect test blocks when `--test` flag is passed

### Task 4.2: Generate Test Harness

**New file:** `compiler/test/harness.zig`

```zig
//! Generates a test harness that runs all inline tests.

const std = @import("std");
const ast = @import("../frontend/ast.zig");

pub const TestInfo = struct {
    name: []const u8,
    func_name: []const u8,  // Generated function name
    loc: SourceLoc,
};

/// Extract all test declarations from an AST.
pub fn extractTests(tree: *const ast.Ast, allocator: std.mem.Allocator) ![]TestInfo {
    var tests: std.ArrayListUnmanaged(TestInfo) = .{};

    for (tree.nodes.items, 0..) |node, i| {
        if (node.kind == .test_decl) {
            const test_data = tree.getTestDecl(@intCast(i));
            const func_name = try std.fmt.allocPrint(
                allocator,
                "__cot_test_{d}",
                .{tests.items.len}
            );
            try tests.append(allocator, .{
                .name = test_data.name,
                .func_name = func_name,
                .loc = tree.getLoc(@intCast(i)),
            });
        }
    }

    return tests.toOwnedSlice(allocator);
}

/// Generate a main function that runs all tests.
pub fn generateHarness(tests: []const TestInfo) []const u8 {
    // Generate code like:
    //
    // fn main() int {
    //     var failed = 0
    //     // For each test:
    //     if !__cot_run_test(__cot_test_0, "factorial of 5 is 120") { failed += 1 }
    //     if !__cot_run_test(__cot_test_1, "factorial of 0 is 1") { failed += 1 }
    //     return failed
    // }

    // ... code generation ...
}
```

**Checklist:**
- [ ] Create `compiler/test/harness.zig`
- [ ] Extract test declarations from AST
- [ ] Generate test wrapper functions
- [ ] Generate main harness that runs all tests
- [ ] Add `--test` flag to compiler CLI

---

## Phase 5: E2E Test Suite

**Goal:** Comprehensive test suite that runs on both Wasm and Native, catching regressions.

### Task 5.1: Port Bootstrap-0.2 Test Suite

**New file:** `tests/e2e/all_tests.cot`

This will be a direct port of `bootstrap-0.2/archive/cot0/test/all_tests.cot`, organized by tier:

```cot
// ============================================================================
// TIER 1: Basic Return + Arithmetic
// ============================================================================

test "return constant" {
    fn answer() int { return 42 }
    assert(answer() == 42)
}

test "multiplication" {
    assert(6 * 7 == 42)
}

test "division" {
    assert(84 / 2 == 42)
}

// ============================================================================
// TIER 2: Function Calls
// ============================================================================

test "function call with parameter" {
    fn add_one(x: int) int { return x + 1 }
    assert(add_one(41) == 42)
}

test "nested function calls" {
    fn double(x: int) int { return x * 2 }
    fn quadruple(x: int) int { return double(double(x)) }
    assert(quadruple(10) == 40)
}

// ... (166+ tests organized by tier) ...
```

**Tier structure (from bootstrap-0.2):**

| Tier | Category | Test Count |
|------|----------|------------|
| 1 | Basic Return + Arithmetic | 5 |
| 2 | Function Calls | 4 |
| 3 | Local Variables | 2 |
| 4 | Comparisons | 3 |
| 5 | If/Else | 3 |
| 6 | While Loops | 3 |
| 6.5 | Edge Cases | 17 |
| 7 | Structs | 4 |
| 8 | Characters + Strings | 7 |
| 9 | Arrays | 4 |
| 10 | Pointers | 7 |
| 11 | Bitwise Operators | 8 |
| 12 | Logical Operators | 10 |
| 13 | Enums | 5 |
| 14 | Null + Pointers | 4 |
| 15 | Slices | 11+ |
| 16 | For-In Loops | 4 |
| 17 | Switch Statement | 4 |
| 18 | Function Pointers | 3 |
| 19 | Pointer Arithmetic | 2 |
| 20 | Bitwise NOT | 3 |
| 21 | Compound Assignments | 6 |
| 22 | @intCast | 3 |
| 23 | Defer Statement | 4 |
| 24 | Global Variables | 4 |
| 25 | Stress Tests | 13 |
| 26 | Bug Regressions | 6 |

**Checklist:**
- [ ] Create `tests/e2e/all_tests.cot`
- [ ] Port Tier 1-6 tests (basic functionality)
- [ ] Port Tier 7-15 tests (compound types)
- [ ] Port Tier 16-26 tests (advanced features)
- [ ] Add new tests for Wasm-specific features

### Task 5.2: Create Parity Test Runner

**New file:** `compiler/test/parity_runner.zig`

```zig
//! Runs the same test on both Wasm and Native targets,
//! verifying they produce identical results.

const std = @import("std");
const Driver = @import("../driver.zig").Driver;
const Target = @import("../core/target.zig").Target;

pub const ParityResult = struct {
    wasm_exit_code: ?u32,
    native_exit_code: ?u32,
    wasm_stdout: []const u8,
    native_stdout: []const u8,
    match: bool,
};

pub fn runParityTest(
    allocator: std.mem.Allocator,
    source: []const u8,
    test_name: []const u8,
) !ParityResult {
    // Compile to Wasm
    var wasm_driver = Driver.init(allocator);
    wasm_driver.setTarget(Target.wasm32());
    const wasm_result = try runWasm(allocator, try wasm_driver.compileSource(source));

    // Compile to Native
    var native_driver = Driver.init(allocator);
    native_driver.setTarget(Target.native());
    const native_result = try runNative(allocator, try native_driver.compileSource(source), test_name);

    return .{
        .wasm_exit_code = wasm_result.exit_code,
        .native_exit_code = native_result.exit_code,
        .wasm_stdout = wasm_result.stdout,
        .native_stdout = native_result.stdout,
        .match = wasm_result.exit_code == native_result.exit_code and
                 std.mem.eql(u8, wasm_result.stdout, native_result.stdout),
    };
}

fn runWasm(allocator: std.mem.Allocator, wasm_bytes: []const u8) !struct { exit_code: ?u32, stdout: []const u8 } {
    // Option 1: Use Node.js
    // Option 2: Use wasm3 (embeddable interpreter)
    // Option 3: Use built-in Wasm interpreter

    // Write to temp file and run with Node
    const tmp_path = "/tmp/cot_parity_test.wasm";
    try std.fs.cwd().writeFile(.{ .sub_path = tmp_path, .data = wasm_bytes });

    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{
            "node", "-e",
            "const fs=require('fs');" ++
            "const wasm=fs.readFileSync('/tmp/cot_parity_test.wasm');" ++
            "WebAssembly.instantiate(wasm).then(r=>{" ++
            "  const code=r.instance.exports.main();" ++
            "  process.exit(code);" ++
            "});",
        },
    });

    return .{
        .exit_code = result.term.Exited,
        .stdout = result.stdout,
    };
}

fn runNative(allocator: std.mem.Allocator, obj_bytes: []const u8, test_name: []const u8) !struct { exit_code: ?u32, stdout: []const u8 } {
    const obj_path = try std.fmt.allocPrint(allocator, "/tmp/cot_parity_{s}.o", .{test_name});
    const exe_path = try std.fmt.allocPrint(allocator, "/tmp/cot_parity_{s}", .{test_name});

    try std.fs.cwd().writeFile(.{ .sub_path = obj_path, .data = obj_bytes });

    // Link
    _ = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "zig", "cc", "-o", exe_path, obj_path },
    });

    // Run
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{exe_path},
    });

    return .{
        .exit_code = result.term.Exited,
        .stdout = result.stdout,
    };
}
```

**Checklist:**
- [ ] Create `compiler/test/parity_runner.zig`
- [ ] Implement Wasm execution (Node.js or wasm3)
- [ ] Implement Native execution
- [ ] Compare exit codes and stdout
- [ ] Report parity failures with diffs

### Task 5.3: CI Integration

**New file:** `.github/workflows/test.yml`

```yaml
name: Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ${{ matrix.os }}
    strategy:
      matrix:
        os: [ubuntu-latest, macos-latest]

    steps:
      - uses: actions/checkout@v4

      - name: Install Zig
        uses: goto-bus-stop/setup-zig@v2
        with:
          version: 0.15.0

      - name: Install Node.js (for Wasm tests)
        uses: actions/setup-node@v4
        with:
          node-version: '20'

      - name: Build compiler
        run: zig build

      - name: Run unit tests
        run: zig build test

      - name: Run E2E tests (Wasm)
        run: zig build test-e2e-wasm

      - name: Run E2E tests (Native)
        run: zig build test-e2e-native

      - name: Run parity tests
        run: zig build test-parity
```

**Checklist:**
- [ ] Create `.github/workflows/test.yml`
- [ ] Add `test-e2e-wasm` build step
- [ ] Add `test-e2e-native` build step
- [ ] Add `test-parity` build step
- [ ] Configure matrix for Ubuntu + macOS

---

## Phase 6: Integration and Polish

### Task 6.1: Update Build System

**File:** `build.zig`

```zig
// Add test commands

const test_step = b.step("test", "Run all unit tests");
test_step.dependOn(&unit_tests.step);

const test_e2e_wasm = b.step("test-e2e-wasm", "Run E2E tests on Wasm target");
// ...

const test_e2e_native = b.step("test-e2e-native", "Run E2E tests on Native target");
// ...

const test_parity = b.step("test-parity", "Run parity tests (Wasm vs Native)");
// ...

const test_all = b.step("test-all", "Run all tests including E2E and parity");
test_all.dependOn(test_step);
test_all.dependOn(test_e2e_wasm);
test_all.dependOn(test_e2e_native);
test_all.dependOn(test_parity);
```

**Checklist:**
- [ ] Add `test-e2e-wasm` step to build.zig
- [ ] Add `test-e2e-native` step to build.zig
- [ ] Add `test-parity` step to build.zig
- [ ] Add `test-all` meta-step

### Task 6.2: Add CLI Test Command

**Files to modify:**
- `compiler/main.zig`

```zig
// New CLI usage:
//   cot test                 # Run all tests in current directory
//   cot test path/to/file.cot # Run tests in specific file
//   cot test --filter "factorial" # Run tests matching pattern
//   cot test --target wasm   # Run tests only on Wasm
//   cot test --target native # Run tests only on Native
//   cot test --parity        # Run parity tests (both targets)
//   cot test --verbose       # Show all test names, not just failures
```

**Checklist:**
- [ ] Add `test` subcommand to CLI
- [ ] Implement `--filter` pattern matching
- [ ] Implement `--target` selection
- [ ] Implement `--parity` mode
- [ ] Implement `--verbose` output

---

## Implementation Order

For TDD to work effectively, implement in this order:

### Sprint 1: Foundation (Week 1)
1. **Task 1.1** - Source locations in SSA values
2. **Task 2.1** - Pretty printer module
3. **Task 5.1** - Port first 30 tests from bootstrap-0.2

### Sprint 2: Error Handling (Week 2)
4. **Task 1.2** - Source map module
5. **Task 1.3** - Emit source maps during codegen
6. **Task 3.1** - Runtime assertion support

### Sprint 3: Inline Tests (Week 3)
7. **Task 4.1** - Test syntax in parser
8. **Task 4.2** - Test harness generation
9. **Task 5.1** - Complete bootstrap-0.2 test port

### Sprint 4: Parity & CI (Week 4)
10. **Task 5.2** - Parity test runner
11. **Task 5.3** - CI integration
12. **Task 6.1** - Build system updates
13. **Task 6.2** - CLI test command

### Sprint 5: Polish (Week 5)
14. **Task 2.2** - Test result formatter
15. **Task 3.2** - Stack trace support
16. Documentation and examples

---

## Success Criteria

The testing framework is complete when:

1. **Source locations work:**
   - [ ] `assert()` failures show file:line:column
   - [ ] Runtime errors show source location
   - [ ] Stack traces show meaningful locations

2. **Pretty output works:**
   - [ ] Colored output (green pass, red fail)
   - [ ] Progress indicator during long test runs
   - [ ] Summary with pass/fail counts and timing

3. **Inline tests work:**
   - [ ] `test "name" { }` syntax parses
   - [ ] `cot test` discovers and runs inline tests
   - [ ] Tests can use `assert()` with good error messages

4. **E2E suite comprehensive:**
   - [ ] 166+ tests ported from bootstrap-0.2
   - [ ] All tiers covered (arithmetic through stress tests)
   - [ ] Tests run on both Wasm and Native

5. **Parity enforced:**
   - [ ] Same test produces same result on Wasm and Native
   - [ ] CI fails if parity is broken

---

## Reference Files

| Reference | Location |
|-----------|----------|
| Bootstrap E2E suite | `../bootstrap-0.2/archive/cot0/test/all_tests.cot` |
| Current Wasm E2E | `compiler/codegen/wasm_e2e_test.zig` |
| Current Native E2E | `compiler/codegen/native_e2e_test.zig` |
| Zig test syntax | `std/testing.zig` (reference for inline test pattern) |
| DWARF debugging | Reference for native debug info |
| Wasm sourcemap spec | Reference for Wasm debug info |

---

## Appendix: Example Test Output

```
═══ E2E Test Suite ═══

Running 166 tests...

✓ return constant
✓ multiplication
✓ division
✓ function call with parameter
✓ nested function calls
✓ factorial recursive
✗ pointer arithmetic
    Error: assertion failed: (buf + 8).* == 20
    at tests/e2e/all_tests.cot:583:5

    581 |     buf.* = 10
    582 |     let p1 = buf + 8
  > 583 |     assert((buf + 8).* == 20)
        |     ^
    584 |     ...

✓ bitwise NOT
✓ compound assignments
⊘ function pointers (skipped - not implemented)

═══ Summary ═══

165 passed, 1 failed, 1 skipped (2.3s)

═══ Parity Check ═══

Comparing Wasm vs Native results...
  ✓ 164/165 tests match
  ✗ pointer arithmetic: Wasm=10, Native=20

FAILED: Parity check found 1 mismatch
```
