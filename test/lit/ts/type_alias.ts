// RUN: %cot emit-cir %s | %FileCheck %s

// Type alias declaration: type Result = number | Error

type Result = number | Error;

function succeed(): Result {
    return 42;
}

function fail(): Result {
    throw 1;
}

// CHECK-LABEL: func.func @succeed
// CHECK-SAME: -> !cir.error_union<i32>
// CHECK: cir.wrap_result
// CHECK-SAME: i32 to !cir.error_union<i32>
// CHECK: return

// CHECK-LABEL: func.func @fail
// CHECK-SAME: -> !cir.error_union<i32>
// CHECK: cir.throw
