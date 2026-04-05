// RUN: %cot emit-cir %s | %FileCheck %s

// libsc: struct method call (p.sum() dispatches as call @sum(p))

struct Point {
    let x: Int32
    let y: Int32
}

func sum(p: Point) -> Int32 {
    return p.x + p.y
}

func main() -> Int32 {
    let p: Point = Point(x: 19, y: 23)
    return p.sum()
}

// CHECK-LABEL: func.func @main
// CHECK: cir.struct_init
// CHECK: call @sum
// CHECK-SAME: !cir.struct<"Point", x: i32, y: i32>
