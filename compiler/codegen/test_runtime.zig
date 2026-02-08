//! Test Runtime for Cot (WebAssembly)
//!
//! Provides test output functions for the `cot test` runner.
//! Reference: Zig test runner output format, Go runtime/print.go (cot_write pattern)
//!
//! Four functions:
//!   __test_print_name(ptr, len) -> void  — write 'test "name" ... ' to stderr
//!   __test_pass() -> void                — write "ok\n" to stderr
//!   __test_fail() -> void                — write "FAIL\n" to stderr
//!   __test_summary(passed, failed) -> void — write "\nN passed, M failed\n" to stderr

const std = @import("std");
const wasm = @import("wasm.zig");
const wasm_link = @import("wasm/wasm.zig");
const ValType = wasm_link.ValType;
const wasm_op = @import("wasm_opcodes.zig");
const BLOCK_VOID: u8 = wasm_op.BLOCK_VOID;

// =============================================================================
// Function Names
// =============================================================================

pub const TEST_PRINT_NAME_NAME = "__test_print_name";
pub const TEST_PASS_NAME = "__test_pass";
pub const TEST_FAIL_NAME = "__test_fail";
pub const TEST_SUMMARY_NAME = "__test_summary";

// =============================================================================
// Return Type
// =============================================================================

pub const TestFunctions = struct {
    test_print_name_idx: u32,
    test_pass_idx: u32,
    test_fail_idx: u32,
    test_summary_idx: u32,
};

// =============================================================================
// addToLinker — register all test runtime functions
// =============================================================================

pub fn addToLinker(allocator: std.mem.Allocator, linker: *@import("wasm/link.zig").Linker, write_func_idx: u32, eprint_int_func_idx: u32) !TestFunctions {
    // __test_print_name: (ptr: i64, len: i64) -> void
    const print_name_type = try linker.addType(
        &[_]ValType{ .i64, .i64 },
        &[_]ValType{},
    );
    const print_name_body = try generateTestPrintNameBody(allocator, write_func_idx);
    const test_print_name_idx = try linker.addFunc(.{
        .name = TEST_PRINT_NAME_NAME,
        .type_idx = print_name_type,
        .code = print_name_body,
        .exported = false,
    });

    // __test_pass: () -> void
    const pass_type = try linker.addType(
        &[_]ValType{},
        &[_]ValType{},
    );
    const pass_body = try generateTestPassBody(allocator, write_func_idx);
    const test_pass_idx = try linker.addFunc(.{
        .name = TEST_PASS_NAME,
        .type_idx = pass_type,
        .code = pass_body,
        .exported = false,
    });

    // __test_fail: () -> void
    const fail_body = try generateTestFailBody(allocator, write_func_idx);
    const test_fail_idx = try linker.addFunc(.{
        .name = TEST_FAIL_NAME,
        .type_idx = pass_type, // Same type: () -> void
        .code = fail_body,
        .exported = false,
    });

    // __test_summary: (passed: i64, failed: i64) -> void
    const summary_type = try linker.addType(
        &[_]ValType{ .i64, .i64 },
        &[_]ValType{},
    );
    const summary_body = try generateTestSummaryBody(allocator, write_func_idx, eprint_int_func_idx);
    const test_summary_idx = try linker.addFunc(.{
        .name = TEST_SUMMARY_NAME,
        .type_idx = summary_type,
        .code = summary_body,
        .exported = false,
    });

    return TestFunctions{
        .test_print_name_idx = test_print_name_idx,
        .test_pass_idx = test_pass_idx,
        .test_fail_idx = test_fail_idx,
        .test_summary_idx = test_summary_idx,
    };
}

// =============================================================================
// __test_print_name — writes: test "name" ...
//
// Algorithm:
//   1. Allocate stack buffer for prefix 'test "' (6 bytes) + '" ... ' (5 bytes) = 11 bytes overhead
//   2. Write 'test "' to stderr via cot_write
//   3. Write the name bytes to stderr via cot_write (ptr and len from params)
//   4. Write '" ... ' to stderr via cot_write
//
// Wasm locals layout:
//   param 0: ptr (i64) — pointer to name bytes
//   param 1: len (i64) — length of name
//   local 2: buf_ptr (i32) — base of stack buffer
// =============================================================================

