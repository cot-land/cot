# Phase 7 - Phase D: End-to-End Tests

**Created**: 2026-02-03
**Status**: COMPLETE (2026-02-03)
**Based On**: Cranelift test infrastructure

---

## Executive Summary

Phase D completes the integration testing to verify the full native compilation pipeline:
- Task 7.8: End-to-end tests - Verify complete Wasm→CLIF→VCode→Native→Object flow

**Goal**: Demonstrate that the Cranelift port can produce working native executables.

---

## Task 7.8: End-to-End Tests

**Status**: [ ] IN PROGRESS

### Test Strategy

We need to test the complete pipeline:
1. Parse Wasm bytecode
2. Translate to CLIF IR
3. Lower to VCode (virtual registers)
4. Run register allocation
5. Emit machine code
6. Generate object file
7. Link with system linker
8. Run the executable

### Test Cases

#### 7.8.1 Simple Return
Simplest possible function - just return a constant.

```
fn main() i64 {
    return 42
}
```

Expected: Exit code 42

#### 7.8.2 Arithmetic
Test basic i64 arithmetic operations.

```
fn main() i64 {
    return 10 + 20 + 12
}
```

Expected: Exit code 42

#### 7.8.3 Local Variables
Test local variable usage.

```
fn main() i64 {
    let a = 20
    let b = 22
    return a + b
}
```

Expected: Exit code 42

#### 7.8.4 Function Calls
Test calling between functions.

```
fn add(a: i64, b: i64) i64 {
    return a + b
}

fn main() i64 {
    return add(20, 22)
}
```

Expected: Exit code 42

#### 7.8.5 Control Flow
Test if/else control flow.

```
fn main() i64 {
    let x = 10
    if x > 5 {
        return 42
    } else {
        return 0
    }
}
```

Expected: Exit code 42

### Implementation Plan

#### 7.8.1 Create Native Test Infrastructure
- [ ] Create `compiler/codegen/native/tests/` directory
- [ ] Create test harness that:
  - Compiles Cot source to object file
  - Links with clang/ld
  - Runs the executable
  - Verifies exit code

#### 7.8.2 Add Test Cases
- [ ] Simple return test
- [ ] Arithmetic test
- [ ] Local variables test
- [ ] Function calls test
- [ ] Control flow test

#### 7.8.3 Integration with Test Suite
- [ ] Add native tests to `zig build test`
- [ ] Skip on unsupported platforms

### Test Implementation

```zig
test "native e2e: return 42" {
    const allocator = std.testing.allocator;

    // Compile to object file
    var driver = Driver.init(allocator);
    driver.setTarget(.{ .arch = .aarch64, .os = .macos });
    const obj_bytes = try driver.compileSource("fn main() i64 { return 42 }");
    defer allocator.free(obj_bytes);

    // Write to temp file
    const tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    const obj_path = try tmp_dir.dir.realpathAlloc(allocator, "test.o");
    defer allocator.free(obj_path);
    try tmp_dir.dir.writeFile("test.o", obj_bytes);

    // Link with clang
    var link_proc = std.process.Child.init(&.{
        "clang", obj_path, "-o", "test_exe",
    }, allocator);
    _ = try link_proc.spawnAndWait();

    // Run and check exit code
    var run_proc = std.process.Child.init(&.{"./test_exe"}, allocator);
    const term = try run_proc.spawnAndWait();
    try std.testing.expectEqual(@as(u8, 42), term.Exited);
}
```

---

## Progress Tracking

### Overall Progress
- [ ] Task 7.8.1: Create test infrastructure
- [ ] Task 7.8.2: Add test cases
- [ ] Task 7.8.3: Integration with test suite

### Test Status
- [ ] Simple return compiles and runs
- [ ] Arithmetic compiles and runs
- [ ] Local variables compile and run
- [ ] Function calls compile and run
- [ ] Control flow compiles and runs

---

## Files To Create

| File | Status | Description |
|------|--------|-------------|
| `native/tests/e2e.zig` | [ ] Create | End-to-end test cases |

---

## Notes

- Tests may need to be skipped on CI if clang/ld not available
- Platform-specific (ARM64 macOS vs x86_64 Linux)
- Focus on verifying the pipeline works, not comprehensive coverage
