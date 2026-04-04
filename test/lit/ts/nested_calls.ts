// RUN: %cot emit-cir %s | %FileCheck %s

// Phase 1: functions calling functions

function double(x: number): number {
    return x + x;
}

function quadruple(x: number): number {
    return double(double(x));
}

function main(): number {
    return quadruple(10) + double(1);
}

// CHECK-LABEL: func.func @double
// CHECK: cir.add

// CHECK-LABEL: func.func @quadruple
// CHECK: call @double
// CHECK: call @double

// CHECK-LABEL: func.func @main
// CHECK: call @quadruple
// CHECK: call @double
// CHECK: cir.add
