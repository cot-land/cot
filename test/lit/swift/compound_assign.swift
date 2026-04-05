// RUN: %cot emit-cir %s | %FileCheck %s

// libsc: compound assignment operators +=, -=, *=

func accumulate() -> Int32 {
    var x: Int32 = 10
    x += 32
    x -= 2
    x *= 3
    return x
}

// CHECK-LABEL: func.func @accumulate
// CHECK: cir.alloca i32 : !cir.ptr
// CHECK: cir.store
// CHECK: cir.load
// CHECK: cir.add
// CHECK: cir.store
// CHECK: cir.load
// CHECK: cir.sub
// CHECK: cir.store
// CHECK: cir.load
// CHECK: cir.mul
// CHECK: cir.store
// CHECK: cir.load
// CHECK: return
