// RUN: %cot emit-cir %s | %FileCheck %s

// Feature #026: Struct field access — Zig syntax

const Point = struct { x: i32, y: i32 };

pub fn get_x(p: Point) i32 {
    return p.x;
}

pub fn get_y(p: Point) i32 {
    return p.y;
}

// CHECK-LABEL: func.func @get_x
// CHECK: cir.field_val %arg0, 0 : !cir.struct<"Point", x: i32, y: i32> -> i32

// CHECK-LABEL: func.func @get_y
// CHECK: cir.field_val %arg0, 1 : !cir.struct<"Point", x: i32, y: i32> -> i32
