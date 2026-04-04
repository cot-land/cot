// RUN: %cot emit-cir %s | %FileCheck %s

// Phase 1: comparison operators

function eq(a: number, b: number): boolean {
    return a === b;
}

function ne(a: number, b: number): boolean {
    return a !== b;
}

function lt(a: number, b: number): boolean {
    return a < b;
}

function le(a: number, b: number): boolean {
    return a <= b;
}

function gt(a: number, b: number): boolean {
    return a > b;
}

function ge(a: number, b: number): boolean {
    return a >= b;
}

// CHECK-LABEL: func.func @eq
// CHECK: cir.cmp eq

// CHECK-LABEL: func.func @ne
// CHECK: cir.cmp ne

// CHECK-LABEL: func.func @lt
// CHECK: cir.cmp slt

// CHECK-LABEL: func.func @le
// CHECK: cir.cmp sle

// CHECK-LABEL: func.func @gt
// CHECK: cir.cmp sgt

// CHECK-LABEL: func.func @ge
// CHECK: cir.cmp sge
