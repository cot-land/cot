// RUN: %cot emit-cir %s | %FileCheck %s

// Feature #055: Generic function — TypeScript syntax
// Must be valid TypeScript — compilable by tsc

function identity<T>(x: T): T {
    return x;
}

function main(): number {
    return identity<number>(42);
}

// Frontend monomorphizes: identity<number> → identity_number
// CHECK-LABEL: func.func @main
// CHECK: call @identity
// CHECK: return
