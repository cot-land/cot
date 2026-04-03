//! libzc — Zig frontend for COT.
//!
//! Parses Zig source using std.zig.Ast, produces CIR MLIR bytecode.
//! Two consumption modes:
//!   1. C ABI: cot links libzc.a, calls zc_parse() directly
//!   2. Bytecode: zc CLI writes .cir file, cot reads it

const std = @import("std");
pub const astgen = @import("astgen.zig");
pub const mlir = @import("mlir.zig");

/// Parse Zig source → CIR MLIR bytecode.
/// Returns 0 on success, -1 on error.
export fn zc_parse(
    source_ptr: [*]const u8,
    source_len: usize,
    filename: [*:0]const u8,
    out_ptr: *[*]const u8,
    out_len: *usize,
) callconv(.c) i32 {
    _ = filename;
    const gpa = std.heap.page_allocator;

    // Create sentinel-terminated source for Zig parser
    const source_z = gpa.allocSentinel(u8, source_len, 0) catch return -1;
    defer gpa.free(source_z[0 .. source_len + 1]);
    @memcpy(source_z[0..source_len], source_ptr[0..source_len]);

    // Parse with Zig's standard library parser
    var tree = std.zig.Ast.parse(gpa, source_z, .zig) catch return -1;
    defer tree.deinit(gpa);
    if (tree.errors.len > 0) return -1;

    // AstGen: AST → CIR MLIR module
    var result = astgen.generate(gpa, &tree) catch return -1;

    // Serialize to bytecode
    const bytes = result.toBytecode(gpa) catch return -1;
    out_ptr.* = bytes.ptr;
    out_len.* = bytes.len;
    return 0;
}

test "libzc compiles" {
    _ = astgen;
    _ = mlir;
}
