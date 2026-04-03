// RUN: %cot emit-cir %s | %FileCheck %s

pub fn add_f32(a: f32, b: f32) f32 {
    return a + b;
}

pub fn add_f64(a: f64, b: f64) f64 {
    return a + b;
}

// CHECK-LABEL: func.func @add_f32
// CHECK: cir.add %{{.*}}, %{{.*}} : f32

// CHECK-LABEL: func.func @add_f64
// CHECK: cir.add %{{.*}}, %{{.*}} : f64
