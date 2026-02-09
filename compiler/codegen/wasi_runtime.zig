//! WASI Runtime for Cot (WebAssembly)
//!
//! Provides WASI-compatible I/O functions.
//! Reference: WASI preview1 (Go: syscall/fs_wasip1.go, Wasmtime: wasi-common)
//!
//! Functions:
//!   wasi_fd_write(fd, iovs, iovs_len, nwritten) -> i64  — WASI fd_write (stub, ARM64 override)
//!   cot_fd_write_simple(fd, ptr, len) -> i64             — simple write (stub, ARM64 override)
//!   cot_fd_read_simple(fd, buf, len) -> i64              — simple read (stub, ARM64 override)
//!   cot_fd_close(fd) -> i64                              — close fd (stub, ARM64 override)

const std = @import("std");
const wasm = @import("wasm.zig");
const wasm_link = @import("wasm/wasm.zig");
const ValType = wasm_link.ValType;

const wasm_op = @import("wasm_opcodes.zig");

// =============================================================================
// Function Names
// =============================================================================

pub const FD_WRITE_NAME = "wasi_fd_write";
pub const FD_WRITE_SIMPLE_NAME = "cot_fd_write_simple";
pub const FD_READ_SIMPLE_NAME = "cot_fd_read_simple";
pub const FD_CLOSE_NAME = "cot_fd_close";

// =============================================================================
// Return Type
// =============================================================================

pub const WasiFunctions = struct {
    fd_write_idx: u32,
    fd_write_simple_idx: u32,
    fd_read_simple_idx: u32,
    fd_close_idx: u32,
};

// =============================================================================
// addToLinker — register all WASI runtime functions
// =============================================================================

pub fn addToLinker(allocator: std.mem.Allocator, linker: *@import("wasm/link.zig").Linker) !WasiFunctions {
    // wasi_fd_write: (fd: i64, iovs: i64, iovs_len: i64, nwritten: i64) -> i64
    // Returns WASI errno (0 = success)
    const fd_write_type = try linker.addType(
        &[_]ValType{ .i64, .i64, .i64, .i64 },
        &[_]ValType{.i64},
    );
    const fd_write_body = try generateFdWriteStubBody(allocator);
    const fd_write_idx = try linker.addFunc(.{
        .name = FD_WRITE_NAME,
        .type_idx = fd_write_type,
        .code = fd_write_body,
        .exported = true, // So generateMachO can find it by name for ARM64 override
    });

    // cot_fd_write_simple: (fd: i64, ptr: i64, len: i64) -> i64
    // Same signature as cot_write. Exported so native can override with ARM64 syscall.
    // Wasm stub returns 0. On native, ARM64 override does real SYS_write.
    const fd_write_simple_type = try linker.addType(
        &[_]ValType{ .i64, .i64, .i64 },
        &[_]ValType{.i64},
    );
    const fd_write_simple_body = try generateStubReturnsZero(allocator);
    const fd_write_simple_idx = try linker.addFunc(.{
        .name = FD_WRITE_SIMPLE_NAME,
        .type_idx = fd_write_simple_type,
        .code = fd_write_simple_body,
        .exported = true, // So generateMachO can find it for ARM64 override
    });

    // cot_fd_read_simple: (fd: i64, buf: i64, len: i64) -> i64
    // Reference: Go syscall/fs_wasip1.go:900 Read() — builds 1-element iovec, calls fd_read
    // Same pattern as cot_fd_write_simple: stub on Wasm, ARM64 SYS_read override on native.
    // Returns bytes read (0 = EOF).
    const fd_read_simple_body = try generateStubReturnsZero(allocator);
    const fd_read_simple_idx = try linker.addFunc(.{
        .name = FD_READ_SIMPLE_NAME,
        .type_idx = fd_write_simple_type, // Same type: (i64, i64, i64) -> i64
        .code = fd_read_simple_body,
        .exported = true, // ARM64 override in driver.zig
    });

    // cot_fd_close: (fd: i64) -> i64
    // Reference: Go syscall/fs_wasip1.go:203 fd_close(fd int32) Errno
    // Returns 0 on success, WASI errno on error.
    const fd_close_type = try linker.addType(
        &[_]ValType{.i64},
        &[_]ValType{.i64},
    );
    const fd_close_body = try generateStubReturnsZero(allocator);
    const fd_close_idx = try linker.addFunc(.{
        .name = FD_CLOSE_NAME,
        .type_idx = fd_close_type,
        .code = fd_close_body,
        .exported = true, // ARM64 override in driver.zig
    });

    return WasiFunctions{
        .fd_write_idx = fd_write_idx,
        .fd_write_simple_idx = fd_write_simple_idx,
        .fd_read_simple_idx = fd_read_simple_idx,
        .fd_close_idx = fd_close_idx,
    };
}

// =============================================================================
// wasi_fd_write stub — returns ENOSYS (52)
// Pure Wasm can't do I/O; native overrides this with ARM64 syscall
// =============================================================================

fn generateFdWriteStubBody(allocator: std.mem.Allocator) ![]const u8 {
    var code = wasm.CodeBuilder.init(allocator);
    defer code.deinit();

    // Parameters: fd (local 0), iovs (local 1), iovs_len (local 2), nwritten (local 3)
    // Stub: return 52 (WASI ENOSYS)
    try code.emitI64Const(52);
    return try code.finish();
}

// =============================================================================
// Shared stub — drops args, returns i64(0)
// Used by cot_fd_write_simple, cot_fd_read_simple, cot_fd_close.
// Same pattern as cot_write: Wasm can't do I/O, native overrides with ARM64 syscall.
// Reference: print_runtime.zig generateWriteStubBody
// =============================================================================

fn generateStubReturnsZero(allocator: std.mem.Allocator) ![]const u8 {
    var code = wasm.CodeBuilder.init(allocator);
    defer code.deinit();

    try code.emitI64Const(0);
    return try code.finish();
}
