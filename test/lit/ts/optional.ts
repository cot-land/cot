// RUN: %cot emit-cir %s | %FileCheck %s

// libtc: optional type — number | null → !cir.optional<i32>

function getOrNull(x: number): number | null {
    if (x > 0) { return x; }
    return null;
}

// CHECK-LABEL: func.func @getOrNull
// CHECK-SAME: ({{%.*}}: i32) -> !cir.optional<i32>
// CHECK: cir.wrap_optional
// CHECK-SAME: i32 to !cir.optional<i32>
// CHECK: cir.none : !cir.optional<i32>
// CHECK: return
