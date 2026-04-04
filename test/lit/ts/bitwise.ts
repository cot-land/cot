// RUN: %cot emit-cir %s | %FileCheck %s

// Phase 1: bitwise operators

function band(a: number, b: number): number {
    return a & b;
}

function bor(a: number, b: number): number {
    return a | b;
}

function bxor(a: number, b: number): number {
    return a ^ b;
}

function bnot(x: number): number {
    return ~x;
}

// CHECK-LABEL: func.func @band
// CHECK: cir.bit_and

// CHECK-LABEL: func.func @bor
// CHECK: cir.bit_or

// CHECK-LABEL: func.func @bxor
// CHECK: cir.xor

// CHECK-LABEL: func.func @bnot
// CHECK: cir.bit_not
