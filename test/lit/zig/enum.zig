// RUN: %cot emit-cir %s | %FileCheck %s

// Features #049-050: Enum type + value — Zig syntax
// Must be valid Zig — compilable by zig build-exe

const Color = enum(u8) { red, green, blue };

pub fn getRed() Color {
    return .red;
}

pub fn getBlue() Color {
    return .blue;
}

// CHECK-LABEL: func.func @getRed
// CHECK: cir.enum_constant "red" : !cir.enum<"Color"
// CHECK: return

// CHECK-LABEL: func.func @getBlue
// CHECK: cir.enum_constant "blue" : !cir.enum<"Color"
// CHECK: return
