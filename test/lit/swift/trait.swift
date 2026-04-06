// RUN: %cot emit-cir %s | %FileCheck %s

// Feature #057-058: Protocol declarations + conformances — Swift syntax
// Swift protocol + extension maps to cir.witness_table + cir.trait_call.

struct Point {
    let x: Int32
    let y: Int32
}

protocol Summable {
    func sum() -> Int32
}

extension Point: Summable {
    func sum() -> Int32 {
        return self.x + self.y
    }
}

func applySummable<T: Summable>(_ val: T) -> Int32 {
    return val.sum()
}

func main() -> Int32 {
    return 42
}

// Impl method emitted with mangled name (self injected as first param)
// CHECK-LABEL: func.func @Point_Summable_sum
// CHECK-SAME: !cir.struct<"Point"
// CHECK: cir.field_val
// CHECK: cir.field_val
// CHECK: cir.add
// CHECK: return

// Witness table emitted
// CHECK: cir.witness_table "Point_Summable"
// CHECK-SAME: protocol("Summable")
// CHECK-SAME: methods(["sum"] = [@Point_Summable_sum])
