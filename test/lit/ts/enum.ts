// RUN: %cot emit-cir %s | %FileCheck %s

// Features #049-050: Enum type + value — TypeScript syntax
// Must be valid TypeScript — compilable by tsc

enum Color { Red, Green, Blue }

function getRed(): Color {
    return Color.Red;
}

function getBlue(): Color {
    return Color.Blue;
}

// CHECK-LABEL: func.func @getRed
// CHECK: cir.enum_constant "Red" : !cir.enum<"Color"
// CHECK: return

// CHECK-LABEL: func.func @getBlue
// CHECK: cir.enum_constant "Blue" : !cir.enum<"Color"
// CHECK: return
