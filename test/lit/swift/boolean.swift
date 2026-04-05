// RUN: %cot emit-cir %s | %FileCheck %s

// libsc: boolean literals and bool function parameters

func yes() -> Bool {
    return true
}

func no() -> Bool {
    return false
}

func identity(flag: Bool) -> Bool {
    return flag
}

// CHECK-LABEL: func.func @yes
// CHECK: cir.constant true : i1
// CHECK: return

// CHECK-LABEL: func.func @no
// CHECK: cir.constant false : i1
// CHECK: return

// CHECK-LABEL: func.func @identity
// CHECK: return %arg0 : i1
