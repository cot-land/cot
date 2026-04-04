// RUN: %cot emit-cir %s | %FileCheck %s

// libtc Phase 1: arithmetic operations

function arith(a: number, b: number): number {
    return a + b;
}

function sub(a: number, b: number): number {
    return a - b;
}

function mul(a: number, b: number): number {
    return a * b;
}

function div(a: number, b: number): number {
    return a / b;
}

function rem(a: number, b: number): number {
    return a % b;
}

// CHECK-LABEL: func.func @arith
// CHECK: cir.add

// CHECK-LABEL: func.func @sub
// CHECK: cir.sub

// CHECK-LABEL: func.func @mul
// CHECK: cir.mul

// CHECK-LABEL: func.func @div
// CHECK: cir.div

// CHECK-LABEL: func.func @rem
// CHECK: cir.rem
