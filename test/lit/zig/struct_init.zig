// RUN: %cot emit-cir %s | %FileCheck %s

// Feature #025: Struct construction — Zig syntax

const Point = struct { x: i32, y: i32 };

pub fn make_point() i32 {
    const p = Point{ .x = 19, .y = 23 };
    return 0;
}

// CHECK-LABEL: func.func @make_point
// CHECK: cir.constant 19
// CHECK: cir.constant 23
// CHECK: cir.struct_init
// CHECK-SAME: !cir.struct<"Point", x: i32, y: i32>
