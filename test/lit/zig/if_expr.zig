// RUN: %cot emit-cir %s | %FileCheck %s

pub fn clamp_low(x: i32) i32 {
    const result = if (x > 0) x else 0;
    return result;
}

// CHECK-LABEL: func.func @clamp_low
// CHECK: cir.cmp sgt
// CHECK: cir.select
