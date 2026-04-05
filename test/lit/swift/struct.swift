// RUN: %cot emit-cir %s | %FileCheck %s

// libsc: struct declarations, construction, field access

struct Point {
    let x: Int32
    let y: Int32
}

func makePoint(x: Int32, y: Int32) -> Point {
    return Point(x: x, y: y)
}

func getX(p: Point) -> Int32 {
    return p.x
}

// CHECK-LABEL: func.func @makePoint
// CHECK: cir.struct_init
// CHECK-SAME: !cir.struct<"Point"
// CHECK: return

// CHECK-LABEL: func.func @getX
// CHECK: cir.field_val
// CHECK: return
