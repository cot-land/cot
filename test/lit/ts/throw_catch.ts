// RUN: %cot emit-cir %s | %FileCheck %s

// Phase 5c: Exception-based error handling — TypeScript syntax

function mayThrow(): number {
    throw 42;
}

// CHECK-LABEL: func.func @mayThrow
// CHECK: cir.throw
// CHECK-SAME: i32
