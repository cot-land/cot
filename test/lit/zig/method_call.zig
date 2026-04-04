// RUN: %cot emit-cir %s | %FileCheck %s

// Feature #027: Struct method syntax — Zig

const Point = struct { x: i32, y: i32 };

pub fn sum(p: Point) i32 {
    return p.x + p.y;
}

pub fn main() i32 {
    const p: Point = Point{ .x = 19, .y = 23 };
    return p.sum();
}

// CHECK-LABEL: func.func @main
// CHECK: call @sum
// CHECK-SAME: !cir.struct<"Point", x: i32, y: i32>