fn generateTestPrintNameBody(allocator: std.mem.Allocator, write_func_idx: u32) ![]const u8 {
    var code = wasm.CodeBuilder.init(allocator);
    defer code.deinit();

    // Declare 1 local: buf_ptr (i32)
    _ = try code.declareLocals(&[_]wasm.ValType{.i32});
    // param 0 = ptr, param 1 = len, local 2 = buf_ptr

    // --- Allocate 16 bytes on Wasm stack for string literals ---
    try code.emitGlobalGet(0); // SP (i32)
    try code.emitI32Const(16);
    try code.emitI32Sub();
    try code.emitLocalTee(2); // buf_ptr = SP - 16
    try code.emitGlobalSet(0); // SP = buf_ptr

    // --- Write 'test "' (6 bytes) ---
    // Store 'test "' at buf_ptr
    // 't' = 0x74, 'e' = 0x65, 's' = 0x73, 't' = 0x74, ' ' = 0x20, '"' = 0x22
    try code.emitLocalGet(2); // buf_ptr
    try code.emitI64Const(0x2220_7473_6574); // "test \"" as little-endian i64
    try code.emitI64Store(3, 0);

    // Call cot_write(fd=2, ptr=buf_ptr, len=6)
    try code.emitI64Const(2); // fd = stderr
    try code.emitLocalGet(2); // buf_ptr
    try code.emitI64ExtendI32U();
    try code.emitI64Const(6); // len = 6
    try code.emitCall(write_func_idx);
    try code.emitDrop(); // drop return value

    // --- Write name bytes (ptr, len from params) ---
    try code.emitI64Const(2); // fd = stderr
    try code.emitLocalGet(0); // ptr (param 0)
    try code.emitLocalGet(1); // len (param 1)
    try code.emitCall(write_func_idx);
    try code.emitDrop(); // drop return value

    // --- Write '" ... ' (5 bytes) ---
    // '"' = 0x22, ' ' = 0x20, '.' = 0x2E, '.' = 0x2E, '.' = 0x2E, ' ' = 0x20
    // Actually: '" ... ' is: 0x22 0x20 0x2E 0x2E 0x2E 0x20 = 6 bytes
    try code.emitLocalGet(2); // buf_ptr
    try code.emitI64Const(0x202E_2E2E_2022); // '" ... ' as little-endian i64
    try code.emitI64Store(3, 0);

    try code.emitI64Const(2); // fd = stderr
    try code.emitLocalGet(2); // buf_ptr
    try code.emitI64ExtendI32U();
    try code.emitI64Const(6); // len = 6
    try code.emitCall(write_func_idx);
    try code.emitDrop(); // drop return value

    // --- Restore stack pointer ---
    try code.emitLocalGet(2); // buf_ptr
    try code.emitI32Const(16);
    try code.emitI32Add();
    try code.emitGlobalSet(0); // SP = original

    return try code.finish();
}

// =============================================================================
// __test_pass — writes "ok\n" to stderr
// =============================================================================

fn generateTestPassBody(allocator: std.mem.Allocator, write_func_idx: u32) ![]const u8 {
    var code = wasm.CodeBuilder.init(allocator);
    defer code.deinit();

    // Declare 1 local: buf_ptr (i32)
    _ = try code.declareLocals(&[_]wasm.ValType{.i32});
    // local 0 = buf_ptr

    // Allocate 8 bytes on stack
    try code.emitGlobalGet(0);
    try code.emitI32Const(8);
    try code.emitI32Sub();
    try code.emitLocalTee(0);
    try code.emitGlobalSet(0);

    // Store "ok\n" at buf_ptr: 'o' = 0x6F, 'k' = 0x6B, '\n' = 0x0A
    try code.emitLocalGet(0);
    try code.emitI64Const(0x0A_6B6F); // "ok\n" as little-endian
    try code.emitI64Store(3, 0);

    // cot_write(fd=2, buf_ptr, 3)
    try code.emitI64Const(2); // fd = stderr
    try code.emitLocalGet(0);
    try code.emitI64ExtendI32U();
    try code.emitI64Const(3); // len = 3
    try code.emitCall(write_func_idx);
    try code.emitDrop();

    // Restore stack pointer
    try code.emitLocalGet(0);
    try code.emitI32Const(8);
    try code.emitI32Add();
    try code.emitGlobalSet(0);

    return try code.finish();
}

// =============================================================================
// __test_fail — writes "FAIL\n" to stderr
// =============================================================================

fn generateTestFailBody(allocator: std.mem.Allocator, write_func_idx: u32) ![]const u8 {
    var code = wasm.CodeBuilder.init(allocator);
    defer code.deinit();

    // Declare 1 local: buf_ptr (i32)
    _ = try code.declareLocals(&[_]wasm.ValType{.i32});
    // local 0 = buf_ptr

    // Allocate 8 bytes on stack
    try code.emitGlobalGet(0);
    try code.emitI32Const(8);
    try code.emitI32Sub();
    try code.emitLocalTee(0);
    try code.emitGlobalSet(0);

    // Store "FAIL\n" at buf_ptr: 'F' = 0x46, 'A' = 0x41, 'I' = 0x49, 'L' = 0x4C, '\n' = 0x0A
    try code.emitLocalGet(0);
    try code.emitI64Const(0x0A_4C49_4146); // "FAIL\n" as little-endian
    try code.emitI64Store(3, 0);

    // cot_write(fd=2, buf_ptr, 5)
    try code.emitI64Const(2); // fd = stderr
    try code.emitLocalGet(0);
    try code.emitI64ExtendI32U();
    try code.emitI64Const(5); // len = 5
    try code.emitCall(write_func_idx);
    try code.emitDrop();

    // Restore stack pointer
    try code.emitLocalGet(0);
    try code.emitI32Const(8);
    try code.emitI32Add();
    try code.emitGlobalSet(0);

    return try code.finish();
}

