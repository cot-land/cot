// RUN: %cot emit-cir %s | %FileCheck %s

pub fn sum_to_ten() i32 {
    var total: i32 = 0;
    var i: i32 = 1;
    while (i <= 10) {
        total += i;
        i += 1;
    }
    return total;
}

// CHECK-LABEL: func.func @sum_to_ten
// CHECK: cir.br
// CHECK: cir.cmp sle
// CHECK: cir.condbr
// CHECK: cir.add
// CHECK: cir.br
// CHECK: cir.load
// CHECK: return
