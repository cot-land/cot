// RUN: %cot emit-cir %s | %FileCheck %s

// Feature #024: Struct declaration (interface) — TypeScript syntax
// Tests interface-as-type in function signatures (separate from struct_init)

interface Point {
    x: number;
    y: number;
}

interface Rect {
    left: number;
    top: number;
    width: number;
    height: number;
}

function takes_point(p: Point): number {
    return 0;
}

function takes_rect(r: Rect): number {
    return 0;
}

// CHECK-LABEL: func.func @takes_point
// CHECK-SAME: !cir.struct<"Point", x: i32, y: i32>

// CHECK-LABEL: func.func @takes_rect
// CHECK-SAME: !cir.struct<"Rect", left: i32, top: i32, width: i32, height: i32>
