//! I/O Runtime for Direct Native Backend — CLIF IR Generation
//!
//! Generates thin I/O wrapper functions as CLIF IR, compiled through native_compile.compile().
//! Each function forwards to the corresponding libc call.
//!
//! Reference: compiler/codegen/wasi_runtime.zig (Wasm I/O path)
//! Reference: cg_clif abi/mod.rs:183-201 (lib_call pattern for external calls)

const std = @import("std");
const Allocator = std.mem.Allocator;

const clif = @import("../../ir/clif/mod.zig");
const frontend_mod = @import("frontend/mod.zig");
const FunctionBuilder = frontend_mod.FunctionBuilder;
const FunctionBuilderContext = frontend_mod.FunctionBuilderContext;
const native_compile = @import("compile.zig");
const arc_native = @import("arc_native.zig");
const RuntimeFunc = arc_native.RuntimeFunc;

const debug = @import("../../pipeline_debug.zig");

/// Generate all I/O runtime functions as compiled native code.
pub fn generate(
    allocator: Allocator,
    isa: native_compile.TargetIsa,
    ctrl_plane: *native_compile.ControlPlane,
    func_index_map: *const std.StringHashMapUnmanaged(u32),
) !std.ArrayListUnmanaged(RuntimeFunc) {
    var result = std.ArrayListUnmanaged(RuntimeFunc){};
    errdefer {
        for (result.items) |*rf| rf.compiled.deinit();
        result.deinit(allocator);
    }

    // fd_write(fd, ptr, len) → i64  (calls libc write)
    try result.append(allocator, .{
        .name = "fd_write",
        .compiled = try generateForward3(allocator, isa, ctrl_plane, func_index_map, "write", true),
    });

    // fd_read(fd, buf, len) → i64  (calls libc read)
    try result.append(allocator, .{
        .name = "fd_read",
        .compiled = try generateForward3(allocator, isa, ctrl_plane, func_index_map, "read", true),
    });

    // fd_close(fd) → i64  (calls libc close)
    try result.append(allocator, .{
        .name = "fd_close",
        .compiled = try generateForward1(allocator, isa, ctrl_plane, func_index_map, "close", true),
    });

    // exit(code) → void  (calls libc _exit)
    try result.append(allocator, .{
        .name = "exit",
        .compiled = try generateExit(allocator, isa, ctrl_plane, func_index_map),
    });

    // fd_seek(fd, offset, whence) → i64  (calls libc lseek)
    try result.append(allocator, .{
        .name = "fd_seek",
        .compiled = try generateForward3(allocator, isa, ctrl_plane, func_index_map, "lseek", true),
    });

    // memset_zero(ptr, size) → void  (calls libc memset(ptr, 0, size))
    try result.append(allocator, .{
        .name = "memset_zero",
        .compiled = try generateMemsetZero(allocator, isa, ctrl_plane, func_index_map),
    });

    // fd_open(path_ptr, path_len, flags) → i64  (null-terminates path, calls libc open)
    try result.append(allocator, .{
        .name = "fd_open",
        .compiled = try generateFdOpen(allocator, isa, ctrl_plane, func_index_map),
    });

    // time() → i64  (nanoseconds since epoch, calls libc gettimeofday)
    try result.append(allocator, .{
        .name = "time",
        .compiled = try generateTime(allocator, isa, ctrl_plane, func_index_map),
    });

    // random(buf, len) → i64  (calls libc getentropy)
    try result.append(allocator, .{
        .name = "random",
        .compiled = try generateForward2(allocator, isa, ctrl_plane, func_index_map, "getentropy"),
    });

    // isatty(fd) → i64: no wrapper needed, libc isatty is ABI-compatible.
    // User code calls the libc symbol directly via external reference.

    return result;
}

// ============================================================================
// Generic forwarding: 3-param function → 3-param libc call
// Used for: fd_write→write, fd_read→read, fd_seek→lseek
// ============================================================================

