// RUN: %cot emit-cir %s | %FileCheck %s

// Phase 1: boolean constants true/false

function returns_true(): boolean {
    return true;
}

function returns_false(): boolean {
    return false;
}

// CHECK-LABEL: func.func @returns_true
// CHECK: cir.constant true : i1
// CHECK: return

// CHECK-LABEL: func.func @returns_false
// CHECK: cir.constant false : i1
// CHECK: return
