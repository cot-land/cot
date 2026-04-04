// RUN: %cot emit-cir %s | %FileCheck %s

// Feature #007: Comparison — Zig syntax

pub fn isEqual(a: i32, b: i32) i32 {
    if (a == b) return 1;
    return 0;
}

pub fn isLess(a: i32, b: i32) i32 {
    if (a < b) return 1;
    return 0;
}

// CHECK-LABEL: func.func @isEqual
// CHECK: cir.cmp eq
// CHECK: cir.condbr

// CHECK-LABEL: func.func @isLess
// CHECK: cir.cmp slt
// CHECK: cir.condbr
