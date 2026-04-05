// RUN: %cot emit-cir %s | %FileCheck %s

// libsc: throws/throw — Swift error handling mapped to CIR error unions
// func throws -> T maps to !cir.error_union<T>
// throw expr maps to cir.throw

func mayFail() throws -> Int32 {
    throw 1
}

func getResult() throws -> Int32 {
    return 42
}

// CHECK-LABEL: func.func @mayFail
// CHECK-SAME: -> !cir.error_union<i32>
// CHECK: cir.throw
// CHECK-SAME: i32

// CHECK-LABEL: func.func @getResult
// CHECK-SAME: -> !cir.error_union<i32>
// CHECK: cir.wrap_result
// CHECK-SAME: i32 to !cir.error_union<i32>
// CHECK: return
