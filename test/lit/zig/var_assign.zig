// RUN: %cot emit-cir %s | %FileCheck %s

pub fn counter() i32 {
    var x: i32 = 0;
    x = 42;
    return x;
}

// CHECK-LABEL: func.func @counter
// CHECK: cir.alloca i32 : !cir.ptr
// CHECK: cir.store
// CHECK: cir.store
// CHECK: cir.load
