// RUN: %cot emit-cir %s | %FileCheck %s

// Phase 2: compound assignment operator

function accumulate(): number {
    let x: number = 10;
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
