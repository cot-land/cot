// RUN: %cot emit-cir %s | %FileCheck %s

// Kitchen sink: all Zig features COT supports in one real-world example.
// This must be valid Zig — compilable by zig build-exe.

const Vec2 = struct {
    x: i32,
    y: i32,
};

const MathError = error{ Overflow, DivByZero };

pub fn vec2Add(a: Vec2, b: Vec2) Vec2 {
    return Vec2{ .x = a.x + b.x, .y = a.y + b.y };
}

pub fn dot(a: Vec2, b: Vec2) i32 {
    return a.x * b.x + a.y * b.y;
}

pub fn magnitude_squared(v: Vec2) i32 {
    return dot(v, v);
}

pub fn safeDivide(a: i32, b: i32) MathError!i32 {
    if (b == 0) return error.DivByZero;
    return @divTrunc(a, b);
}

pub fn clamp(val: i32, lo: i32, hi: i32) i32 {
    if (val < lo) return lo;
    if (val > hi) return hi;
    return val;
}

pub fn sumArray(arr: [4]i32) i32 {
    var total: i32 = 0;
    var i: i32 = 0;
    while (i < 4) {
        total = total + arr[@intCast(i)];
        i += 1;
    }
    return total;
}

pub fn firstOrNull(opt: ?i32) i32 {
    if (opt) |val| {
        return val;
    }
    return 0;
}

pub fn greetLen(s: []const u8) i64 {
    return s.len;
}

// CHECK-LABEL: func.func @vec2Add
// CHECK: cir.field_val
// CHECK: cir.add
// CHECK: cir.struct_init

// CHECK-LABEL: func.func @dot
// CHECK: cir.mul
// CHECK: cir.add

// CHECK-LABEL: func.func @magnitude_squared
// CHECK: call @dot

// CHECK-LABEL: func.func @safeDivide
// CHECK: cir.cmp eq
// CHECK: cir.wrap_error
// CHECK: cir.div
// CHECK: cir.wrap_result

// CHECK-LABEL: func.func @clamp
// CHECK: cir.cmp slt
// CHECK: cir.cmp sgt

// CHECK-LABEL: func.func @sumArray
// CHECK: cir.alloca
// CHECK: cir.cmp slt
// CHECK: cir.condbr
// CHECK: cir.add

// CHECK-LABEL: func.func @firstOrNull
// CHECK: cir.is_non_null
// CHECK: cir.optional_payload

// CHECK-LABEL: func.func @greetLen
// CHECK: cir.slice_len
