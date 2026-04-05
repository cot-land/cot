// RUN: %cot emit-cir %s | %FileCheck %s

// libsc: nested function calls

func double(x: Int32) -> Int32 {
    return x + x
}

func quadruple(x: Int32) -> Int32 {
    return double(double(x))
}

func main() -> Int32 {
    return quadruple(10) + double(1)
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
