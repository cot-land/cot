// RUN: %cot emit-cir %s | %FileCheck %s

// Kitchen sink: all TypeScript features COT supports in one real-world example.
// This must be valid TypeScript — compilable by tsc.

interface Vec2 {
    x: number;
    y: number;
}

function vec2Add(a: Vec2, b: Vec2): Vec2 {
    return { x: a.x + b.x, y: a.y + b.y };
}

function dot(a: Vec2, b: Vec2): number {
    return a.x * b.x + a.y * b.y;
}

function magnitudeSquared(v: Vec2): number {
    return dot(v, v);
}

function clamp(val: number, lo: number, hi: number): number {
    if (val < lo) return lo;
    if (val > hi) return hi;
    return val;
}

function abs(x: number): number {
    return x > 0 ? x : 0 - x;
}

function sumTo(n: number): number {
    let total: number = 0;
    for (let i: number = 0; i < n; i = i + 1) {
        total = total + i;
    }
    return total;
}

function factorial(n: number): number {
    let result: number = 1;
    let i: number = 2;
    while (i <= n) {
        result = result * i;
        i += 1;
    }
    return result;
}

function isEven(n: number): boolean {
    return n % 2 == 0;
}

function greetLen(s: string): number {
    return s.len;
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

// CHECK-LABEL: func.func @abs
// CHECK: cir.cmp sgt
// CHECK: cir.select

// CHECK-LABEL: func.func @sumTo
// CHECK: cir.cmp slt
// CHECK: cir.condbr
// CHECK: cir.add

// CHECK-LABEL: func.func @factorial
// CHECK: cir.cmp sle
// CHECK: cir.mul

// CHECK-LABEL: func.func @isEven
// CHECK: cir.rem
// CHECK: cir.cmp eq

// CHECK-LABEL: func.func @greetLen
// CHECK: cir.slice_len
