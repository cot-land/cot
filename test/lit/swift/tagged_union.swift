// RUN: %cot emit-cir %s | %FileCheck %s

// libsc: enums with associated values — Swift tagged unions
// enum Shape { case circle(Int32); case none } maps to !cir.tagged_union

enum Shape {
    case circle(Int32)
    case none
}

func makeCircle(_ r: Int32) -> Shape {
    return .circle(r)
}

// CHECK-LABEL: func.func @makeCircle
// CHECK-SAME: ({{%.*}}: i32) -> !cir.tagged_union<"Shape"
// CHECK: cir.union_init "circle"
// CHECK-SAME: i32
// CHECK: return
