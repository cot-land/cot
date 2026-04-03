// RUN: %cot emit-cir %s | %FileCheck %s

pub fn clamp(x: i32) i32 {
    var result: i32 = x;
    if (x > 100) {
        result = 100;
    }
    return result;
}

// CHECK-LABEL: func.func @clamp
// CHECK: cir.alloca i32 : !cir.ptr
// CHECK: cir.cmp sgt
// CHECK: cir.condbr
// CHECK: cir.store
// CHECK: cir.br
// CHECK: cir.load
// CHECK: return
