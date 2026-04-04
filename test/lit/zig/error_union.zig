// RUN: %cot emit-cir %s | %FileCheck %s

// Features #045-048: Error union type — Zig syntax

const MyError = error{ OutOfMemory, NotFound };

pub fn getError() MyError!i32 {
    return error.OutOfMemory;
}

pub fn getResult() MyError!i32 {
    return 42;
}

// CHECK-LABEL: func.func @getError
// CHECK: cir.wrap_error
// CHECK-SAME: i16 to !cir.error_union<i32>
// CHECK: return

// CHECK-LABEL: func.func @getResult
// CHECK: cir.constant 42
// CHECK: cir.wrap_result
// CHECK-SAME: i32 to !cir.error_union<i32>
// CHECK: return