fn generateForward3(
    allocator: Allocator,
    isa: native_compile.TargetIsa,
    ctrl_plane: *native_compile.ControlPlane,
    func_index_map: *const std.StringHashMapUnmanaged(u32),
    libc_name: []const u8,
    has_return: bool,
) !native_compile.CompiledCode {
    var clif_func = clif.Function.init(allocator);
    defer clif_func.deinit();

    var func_ctx = FunctionBuilderContext.init(allocator);
    defer func_ctx.deinit();
    var builder = FunctionBuilder.init(&clif_func, &func_ctx);

    // Signature: (i64, i64, i64) -> i64 (or void)
    try clif_func.signature.addParam(allocator, clif.AbiParam.init(clif.Type.I64));
    try clif_func.signature.addParam(allocator, clif.AbiParam.init(clif.Type.I64));
    try clif_func.signature.addParam(allocator, clif.AbiParam.init(clif.Type.I64));
    if (has_return) {
        try clif_func.signature.addReturn(allocator, clif.AbiParam.init(clif.Type.I64));
    }

    const block_entry = try builder.createBlock();
    builder.switchToBlock(block_entry);
    try builder.appendBlockParamsForFunctionParams(block_entry);
    try builder.ensureInsertedBlock();

    const ins = builder.ins();
    const params = builder.blockParams(block_entry);

    // Call libc function with same arguments
    const libc_idx = func_index_map.get(libc_name) orelse 0;
    var libc_sig = clif.Signature.init(.system_v);
    try libc_sig.addParam(allocator, clif.AbiParam.init(clif.Type.I64));
    try libc_sig.addParam(allocator, clif.AbiParam.init(clif.Type.I64));
    try libc_sig.addParam(allocator, clif.AbiParam.init(clif.Type.I64));
    if (has_return) {
        try libc_sig.addReturn(allocator, clif.AbiParam.init(clif.Type.I64));
    }
    const sig_ref = try builder.importSignature(libc_sig);
    const func_ref = try builder.importFunction(.{
        .name = .{ .user = .{ .namespace = 0, .index = libc_idx } },
        .signature = sig_ref,
        .colocated = false,
    });
    const call_result = try ins.call(func_ref, &[_]clif.Value{ params[0], params[1], params[2] });

    if (has_return) {
        _ = try ins.return_(&[_]clif.Value{call_result.results[0]});
    } else {
        _ = try ins.return_(&[_]clif.Value{});
    }

    try builder.sealAllBlocks();
    builder.finalize();

    return native_compile.compile(allocator, &clif_func, isa, ctrl_plane);
}

// ============================================================================
// Generic forwarding: 1-param function → 1-param libc call
// Used for: fd_close→close
// ============================================================================

fn generateForward1(
    allocator: Allocator,
    isa: native_compile.TargetIsa,
    ctrl_plane: *native_compile.ControlPlane,
    func_index_map: *const std.StringHashMapUnmanaged(u32),
    libc_name: []const u8,
    has_return: bool,
) !native_compile.CompiledCode {
    var clif_func = clif.Function.init(allocator);
    defer clif_func.deinit();

    var func_ctx = FunctionBuilderContext.init(allocator);
    defer func_ctx.deinit();
    var builder = FunctionBuilder.init(&clif_func, &func_ctx);

    try clif_func.signature.addParam(allocator, clif.AbiParam.init(clif.Type.I64));
    if (has_return) {
        try clif_func.signature.addReturn(allocator, clif.AbiParam.init(clif.Type.I64));
    }

    const block_entry = try builder.createBlock();
    builder.switchToBlock(block_entry);
    try builder.appendBlockParamsForFunctionParams(block_entry);
    try builder.ensureInsertedBlock();

    const ins = builder.ins();
    const params = builder.blockParams(block_entry);

    const libc_idx = func_index_map.get(libc_name) orelse 0;
    var libc_sig = clif.Signature.init(.system_v);
    try libc_sig.addParam(allocator, clif.AbiParam.init(clif.Type.I64));
    if (has_return) {
        try libc_sig.addReturn(allocator, clif.AbiParam.init(clif.Type.I64));
    }
    const sig_ref = try builder.importSignature(libc_sig);
    const func_ref = try builder.importFunction(.{
        .name = .{ .user = .{ .namespace = 0, .index = libc_idx } },
        .signature = sig_ref,
        .colocated = false,
    });
    const call_result = try ins.call(func_ref, &[_]clif.Value{params[0]});

    if (has_return) {
        _ = try ins.return_(&[_]clif.Value{call_result.results[0]});
    } else {
        _ = try ins.return_(&[_]clif.Value{});
    }

    try builder.sealAllBlocks();
    builder.finalize();

    return native_compile.compile(allocator, &clif_func, isa, ctrl_plane);
}

// ============================================================================
// exit(code: i64) → void
// Calls libc _exit(code). Does not return.
// Reference: wasi_runtime.zig exit function
// ============================================================================

