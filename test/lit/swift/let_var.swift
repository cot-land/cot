// RUN: %cot emit-cir %s | %FileCheck %s

// libsc: let/var bindings, alloca/store/load

func compute(x: Int32) -> Int32 {
    let a: Int32 = x + 1
    var b: Int32 = a * 2
    b += 10
    return b
}

// CHECK-LABEL: func.func @compute
// CHECK: cir.alloca i32
// CHECK: cir.add
// CHECK: cir.store
// CHECK: cir.alloca i32
// CHECK: cir.mul
// CHECK: cir.store
// CHECK: cir.load
// CHECK: cir.add
// CHECK: cir.store
// CHECK: cir.load
// CHECK: return
