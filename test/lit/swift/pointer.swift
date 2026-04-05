// RUN: %cot emit-cir %s | %FileCheck %s

// Feature #031-033: Pointer types, address-of, dereference — Swift syntax
// UnsafePointer<T> / UnsafeMutablePointer<T> → !cir.ref<T>

func readPtr(_ p: UnsafePointer<Int32>) -> Int32 {
    return p.pointee
}

// CHECK-LABEL: func.func @readPtr
// CHECK-SAME: !cir.ref<i32>
// CHECK: cir.deref %arg0 : !cir.ref<i32> to i32
