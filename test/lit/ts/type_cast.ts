// RUN: %cot emit-cir %s | %FileCheck %s

// libtc: type assertion — x as number (identity cast, no-op)

function castToNumber(x: number): number {
    return x as number;
}

// CHECK-LABEL: func.func @castToNumber
// CHECK-SAME: ({{%.*}}: i32) -> i32
// CHECK: return {{%.*}} : i32
