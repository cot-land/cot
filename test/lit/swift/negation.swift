// RUN: %cot emit-cir %s | %FileCheck %s

// libsc: unary minus (negation)

func negate(x: Int32) -> Int32 {
    return -x
}

func negateLong(x: Int64) -> Int64 {
    return -x
}

// CHECK-LABEL: func.func @negate
// CHECK: cir.neg %arg0 : i32
// CHECK: return

// CHECK-LABEL: func.func @negateLong
// CHECK: cir.neg %arg0 : i64
// CHECK: return
