// RUN: %cot emit-cir %s | %FileCheck %s

// Feature #027: Struct method syntax — TypeScript

interface Point {
    x: number;
    y: number;
}

function sum(p: Point): number {
    return p.x + p.y;
}

function main(): number {
    let p: Point = { x: 19, y: 23 };
    return p.sum();
}

// CHECK-LABEL: func.func @main
// CHECK: call @sum
// CHECK-SAME: !cir.struct<"Point", x: i32, y: i32>
