// RUN: %cot emit-cir %s | %FileCheck %s

// libsc: enum declarations, enum constants, enum comparison

enum Color: Int32 {
    case red = 0
    case green = 1
    case blue = 2
}

func isRed(c: Color) -> Bool {
    return c == Color.red
}

// CHECK-LABEL: func.func @isRed
// CHECK: cir.enum_constant "red"
// CHECK: cir.enum_value
// CHECK: cir.enum_value
// CHECK: cir.cmp eq
// CHECK: return
