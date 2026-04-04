// RUN: %cot emit-cir %s | %FileCheck %s

// Feature #016: If expression (ternary) — TypeScript syntax

function max(a: number, b: number): number {
    return a > b ? a : b;
}

// CHECK-LABEL: func.func @max
// CHECK: cir.cmp sgt
// CHECK: cir.select
// CHECK: return
