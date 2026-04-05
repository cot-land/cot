// RUN: %cot emit-cir %s | %FileCheck %s

// libsc: String literals

func getHello() -> String {
    return "hello"
}

func getEmpty() -> String {
    return ""
}

func getWithSpaces() -> String {
    return "hello world"
}

// CHECK-LABEL: func.func @getHello
// CHECK: cir.string_constant "hello" : !cir.slice<i8>
// CHECK: return

// CHECK-LABEL: func.func @getEmpty
// CHECK: cir.string_constant "" : !cir.slice<i8>
// CHECK: return

// CHECK-LABEL: func.func @getWithSpaces
// CHECK: cir.string_constant "hello world" : !cir.slice<i8>
// CHECK: return
