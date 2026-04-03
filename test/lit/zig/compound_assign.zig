// RUN: %cot emit-cir %s | %FileCheck %s

pub fn accumulate() i32 {
    var x: i32 = 10;
    x += 32;
    return x;
}

// CHECK-LABEL: func.func @accumulate
// CHECK: cir.alloca i32 : !cir.ptr
// CHECK: cir.store
// CHECK: cir.load
// CHECK: cir.add
// CHECK: cir.store
// CHECK: cir.load
