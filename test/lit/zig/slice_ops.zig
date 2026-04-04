// RUN: %cot emit-cir %s | %FileCheck %s

// Features #037-040: Slice operations — Zig syntax

pub fn getLen() i64 {
    const s: []const u8 = "hello";
    return s.len;
}

// CHECK-LABEL: func.func @getLen
// CHECK: cir.string_constant "hello" : !cir.slice<i8>
// CHECK: cir.slice_len
// CHECK-SAME: !cir.slice<i8> to i64
// CHECK: return
