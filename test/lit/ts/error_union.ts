// RUN: %cot emit-cir %s | %FileCheck %s

// Features #045-048: Error union type — TypeScript syntax
// TypeScript uses exceptions (throw/catch), not error unions.
// throw maps to cir.throw, try/catch maps to cir.invoke + cir.landingpad.

function getError(): number | Error {
    throw 1;
}

function getResult(): number | Error {
    return 42;
}

// CHECK-LABEL: func.func @getError
// CHECK: cir.throw
// CHECK-SAME: i32

// CHECK-LABEL: func.func @getResult
// CHECK: cir.wrap_result
// CHECK-SAME: i32 to !cir.error_union<i32>
// CHECK: return
