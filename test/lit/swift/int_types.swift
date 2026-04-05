// RUN: %cot emit-cir %s | %FileCheck %s

// libsc: integer type widths — Int8, Int16, Int32, Int64

func narrow(x: Int8, y: Int8) -> Int8 {
    return x + y
}

func medium(x: Int16, y: Int16) -> Int16 {
    return x + y
}

func wide(x: Int64, y: Int64) -> Int64 {
    return x + y
}

// CHECK-LABEL: func.func @narrow
// CHECK: cir.add %arg0, %arg1 : i8

// CHECK-LABEL: func.func @medium
// CHECK: cir.add %arg0, %arg1 : i16

// CHECK-LABEL: func.func @wide
// CHECK: cir.add %arg0, %arg1 : i64
