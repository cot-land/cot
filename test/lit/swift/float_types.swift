// RUN: %cot emit-cir %s | %FileCheck %s

// libsc: Float (f32) and Double (f64) literals and arithmetic

func addFloat(a: Float, b: Float) -> Float {
    return a + b
}

func addDouble(a: Double, b: Double) -> Double {
    return a + b
}

// CHECK-LABEL: func.func @addFloat
// CHECK: cir.add %arg0, %arg1 : f32

// CHECK-LABEL: func.func @addDouble
// CHECK: cir.add %arg0, %arg1 : f64
