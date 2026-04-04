// RUN: %cot emit-cir %s | %FileCheck %s

// Feature #031: Pointer/reference type — Zig syntax

pub fn takes_ref(p: *i32) i32 {
    return 0;
}

// CHECK-LABEL: func.func @takes_ref
// CHECK-SAME: !cir.ref<i32>
