// RUN: %cot emit-cir %s | %FileCheck %s

// Feature #035-036: String type + literal — Zig syntax

pub fn getHello() []const u8 {
    return "hello";
}

pub fn getEmpty() []const u8 {
    return "";
}

pub fn getWithSpaces() []const u8 {
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
