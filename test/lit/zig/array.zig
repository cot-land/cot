// RUN: %cot emit-cir %s | %FileCheck %s

// Feature #028-030: Array literal and indexing — Zig syntax

pub fn get_second() i32 {
    const arr: [3]i32 = .{ 10, 20, 30 };
    return arr[1];
}

// CHECK-LABEL: func.func @get_second
// CHECK: cir.array_init
// CHECK-SAME: !cir.array<3 x i32>
// CHECK: cir.elem_val
// CHECK-SAME: !cir.array<3 x i32> -> i32
