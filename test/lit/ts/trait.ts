// RUN: %cot emit-cir %s | %FileCheck %s

// Feature #057-058: Interface (protocol) declarations — TypeScript syntax
// TS `interface` with methods + `T extends Interface` generic constraint
// maps to cir.witness_table + cir.trait_call.

interface Summable {
    sum(): number;
}

function applySummable<T extends Summable>(val: T): number {
    return val.sum();
}

function main(): number {
    return 42;
}

// Generic function emitted with type_param and trait_call
// CHECK-LABEL: func.func @applySummable
// CHECK-SAME: !cir.type_param<"T">
// CHECK: cir.trait_call "Summable", "sum"
// CHECK: return

// Main function
// CHECK-LABEL: func.func @main
// CHECK: return
