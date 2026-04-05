// RUN: %cot emit-cir %s | %FileCheck %s

// Feature #051: Switch statement — Zig syntax
// Must be valid Zig — compilable by zig build-exe

const Color = enum(u8) { red, green, blue };

pub fn colorToInt(c: Color) i32 {
    return switch (c) {
        .red => 1,
        .green => 2,
        .blue => 3,
    };
}

// CHECK-LABEL: func.func @colorToInt
// CHECK: cir.enum_value
// CHECK: cir.switch
// CHECK: return
