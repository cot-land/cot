// RUN: %cot emit-cir %s | %FileCheck %s

// libsc: arithmetic operations +, -, *, /, %

func allOps(a: Int32, b: Int32) -> Int32 {
    let sum: Int32 = a + b
    let diff: Int32 = a - b
    let prod: Int32 = sum * diff
    let quot: Int32 = prod / b
    let rem: Int32 = quot % b
    return rem
}

// CHECK-LABEL: func.func @allOps
// CHECK: cir.add %arg0, %arg1 : i32
// CHECK: cir.sub %arg0, %arg1 : i32
// CHECK: cir.mul
// CHECK: cir.div
// CHECK: cir.rem
// CHECK: return
