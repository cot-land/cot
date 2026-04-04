// RUN: %cot emit-cir %s | %FileCheck %s

// Feature #035-036: String type + literal — TypeScript syntax

function getHello(): string {
    return "hello";
}

function getEmpty(): string {
    return "";
}

function getWithSpaces(): string {
    return "hello world";
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
