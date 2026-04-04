// RUN: %cot emit-cir %s | %FileCheck %s

// libtc Phase 1: function declaration, arithmetic, return, call

function add(a: number, b: number): number {
    return a + b;
}

function main(): number {
    return add(19, 23);
}

// CHECK-LABEL: func.func @add
// CHECK: cir.add %{{.*}}, %{{.*}} : i32
// CHECK: return

// CHECK-LABEL: func.func @main
// CHECK: cir.constant 19
// CHECK: cir.constant 23
// CHECK: call @add
