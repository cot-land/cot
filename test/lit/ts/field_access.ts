// RUN: %cot emit-cir %s | %FileCheck %s

// Feature #026: Struct field access — TypeScript syntax

interface Point {
    x: number;
    y: number;
}

function get_x(p: Point): number {
    return p.x;
}

function get_y(p: Point): number {
    return p.y;
}

// CHECK-LABEL: func.func @get_x
// CHECK: cir.field_val %arg0, 0 : !cir.struct<"Point", x: i32, y: i32> -> i32

// CHECK-LABEL: func.func @get_y
// CHECK: cir.field_val %arg0, 1 : !cir.struct<"Point", x: i32, y: i32> -> i32