fn generateExit(
    allocator: Allocator,
    isa: native_compile.TargetIsa,
    ctrl_plane: *native_compile.ControlPlane,
    func_index_map: *const std.StringHashMapUnmanaged(u32),
) !native_compile.CompiledCode {
    var clif_func = clif.Function.init(allocator);
    defer clif_func.deinit();

    var func_ctx = FunctionBuilderContext.init(allocator);
    defer func_ctx.deinit();
    var builder = FunctionBuilder.init(&clif_func, &func_ctx);

    // Signature: (i64) -> void
    try clif_func.signature.addParam(allocator, clif.AbiParam.init(clif.Type.I64));

    const block_entry = try builder.createBlock();
    builder.switchToBlock(block_entry);
    try builder.appendBlockParamsForFunctionParams(block_entry);
    try builder.ensureInsertedBlock();

    const ins = builder.ins();
    const code = builder.blockParams(block_entry)[0];

    // Call _exit(code) — does not return
    const exit_idx = func_index_map.get("_exit") orelse 0;
    var exit_sig = clif.Signature.init(.system_v);
    try exit_sig.addParam(allocator, clif.AbiParam.init(clif.Type.I64));
    const sig_ref = try builder.importSignature(exit_sig);
    const func_ref = try builder.importFunction(.{
        .name = .{ .user = .{ .namespace = 0, .index = exit_idx } },
        .signature = sig_ref,
        .colocated = false,
    });
    _ = try ins.call(func_ref, &[_]clif.Value{code});

    // _exit doesn't return, but CLIF needs a terminator
    _ = try ins.return_(&[_]clif.Value{});

    try builder.sealAllBlocks();
    builder.finalize();

    return native_compile.compile(allocator, &clif_func, isa, ctrl_plane);
}

// ============================================================================
// memset_zero(ptr: i64, size: i64) → void
// Calls libc memset(ptr, 0, size).
// Reference: arc.zig memset_zero
// ============================================================================

fn generateMemsetZero(
    allocator: Allocator,
    isa: native_compile.TargetIsa,
    ctrl_plane: *native_compile.ControlPlane,
    func_index_map: *const std.StringHashMapUnmanaged(u32),
) !native_compile.CompiledCode {
    var clif_func = clif.Function.init(allocator);
    defer clif_func.deinit();

    var func_ctx = FunctionBuilderContext.init(allocator);
    defer func_ctx.deinit();
    var builder = FunctionBuilder.init(&clif_func, &func_ctx);

    // Signature: (ptr: i64, size: i64) → void
    try clif_func.signature.addParam(allocator, clif.AbiParam.init(clif.Type.I64));
    try clif_func.signature.addParam(allocator, clif.AbiParam.init(clif.Type.I64));

    const block_entry = try builder.createBlock();
    builder.switchToBlock(block_entry);
    try builder.appendBlockParamsForFunctionParams(block_entry);
    try builder.ensureInsertedBlock();

    const ins = builder.ins();
    const params = builder.blockParams(block_entry);
    const ptr = params[0];
    const size = params[1];

    // Call memset(ptr, 0, size) — libc signature: memset(void*, int, size_t) → void*
    const memset_idx = func_index_map.get("memset") orelse 0;
    var libc_sig = clif.Signature.init(.system_v);
    try libc_sig.addParam(allocator, clif.AbiParam.init(clif.Type.I64));
    try libc_sig.addParam(allocator, clif.AbiParam.init(clif.Type.I64)); // 0 as i64
    try libc_sig.addParam(allocator, clif.AbiParam.init(clif.Type.I64));
    try libc_sig.addReturn(allocator, clif.AbiParam.init(clif.Type.I64)); // memset returns ptr
    const sig_ref = try builder.importSignature(libc_sig);
    const func_ref = try builder.importFunction(.{
        .name = .{ .user = .{ .namespace = 0, .index = memset_idx } },
        .signature = sig_ref,
        .colocated = false,
    });
    const v_zero = try ins.iconst(clif.Type.I64, 0);
    _ = try ins.call(func_ref, &[_]clif.Value{ ptr, v_zero, size });
    _ = try ins.return_(&[_]clif.Value{});

    try builder.sealAllBlocks();
    builder.finalize();

    return native_compile.compile(allocator, &clif_func, isa, ctrl_plane);
}

// ============================================================================
// fd_open(path_ptr: i64, path_len: i64, flags: i64) → i64
// Null-terminates the path string, then calls libc open(path, flags, 0666).
// Reference: wasi_runtime.zig generateWasiPathOpenShim
// ============================================================================

