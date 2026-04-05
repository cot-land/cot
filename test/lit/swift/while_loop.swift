// RUN: %cot emit-cir %s | %FileCheck %s

// libsc: while loop with compound assignment

func sumTo(n: Int32) -> Int32 {
    var sum: Int32 = 0
    var i: Int32 = 1
    while i <= n {
        sum += i
        i += 1
    }
    return sum
}

// CHECK-LABEL: func.func @sumTo
// CHECK: cir.alloca
// CHECK: cir.alloca
// CHECK: cir.br
// CHECK: cir.cmp sle
// CHECK: cir.condbr
// CHECK: cir.load
// CHECK: cir.add
// CHECK: cir.store
// CHECK: cir.br
// CHECK: cir.load
// CHECK: return
