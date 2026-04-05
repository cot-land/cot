// RUN: %cot emit-cir %s | %FileCheck %s

// Feature #052: Switch expression (value-producing) — Zig syntax
// Must be valid Zig — compilable by zig build-exe
// Note: Zig switch expressions already handled by switch.zig
// This test verifies the value-producing path specifically.

const Color = enum(u8) { red, green, blue };

pub fn colorValue(c: Color) i32 {
    const x = switch (c) {
        .red => 10,
        .green => 20,
        .blue => 30,
    };
    return x;
}

// CHECK-LABEL: func.func @colorValue
// CHECK: cir.enum_value
// CHECK: cir.switch
// CHECK: return
