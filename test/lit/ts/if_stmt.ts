// RUN: %cot emit-cir %s | %FileCheck %s

// Phase 2: if/else statement

function abs(x: number): number {
    if (x > 0) {
        return x;
    } else {
        return -x;
    }
}

// CHECK-LABEL: func.func @abs
// CHECK: cir.cmp sgt
// CHECK: cir.condbr
// CHECK: return
// CHECK: cir.neg
// CHECK: return
