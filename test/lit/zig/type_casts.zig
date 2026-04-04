// RUN: %cot emit-cir %s | %FileCheck %s

// Feature #023: Explicit type casts — Zig @intCast/@floatCast builtins

pub fn widen(x: i32) i64 {
    const y: i64 = @intCast(x);
    return y;
}

pub fn narrow(x: i64) i32 {
    const y: i32 = @truncate(x);
    return y;
}

pub fn intToFloat(x: i32) f64 {
    const y: f64 = @floatFromInt(x);
    return y;
}

pub fn floatNarrow(x: f64) f32 {
    const y: f32 = @floatCast(x);
    return y;
}

pub fn floatWiden(x: f32) f64 {
    const y: f64 = @floatCast(x);
    return y;
}

// CHECK-LABEL: func.func @widen
// CHECK: cir.extsi %{{.*}} : i32 to i64

// CHECK-LABEL: func.func @narrow
// CHECK: cir.trunci %{{.*}} : i64 to i32

// CHECK-LABEL: func.func @intToFloat
// CHECK: cir.sitofp %{{.*}} : i32 to f64

// CHECK-LABEL: func.func @floatNarrow
// CHECK: cir.truncf %{{.*}} : f64 to f32

// CHECK-LABEL: func.func @floatWiden
// CHECK: cir.extf %{{.*}} : f32 to f64
