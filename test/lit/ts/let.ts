// RUN: %cot emit-cir %s | %FileCheck %s

// Phase 2: local variable declaration with let

function compute(): number {
    let x: number = 10;
    let y: number = 32;
    return x + y;
}

// CHECK-LABEL: func.func @compute
// CHECK: %[[XADDR:.*]] = cir.alloca i32 : !cir.ptr
// CHECK: cir.store %{{.*}}, %[[XADDR]] : i32, !cir.ptr
// CHECK: %[[YADDR:.*]] = cir.alloca i32 : !cir.ptr
// CHECK: cir.store %{{.*}}, %[[YADDR]] : i32, !cir.ptr
// CHECK: %[[X:.*]] = cir.load %[[XADDR]] : !cir.ptr to i32
// CHECK: %[[Y:.*]] = cir.load %[[YADDR]] : !cir.ptr to i32
// CHECK: cir.add %[[X]], %[[Y]] : i32
