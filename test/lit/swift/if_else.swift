// RUN: %cot emit-cir %s | %FileCheck %s

// libsc: if/else control flow

func max(a: Int32, b: Int32) -> Int32 {
    if a > b {
        return a
    } else {
        return b
    }
}

// CHECK-LABEL: func.func @max
// CHECK: cir.cmp sgt
// CHECK: cir.condbr
// CHECK: return
// CHECK: return