// =============================================================================
// __test_summary — writes "\nN passed, M failed\n" or "\nN passed\n" to stderr
//
// Algorithm:
//   1. Write "\n" to stderr
//   2. Call eprint_int(passed) to print the number
//   3. Write " passed" to stderr (7 bytes)
//   4. If failed > 0: write ", " + eprint_int(failed) + " failed"
//   5. Write "\n" to stderr
//
// Wasm locals layout:
//   param 0: passed (i64)
//   param 1: failed (i64)
//   local 2: buf_ptr (i32) — base of stack buffer
// =============================================================================

fn generateTestSummaryBody(allocator: std.mem.Allocator, write_func_idx: u32, eprint_int_func_idx: u32) ![]const u8 {
    var code = wasm.CodeBuilder.init(allocator);
    defer code.deinit();

    // Declare 1 local: buf_ptr (i32)
    _ = try code.declareLocals(&[_]wasm.ValType{.i32});
    // param 0 = passed, param 1 = failed, local 2 = buf_ptr

    // --- Allocate 16 bytes on Wasm stack ---
    try code.emitGlobalGet(0); // SP (i32)
    try code.emitI32Const(16);
    try code.emitI32Sub();
    try code.emitLocalTee(2); // buf_ptr = SP - 16
    try code.emitGlobalSet(0); // SP = buf_ptr

    // --- Write "\n" (1 byte) ---
    try code.emitLocalGet(2);
    try code.emitI64Const(0x0A); // "\n"
    try code.emitI64Store(3, 0);

    try code.emitI64Const(2); // fd = stderr
    try code.emitLocalGet(2);
    try code.emitI64ExtendI32U();
    try code.emitI64Const(1); // len = 1
    try code.emitCall(write_func_idx);
    try code.emitDrop();

    // --- Print passed count via eprint_int ---
    try code.emitLocalGet(0); // passed
    try code.emitCall(eprint_int_func_idx);

    // --- Write " passed" (7 bytes) ---
    // ' ' = 0x20, 'p' = 0x70, 'a' = 0x61, 's' = 0x73, 's' = 0x73, 'e' = 0x65, 'd' = 0x64
    // little-endian i64: 0x64_6573_7361_7020 = "passed " reversed... let me compute:
    // bytes: 0x20 0x70 0x61 0x73 0x73 0x65 0x64 0x00
    // as i64 little-endian: 0x00_6465_7373_6170_20
    try code.emitLocalGet(2);
    try code.emitI64Const(0x00_6465_7373_6170_20); // " passed\0" as little-endian i64
    try code.emitI64Store(3, 0);

    try code.emitI64Const(2); // fd = stderr
    try code.emitLocalGet(2);
    try code.emitI64ExtendI32U();
    try code.emitI64Const(7); // len = 7
    try code.emitCall(write_func_idx);
    try code.emitDrop();

    // --- If failed > 0: write ", " + eprint_int(failed) + " failed" ---
    try code.emitLocalGet(1); // failed
    try code.emitI64Const(0);
    try code.emitI64GtS(); // failed > 0?
    try code.emitIf(BLOCK_VOID);
    {
        // Write ", " (2 bytes)
        try code.emitLocalGet(2);
        try code.emitI64Const(0x202C); // ", " as little-endian
        try code.emitI64Store(3, 0);

        try code.emitI64Const(2); // fd = stderr
        try code.emitLocalGet(2);
        try code.emitI64ExtendI32U();
        try code.emitI64Const(2); // len = 2
        try code.emitCall(write_func_idx);
        try code.emitDrop();

        // Print failed count
        try code.emitLocalGet(1); // failed
        try code.emitCall(eprint_int_func_idx);

        // Write " failed" (7 bytes)
        // ' ' = 0x20, 'f' = 0x66, 'a' = 0x61, 'i' = 0x69, 'l' = 0x6C, 'e' = 0x65, 'd' = 0x64
        // as i64 little-endian: 0x00_6465_6C69_6166_20
        try code.emitLocalGet(2);
        try code.emitI64Const(0x00_6465_6C69_6166_20); // " failed\0" as little-endian i64
        try code.emitI64Store(3, 0);

        try code.emitI64Const(2); // fd = stderr
        try code.emitLocalGet(2);
        try code.emitI64ExtendI32U();
        try code.emitI64Const(7); // len = 7
        try code.emitCall(write_func_idx);
        try code.emitDrop();
    }
    try code.emitEnd(); // end if

    // --- Write "\n" (1 byte) ---
    try code.emitLocalGet(2);
    try code.emitI64Const(0x0A); // "\n"
    try code.emitI64Store(3, 0);

    try code.emitI64Const(2); // fd = stderr
    try code.emitLocalGet(2);
    try code.emitI64ExtendI32U();
    try code.emitI64Const(1); // len = 1
    try code.emitCall(write_func_idx);
    try code.emitDrop();

    // --- Restore stack pointer ---
    try code.emitLocalGet(2);
    try code.emitI32Const(16);
    try code.emitI32Add();
    try code.emitGlobalSet(0); // SP = original

    return try code.finish();
}
