// RUN: %cot emit-cir %s | %FileCheck %s

// Feature #025: Struct construction — TypeScript syntax

interface Point {
    x: number;
    y: number;
}

function make_point(): number {
    let p: Point = { x: 19, y: 23 };
    return 0;
}

// CHECK-LABEL: func.func @make_point
// CHECK: cir.constant 19
// CHECK: cir.constant 23
// CHECK: cir.struct_init
// CHECK-SAME: !cir.struct<"Point", x: i32, y: i32>
