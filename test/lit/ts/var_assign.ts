// RUN: %cot emit-cir %s | %FileCheck %s

// Phase 2: variable assignment

function counter(): number {
    let x: number = 0;
    x = 42;
    return x;
}

// CHECK-LABEL: func.func @counter
// CHECK: %[[ADDR:.*]] = cir.alloca i32 : !cir.ptr
// CHECK: cir.store %{{.*}}, %[[ADDR]] : i32, !cir.ptr
// CHECK: cir.store %{{.*}}, %[[ADDR]] : i32, !cir.ptr
// CHECK: cir.load %[[ADDR]] : !cir.ptr to i32
