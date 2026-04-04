// RUN: %cot emit-cir %s | %FileCheck %s

// Phase 1: unary minus

function neg(x: number): number {
    return -x;
}

// CHECK-LABEL: func.func @neg
// CHECK: cir.neg %{{.*}} : i32
// CHECK: return
