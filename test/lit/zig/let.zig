// RUN: %cot emit-cir %s | %FileCheck %s

pub fn compute() i32 {
    const x: i32 = 10;
    const y: i32 = 32;
    return x + y;
}

// CHECK-LABEL: func.func @compute
// CHECK: cir.alloca i32 : !cir.ptr
// CHECK: cir.store
// CHECK: cir.alloca i32 : !cir.ptr
// CHECK: cir.store
// CHECK: cir.load
// CHECK: cir.load
// CHECK: cir.add
