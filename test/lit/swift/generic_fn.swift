// RUN: %cot emit-cir %s | %FileCheck %s

// Feature #055: Generic function — Swift syntax
// Must be valid Swift — compilable by swiftc
// Swift generics → CIR type_param + generic_apply

func identity<T>(_ x: T) -> T {
    return x
}

func main() -> Int32 {
    return identity(42)
}

// After specialization: main calls identity_i32
// CHECK-LABEL: func.func @main
// CHECK: call @identity
// CHECK: return
