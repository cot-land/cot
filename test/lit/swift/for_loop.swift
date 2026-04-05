// RUN: %cot emit-cir %s | %FileCheck %s

// libsc: for-in loop with half-open range

func sumRange() -> Int32 {
    var total: Int32 = 0
    for i in 0..<10 {
        total += i
    }
    return total
}

// CHECK-LABEL: func.func @sumRange
// CHECK: cir.alloca i32 : !cir.ptr
// CHECK: cir.alloca i32 : !cir.ptr
// CHECK: cir.br
// CHECK: cir.cmp slt
// CHECK: cir.condbr
// CHECK: cir.add
// CHECK: cir.store
// CHECK: cir.br
// CHECK: cir.load
// CHECK: return
