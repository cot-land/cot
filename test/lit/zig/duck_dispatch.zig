// RUN: %cot emit-cir %s | %FileCheck %s

// Feature: cir.method_call — Zig comptime duck typing via CIR
// Zig's anytype method dispatch emits cir.method_call (structural dispatch).
// Reference: Zig ZIR field_call → Sema fieldCallBind()

const Point = struct {
    x: i32,
    y: i32,
};

fn sum(self: Point) i32 {
    return self.x + self.y;
}

fn apply(comptime T: type, val: T) i32 {
    return val.sum();
}

fn main() i32 {
    return 42;
}

// Generic function emits cir.method_call (Zig field_call pattern)
// CHECK: func.func @apply
// CHECK: cir.method_call "sum"
// CHECK: return
