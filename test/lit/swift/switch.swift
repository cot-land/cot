// RUN: %cot emit-cir %s | %FileCheck %s

// libsc: switch on enum with dot-prefix case patterns

enum Color: Int32 {
    case red = 0
    case green = 1
    case blue = 2
}

func colorToInt(c: Color) -> Int32 {
    switch c {
    case .red:
        return 1
    case .green:
        return 2
    case .blue:
        return 3
    default:
        return 0
    }
}

// CHECK-LABEL: func.func @colorToInt
// CHECK: cir.enum_value
// CHECK: cir.switch
// CHECK: return
