// RUN: %cot emit-cir %s | %FileCheck %s

pub fn yes() bool {
    return true;
}

pub fn no() bool {
    return false;
}

// CHECK-LABEL: func.func @yes
// CHECK: cir.constant true : i1
// CHECK: return

// CHECK-LABEL: func.func @no
// CHECK: cir.constant false : i1
// CHECK: return