fn generateFdOpen(
    allocator: Allocator,
    isa: native_compile.TargetIsa,
    ctrl_plane: *native_compile.ControlPlane,
    func_index_map: *const std.StringHashMapUnmanaged(u32),
) !native_compile.CompiledCode {
    var clif_func = clif.Function.init(allocator);
    defer clif_func.deinit();

    var func_ctx = FunctionBuilderContext.init(allocator);
    defer func_ctx.deinit();
    var builder = FunctionBuilder.init(&clif_func, &func_ctx);

    // Signature: (path_ptr: i64, path_len: i64, flags: i64) → i64
    try clif_func.signature.addParam(allocator, clif.AbiParam.init(clif.Type.I64));
    try clif_func.signature.addParam(allocator, clif.AbiParam.init(clif.Type.I64));
    try clif_func.signature.addParam(allocator, clif.AbiParam.init(clif.Type.I64));
    try clif_func.signature.addReturn(allocator, clif.AbiParam.init(clif.Type.I64));

    const block_entry = try builder.createBlock();
    builder.switchToBlock(block_entry);
    try builder.appendBlockParamsForFunctionParams(block_entry);
    try builder.ensureInsertedBlock();

    const insb = builder.ins();
    const params = builder.blockParams(block_entry);
    const path_ptr = params[0];
    const path_len = params[1];
    const flags = params[2];

    // Allocate stack buffer for null-terminated path (1024 bytes = PATH_MAX)
    const path_slot = try builder.createSizedStackSlot(
        clif.StackSlotData.explicit(1024, 3), // 1024 bytes, 8-byte aligned
    );
    const buf_addr = try insb.stackAddr(clif.Type.I64, path_slot, 0);

    // Call memcpy(buf_addr, path_ptr, path_len) to copy path to stack
    const memcpy_idx = func_index_map.get("memcpy") orelse 0;
    var memcpy_sig = clif.Signature.init(.system_v);
    try memcpy_sig.addParam(allocator, clif.AbiParam.init(clif.Type.I64));
    try memcpy_sig.addParam(allocator, clif.AbiParam.init(clif.Type.I64));
    try memcpy_sig.addParam(allocator, clif.AbiParam.init(clif.Type.I64));
    try memcpy_sig.addReturn(allocator, clif.AbiParam.init(clif.Type.I64));
    const memcpy_sig_ref = try builder.importSignature(memcpy_sig);
    const memcpy_ref = try builder.importFunction(.{
        .name = .{ .user = .{ .namespace = 0, .index = memcpy_idx } },
        .signature = memcpy_sig_ref,
        .colocated = false,
    });
    _ = try insb.call(memcpy_ref, &[_]clif.Value{ buf_addr, path_ptr, path_len });

    // Null-terminate: store 0 at buf_addr + path_len
    const null_addr = try insb.iadd(buf_addr, path_len);
    const v_zero_byte = try insb.iconst(clif.Type.I8, 0);
    _ = try insb.store(.{}, v_zero_byte, null_addr, 0);

    // Call open(buf_addr, flags, 0o666) → fd
    const open_idx = func_index_map.get("open") orelse 0;
    var open_sig = clif.Signature.init(.system_v);
    try open_sig.addParam(allocator, clif.AbiParam.init(clif.Type.I64)); // path
    try open_sig.addParam(allocator, clif.AbiParam.init(clif.Type.I64)); // flags
    try open_sig.addParam(allocator, clif.AbiParam.init(clif.Type.I64)); // mode
    try open_sig.addReturn(allocator, clif.AbiParam.init(clif.Type.I64));
    const open_sig_ref = try builder.importSignature(open_sig);
    const open_ref = try builder.importFunction(.{
        .name = .{ .user = .{ .namespace = 0, .index = open_idx } },
        .signature = open_sig_ref,
        .colocated = false,
    });
    const mode = try insb.iconst(clif.Type.I64, 0o666);
    const call_result = try insb.call(open_ref, &[_]clif.Value{ buf_addr, flags, mode });

    _ = try insb.return_(&[_]clif.Value{call_result.results[0]});

    try builder.sealAllBlocks();
    builder.finalize();

    return native_compile.compile(allocator, &clif_func, isa, ctrl_plane);
}

// ============================================================================
// time() → i64
// Returns nanoseconds since epoch. Calls libc gettimeofday(&tv, NULL).
// Computes: tv_sec * 1_000_000_000 + tv_usec * 1_000
// Reference: wasi_runtime.zig generateWasiTimeShim
// ============================================================================

