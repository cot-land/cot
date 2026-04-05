// RUN: %cot emit-cir %s | %FileCheck %s

// Kitchen sink: all Swift features COT supports in one real-world example.

struct Vec2 {
    let x: Int32
    let y: Int32
}

enum Direction: Int32 {
    case north = 0
    case south = 1
    case east = 2
    case west = 3
}

func vec2Add(a: Vec2, b: Vec2) -> Vec2 {
    return Vec2(x: a.x + b.x, y: a.y + b.y)
}

func dot(a: Vec2, b: Vec2) -> Int32 {
    return a.x * b.x + a.y * b.y
}

func magnitudeSquared(v: Vec2) -> Int32 {
    return dot(v, v)
}

func clamp(val: Int32, lo: Int32, hi: Int32) -> Int32 {
    if val < lo {
        return lo
    }
    if val > hi {
        return hi
    }
    return val
}

func sumRange() -> Int32 {
    var total: Int32 = 0
    for i in 0..<10 {
        total += i
    }
    return total
}

func dirToInt(d: Direction) -> Int32 {
    switch d {
    case .north:
        return 0
    case .south:
        return 1
    case .east:
        return 2
    case .west:
        return 3
    default:
        return 0
    }
}

func getFirst() -> Int32 {
    let arr: [Int32] = [10, 20, 30]
    return arr[0]
}

func widen(x: Int32) -> Int64 {
    return Int64(x)
}

func getGreeting() -> String {
    return "hello"
}

// CHECK-LABEL: func.func @vec2Add
// CHECK: cir.field_val
// CHECK: cir.add
// CHECK: cir.struct_init

// CHECK-LABEL: func.func @dot
// CHECK: cir.mul
// CHECK: cir.add

// CHECK-LABEL: func.func @magnitudeSquared
// CHECK: call @dot

// CHECK-LABEL: func.func @clamp
// CHECK: cir.cmp slt
// CHECK: cir.cmp sgt

// CHECK-LABEL: func.func @sumRange
// CHECK: cir.alloca
// CHECK: cir.cmp slt
// CHECK: cir.condbr
// CHECK: cir.add

// CHECK-LABEL: func.func @dirToInt
// CHECK: cir.enum_value
// CHECK: cir.switch

// CHECK-LABEL: func.func @getFirst
// CHECK: cir.array_init
// CHECK: cir.elem_val

// CHECK-LABEL: func.func @widen
// CHECK: cir.extsi

// CHECK-LABEL: func.func @getGreeting
// CHECK: cir.string_constant "hello"
