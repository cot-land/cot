// RUN: %cot emit-cir %s | %FileCheck %s

// Features #041-044: Optional type — Zig syntax

pub fn getNull() ?i32 {
    return null;
}

// CHECK-LABEL: func.func @getNull
// CHECK: cir.none : !cir.optional<i32>
// CHECK: return
