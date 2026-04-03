// RUN: %cot emit-cir %s | %FileCheck %s

pub fn double(x: i32) i32 {
    return x + x;
}

pub fn quadruple(x: i32) i32 {
    return double(double(x));
}

pub fn main() i32 {
    return quadruple(10) + double(1);
}

// CHECK-LABEL: func.func @double
// CHECK: cir.add

// CHECK-LABEL: func.func @quadruple
// CHECK: call @double
// CHECK: call @double

// CHECK-LABEL: func.func @main
// CHECK: call @quadruple
// CHECK: call @double
// CHECK: cir.add
