// RUN: %cot emit-cir %s | %FileCheck %s

// Feature #019: For loop — TypeScript syntax

function sumTo(n: number): number {
    let result: number = 0;
    for (let i: number = 0; i < n; i = i + 1) {
        result = result + i;
    }
    return result;
}

// CHECK-LABEL: func.func @sumTo
// CHECK: cir.alloca
// CHECK: cir.cmp slt
// CHECK: cir.condbr
// CHECK: cir.add
// CHECK: return
