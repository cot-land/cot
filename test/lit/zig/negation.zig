// RUN: %cot emit-cir %s | %FileCheck %s

// Feature #008: Negation — Zig syntax

pub fn negate(x: i32) i32 {
    return 0 - x;
}

// CHECK-LABEL: func.func @negate
// CHECK: cir.sub
