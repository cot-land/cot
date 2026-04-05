// RUN: %cot emit-cir %s | %FileCheck %s

// Feature #055: Generic function — Swift syntax
// Must be valid Swift — compilable by swiftc

func identity<T>(_ x: T) -> T {
    return x
}

func main() -> Int32 {
    return identity(42)
}

// Frontend monomorphizes: identity<Int32> → identity_Int32
// CHECK-LABEL: func.func @main
// CHECK: call @identity
// CHECK: return
