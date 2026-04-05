// RUN: %cot emit-cir %s | %FileCheck %s

// Type annotations: number → i32, boolean → i1, string → !cir.slice<i8>

function number_identity(x: number): number {
    return x;
}

function bool_identity(x: boolean): boolean {
    return x;
}

function multi_types(a: number, b: number, flag: boolean): number {
    return a + b;
}

function takes_string(s: string): number {
    return 0;
}

// CHECK-LABEL: func.func @number_identity
// CHECK-SAME: (%arg0: i32) -> i32

// CHECK-LABEL: func.func @bool_identity
// CHECK-SAME: (%arg0: i1) -> i1

// CHECK-LABEL: func.func @multi_types
// CHECK-SAME: (%arg0: i32, %arg1: i32, %arg2: i1) -> i32

// CHECK-LABEL: func.func @takes_string
// CHECK-SAME: (%arg0: !cir.slice<i8>) -> i32
