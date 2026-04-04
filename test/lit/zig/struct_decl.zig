// RUN: %cot emit-cir %s | %FileCheck %s

// Feature #024: Struct declaration — Zig syntax

const Point = struct { x: i32, y: i32 };

const Color = struct { r: i8, g: i8, b: i8 };

pub fn takes_point(p: Point) i32 {
    return 0;
}

pub fn takes_color(c: Color) i32 {
    return 0;
}

// CHECK-LABEL: func.func @takes_point
// CHECK-SAME: !cir.struct<"Point", x: i32, y: i32>

// CHECK-LABEL: func.func @takes_color
// CHECK-SAME: !cir.struct<"Color", r: i8, g: i8, b: i8>
