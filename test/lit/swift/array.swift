// RUN: %cot emit-cir %s | %FileCheck %s

// libsc: array literal and element access

func getSecond() -> Int32 {
    let arr: [Int32] = [10, 20, 30]
    return arr[1]
}

// CHECK-LABEL: func.func @getSecond
// CHECK: cir.array_init
// CHECK-SAME: !cir.array<3 x i32>
// CHECK: cir.elem_val
// CHECK-SAME: !cir.array<3 x i32> to i32