fn generateTime(
    allocator: Allocator,
    isa: native_compile.TargetIsa,
    ctrl_plane: *native_compile.ControlPlane,
    func_index_map: *const std.StringHashMapUnmanaged(u32),
) !native_compile.CompiledCode {
    var clif_func = clif.Function.init(allocator);
    defer clif_func.deinit();

    var func_ctx = FunctionBuilderContext.init(allocator);
    defer func_ctx.deinit();
    var builder = FunctionBuilder.init(&clif_func, &func_ctx);

    // Signature: () → i64
    try clif_func.signature.addReturn(allocator, clif.AbiParam.init(clif.Type.I64));

    const block_entry = try builder.createBlock();
    builder.switchToBlock(block_entry);
    try builder.ensureInsertedBlock();

    const ins = builder.ins();

    // Stack slot for struct timeval { tv_sec: i64, tv_usec: i64 } = 16 bytes
    const tv_slot = try builder.createSizedStackSlot(
        clif.StackSlotData.explicit(16, 3), // 16 bytes, 8-byte aligned
    );
    const tv_addr = try ins.stackAddr(clif.Type.I64, tv_slot, 0);

    // Call gettimeofday(&tv, NULL)
    const gtod_idx = func_index_map.get("gettimeofday") orelse 0;
    var gtod_sig = clif.Signature.init(.system_v);
    try gtod_sig.addParam(allocator, clif.AbiParam.init(clif.Type.I64)); // tv
    try gtod_sig.addParam(allocator, clif.AbiParam.init(clif.Type.I64)); // tz (NULL)
    try gtod_sig.addReturn(allocator, clif.AbiParam.init(clif.Type.I64));
    const sig_ref = try builder.importSignature(gtod_sig);
    const func_ref = try builder.importFunction(.{
        .name = .{ .user = .{ .namespace = 0, .index = gtod_idx } },
        .signature = sig_ref,
        .colocated = false,
    });
    const v_null = try ins.iconst(clif.Type.I64, 0);
    _ = try ins.call(func_ref, &[_]clif.Value{ tv_addr, v_null });

    // Load tv_sec and tv_usec from stack
    const tv_sec = try ins.stackLoad(clif.Type.I64, tv_slot, 0);
    const tv_usec = try ins.stackLoad(clif.Type.I64, tv_slot, 8);

    // Compute: tv_sec * 1_000_000_000 + tv_usec * 1_000
    const billion = try ins.iconst(clif.Type.I64, 1_000_000_000);
    const thousand = try ins.iconst(clif.Type.I64, 1_000);
    const sec_ns = try ins.imul(tv_sec, billion);
    const usec_ns = try ins.imul(tv_usec, thousand);
    const total = try ins.iadd(sec_ns, usec_ns);

    _ = try ins.return_(&[_]clif.Value{total});

    try builder.sealAllBlocks();
    builder.finalize();

    return native_compile.compile(allocator, &clif_func, isa, ctrl_plane);
}

// ============================================================================
// Generic forwarding: 2-param function → 2-param libc call
// Used for: random→getentropy
// ============================================================================

fn generateForward2(
    allocator: Allocator,
    isa: native_compile.TargetIsa,
    ctrl_plane: *native_compile.ControlPlane,
    func_index_map: *const std.StringHashMapUnmanaged(u32),
    libc_name: []const u8,
) !native_compile.CompiledCode {
    var clif_func = clif.Function.init(allocator);
    defer clif_func.deinit();

    var func_ctx = FunctionBuilderContext.init(allocator);
    defer func_ctx.deinit();
    var builder = FunctionBuilder.init(&clif_func, &func_ctx);

    // Signature: (i64, i64) → i64
    try clif_func.signature.addParam(allocator, clif.AbiParam.init(clif.Type.I64));
    try clif_func.signature.addParam(allocator, clif.AbiParam.init(clif.Type.I64));
    try clif_func.signature.addReturn(allocator, clif.AbiParam.init(clif.Type.I64));

    const block_entry = try builder.createBlock();
    builder.switchToBlock(block_entry);
    try builder.appendBlockParamsForFunctionParams(block_entry);
    try builder.ensureInsertedBlock();

    const ins = builder.ins();
    const params = builder.blockParams(block_entry);

    const libc_idx = func_index_map.get(libc_name) orelse 0;
    var libc_sig = clif.Signature.init(.system_v);
    try libc_sig.addParam(allocator, clif.AbiParam.init(clif.Type.I64));
    try libc_sig.addParam(allocator, clif.AbiParam.init(clif.Type.I64));
    try libc_sig.addReturn(allocator, clif.AbiParam.init(clif.Type.I64));
    const sig_ref = try builder.importSignature(libc_sig);
    const func_ref = try builder.importFunction(.{
        .name = .{ .user = .{ .namespace = 0, .index = libc_idx } },
        .signature = sig_ref,
        .colocated = false,
    });
    const call_result = try ins.call(func_ref, &[_]clif.Value{ params[0], params[1] });

    _ = try ins.return_(&[_]clif.Value{call_result.results[0]});

    try builder.sealAllBlocks();
    builder.finalize();

    return native_compile.compile(allocator, &clif_func, isa, ctrl_plane);
}
