// RUN: %cot emit-cir %s | %FileCheck %s

// libsc: struct field access

struct Point {
    let x: Int32
    let y: Int32
}

func getX(p: Point) -> Int32 {
    return p.x
}

func getY(p: Point) -> Int32 {
    return p.y
}

// CHECK-LABEL: func.func @getX
// CHECK: cir.field_val %arg0, 0 : !cir.struct<"Point", x: i32, y: i32> to i32

// CHECK-LABEL: func.func @getY
// CHECK: cir.field_val %arg0, 1 : !cir.struct<"Point", x: i32, y: i32> to i32
