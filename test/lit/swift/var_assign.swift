// RUN: %cot emit-cir %s | %FileCheck %s

// libsc: var declaration and reassignment

func counter() -> Int32 {
    var x: Int32 = 10
    x = 20
    return x
}

// CHECK-LABEL: func.func @counter
// CHECK: cir.alloca i32 : !cir.ptr
// CHECK: cir.constant 10
// CHECK: cir.store
// CHECK: cir.constant 20
// CHECK: cir.store
// CHECK: cir.load
// CHECK: return
