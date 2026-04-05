// RUN: %cot emit-cir %s | %FileCheck %s

// libsc: Swift-style type casts — Int32(x), Int64(x), Float(x)

func widen(x: Int32) -> Int64 {
    return Int64(x)
}

func narrow(x: Int64) -> Int32 {
    return Int32(x)
}

func intToFloat(x: Int32) -> Double {
    return Double(x)
}

// CHECK-LABEL: func.func @widen
// CHECK: cir.extsi %arg0 : i32 to i64

// CHECK-LABEL: func.func @narrow
// CHECK: cir.trunci %arg0 : i64 to i32

// CHECK-LABEL: func.func @intToFloat
// CHECK: cir.sitofp %arg0 : i32 to f64
