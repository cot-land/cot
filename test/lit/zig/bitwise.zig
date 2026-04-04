// RUN: %cot emit-cir %s | %FileCheck %s

pub fn bitand(a: i32, b: i32) i32 {
    return a & b;
}

pub fn bitor(a: i32, b: i32) i32 {
    return a | b;
}

pub fn bitxor(a: i32, b: i32) i32 {
    return a ^ b;
}

pub fn bitnot(x: i32) i32 {
    return ~x;
}

pub fn shifts(a: i32, b: i32) i32 {
    return (a << b) >> b;
}

// CHECK-LABEL: func.func @bitand
// CHECK: cir.bit_and

// CHECK-LABEL: func.func @bitor
// CHECK: cir.bit_or

// CHECK-LABEL: func.func @bitxor
// CHECK: cir.bit_xor

// CHECK-LABEL: func.func @bitnot
// CHECK: cir.bit_not

// CHECK-LABEL: func.func @shifts
// CHECK: cir.shl
// CHECK: cir.shr
