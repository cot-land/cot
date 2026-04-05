// RUN: %cot emit-cir %s | %FileCheck %s

// Feature #051: Switch statement — TypeScript syntax
// Must be valid TypeScript — compilable by tsc

enum Color { Red, Green, Blue }

function colorToInt(c: Color): number {
    switch (c) {
        case Color.Red: return 1;
        case Color.Green: return 2;
        case Color.Blue: return 3;
    }
    return 0;
}

// CHECK-LABEL: func.func @colorToInt
// CHECK: cir.enum_value
// CHECK: cir.switch
// CHECK: return
