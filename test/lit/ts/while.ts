// RUN: %cot emit-cir %s | %FileCheck %s

// Phase 2: while loop

function sum_to_ten(): number {
    let total: number = 0;
    let i: number = 1;
    while (i <= 10) {
        total += i;
        i += 1;
    }
    return total;
}

// CHECK-LABEL: func.func @sum_to_ten
// CHECK: cir.alloca i32 : !cir.ptr
// CHECK: cir.alloca i32 : !cir.ptr
// CHECK: cir.br
// CHECK: cir.cmp sle
// CHECK: cir.condbr
// CHECK: cir.add
// CHECK: cir.store
// CHECK: cir.br
// CHECK: cir.load
// CHECK: return
