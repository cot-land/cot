// RUN: %cot emit-cir %s | %FileCheck %s

// Features #037-040: Slice operations — TypeScript syntax

function getStr(): string {
    return "hello";
}

// Verify string type produces slice CIR
// CHECK-LABEL: func.func @getStr
// CHECK: cir.string_constant "hello" : !cir.slice<i8>
// CHECK: return
