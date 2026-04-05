// RUN: %cot emit-cir %s | %FileCheck %s

// libsc: comparison operators

func isLess(a: Int32, b: Int32) -> Bool {
    return a < b
}

func isEqual(a: Int32, b: Int32) -> Bool {
    return a == b
}

func isGreater(a: Int32, b: Int32) -> Bool {
    return a > b
}

// CHECK-LABEL: func.func @isLess
// CHECK: cir.cmp slt, %{{.*}}, %{{.*}} : i32

// CHECK-LABEL: func.func @isEqual
// CHECK: cir.cmp eq, %{{.*}}, %{{.*}} : i32

// CHECK-LABEL: func.func @isGreater
// CHECK: cir.cmp sgt, %{{.*}}, %{{.*}} : i32
