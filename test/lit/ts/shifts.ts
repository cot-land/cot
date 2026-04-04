// RUN: %cot emit-cir %s | %FileCheck %s

// Phase 1: shift operators

function shl(a: number, b: number): number {
    return a << b;
}

function shr(a: number, b: number): number {
    return a >> b;
}

// CHECK-LABEL: func.func @shl
// CHECK: cir.shl

// CHECK-LABEL: func.func @shr
// CHECK: cir.shr
