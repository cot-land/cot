// RUN: %cot emit-cir %s | %FileCheck %s

// Feature #032-033: Address-of and dereference — Zig syntax

pub fn takes_ref(p: *i32) i32 {
    return p.*;
}

// CHECK-LABEL: func.func @takes_ref
// CHECK-SAME: !cir.ref<i32>
// CHECK: cir.deref %arg0 : !cir.ref<i32> to i32
