// RUN: %cot emit-cir %s | %FileCheck %s

// Feature #055: Generic function — Zig syntax
// Must be valid Zig — compilable by zig build-exe
// Zig comptime generics monomorphize at compile time

pub fn max(comptime T: type, a: T, b: T) T {
    if (a > b) return a;
    return b;
}

pub fn main() i32 {
    return max(i32, 3, 7);
}

// Frontend monomorphizes: max(i32, ...) → max_i32
// CHECK-LABEL: func.func @main
// CHECK: call @max
// CHECK: return
