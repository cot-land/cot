// RUN: %cot emit-cir %s | %FileCheck %s
//
// Zig has no integer range for loop (for iterates slices).
// Idiomatic equivalent: while with counter.

pub fn sum_range() i32 {
    var total: i32 = 0;
    var i: i32 = 0;
    while (i < 10) {
        total += i;
        i += 1;
    }
    return total;
}

// CHECK-LABEL: func.func @sum_range
// CHECK: cir.alloca i32 : !cir.ptr
// CHECK: cir.alloca i32 : !cir.ptr
// CHECK: cir.br
// CHECK: cir.cmp slt
// CHECK: cir.condbr
// CHECK: cir.add
// CHECK: cir.br
