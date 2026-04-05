// RUN: %cot emit-cir %s | %FileCheck %s

// libsc: shift operators << and >>

func shiftLeft(x: Int32, n: Int32) -> Int32 {
    return x << n
}

func shiftRight(x: Int32, n: Int32) -> Int32 {
    return x >> n
}

// CHECK-LABEL: func.func @shiftLeft
// CHECK: cir.shl %arg0, %arg1 : i32
// CHECK: return

// CHECK-LABEL: func.func @shiftRight
// CHECK: cir.shr %arg0, %arg1 : i32
// CHECK: return
