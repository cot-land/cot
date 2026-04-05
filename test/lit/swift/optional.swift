// RUN: %cot emit-cir %s | %FileCheck %s

// libsc: optional type — Int32?, nil, if let

func getNull() -> Int32 {
    var x: Int32? = nil
    x = 42
    if let val = x {
        return val
    }
    return 0
}

// CHECK-LABEL: func.func @getNull
// CHECK: cir.none : !cir.optional<i32>
// CHECK: cir.store
// CHECK: cir.wrap_optional
// CHECK: cir.store
// CHECK: cir.is_non_null
// CHECK: cir.optional_payload
// CHECK: return
