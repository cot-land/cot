// RUN: %cot emit-cir %s | %FileCheck %s

// Features #053-054: Tagged union — Zig syntax
// Must be valid Zig — compilable by zig build-exe

const Shape = union(enum) {
    circle: i32,
    rect: i32,
    none,
};

pub fn makeCircle(r: i32) Shape {
    return Shape{ .circle = r };
}

// CHECK-LABEL: func.func @makeCircle
// CHECK: cir.union_init "circle"
// CHECK-SAME: !cir.tagged_union<"Shape"
// CHECK: return
