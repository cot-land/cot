// RUN: %cot emit-cir %s | %FileCheck %s

// libsc: bitwise operations

func bitOps(x: Int32, y: Int32) -> Int32 {
    return (x & y) | (x ^ y)
}

// CHECK-LABEL: func.func @bitOps
// CHECK: cir.bit_and
// CHECK: cir.bit_xor
// CHECK: cir.bit_or
// CHECK: return
