# Phase 7 — Generics, Traits, Protocols Design

**Date:** 2026-04-05
**Status:** Design document. Read before implementing #055-060.
**Primary reference:** Swift SIL (Lattner). Design for witness tables from day one.

---

## Why Swift's Design, Not Zig's

Zig resolves all generics at compile time (comptime). This is simple but limiting:
- No dynamic dispatch through protocols/interfaces
- No existential types (`dyn Trait`, `any Protocol`)
- No partial specialization
- Must know concrete types at every call site

Swift's design handles ALL cases from day one:
- **Monomorphization** = optimization pass that specializes when types are known
- **Witness tables** = runtime dispatch when types aren't known
- **Both at once** = specialize some calls, dispatch others

**Retrofitting witness tables onto a monomorphize-only system is painful.**
We learned this with the old cot compiler. Start with Swift's architecture.

---

## Reference Study: Swift SIL Generics

### Core Concepts

**1. Generic Signature** — describes what a generic function needs:
- Type parameters: `<T, U>`
- Requirements (constraints): `T: Hashable`, `U: Equatable`, `T.Element == U`
- Source: `swift/include/swift/AST/GenericSignature.h`

**2. Witness Table** — runtime lookup table for protocol conformance:
- One per (Type, Protocol) pair: "Int conforms to Hashable"
- Contains: method implementations, associated types, base protocol conformances
- Source: `swift/include/swift/SIL/SILWitnessTable.h`

**3. Substitution Map** — maps generic params to concrete types + conformances:
- `SubstitutionMap { signature, replacementTypes[], conformances[] }`
- Carried on every `apply` instruction that calls a generic function
- Source: `swift/include/swift/AST/SubstitutionMap.h`

**4. Existential Container** — runtime representation of "any P":
- Contains: value + type metadata + witness table pointer(s)
- Created by `init_existential`, consumed by `open_existential`
- Source: `swift/include/swift/SIL/SILInstruction.h` (lines 7931+)

### Swift's Two Dispatch Modes

**Monomorphic (specialized):**
```
sil @process_Int : (Int) -> Int {
  %fn = function_ref @Int.hashValue    // Direct call — no witness table
  %result = apply %fn(%value)
  return %result
}
```

**Polymorphic (witness dispatch):**
```
sil @process : <T: Hashable> (T) -> Int {
  %fn = witness_method $T, #Hashable.hash  // Lookup through witness table
  %result = apply %fn(%value)
  return %result
}
```

The specializer converts polymorphic → monomorphic when types are known.

---

## CIR Design

### New CIR Types

```mlir
// Generic signature — attached as attribute on generic functions
// Lists type parameters and their constraints
#cir.generic_sig<T: Hashable, U: Equatable>

// Witness table — global constant mapping protocol → implementations
!cir.witness_table<"Int_Hashable",
    hash: @Int_hash,
    equals: @Int_equals>

// Existential container — runtime value for "any Protocol"
!cir.existential<"Hashable">
// Lowers to: !llvm.struct<(ptr, ptr, ptr)> = {value_ptr, type_metadata, witness_table}
```

### New CIR Ops

**Generic function representation:**
```mlir
// Generic function — carries its generic signature
// Before specialization, type params are unresolved
func.func @process(%value: !cir.type_param<"T">) -> i32
    attributes { cir.generic_sig = #cir.generic_sig<T: Hashable> }

// Specialized version — all types concrete, no generic sig
func.func @process_Int(%value: i32) -> i32
```

**Witness table ops:**
```mlir
// Look up method through witness table (protocol dispatch)
%fn = cir.witness_method %type_metadata, "hash"
    : (!cir.ptr) -> ((!cir.ptr) -> i32)

// Call through witness — same as func.call but tracks generic dependency
%result = cir.apply %fn(%value)
    subs [T = i32]
    witnesses [@Int_Hashable_witness]
```

**Existential container ops:**
```mlir
// Pack concrete value into existential (like Swift init_existential)
%e = cir.init_existential %int_val, @Int_Hashable_witness
    : i32 to !cir.existential<"Hashable">

// Unpack existential — gets value pointer + witness table
%val, %witness = cir.open_existential %e
    : !cir.existential<"Hashable"> to (!cir.ptr, !cir.ptr)
```

**Specialization support:**
```mlir
// Monomorphized call (after specialization pass)
%result = func.call @process_Int(%value) : (i32) -> i32
// No subs, no witnesses — pure concrete call
```

### New CIR Passes

**1. WitnessTableGeneration** — for each (Type, Protocol) conformance, emit a global:
```mlir
cir.witness_table @Int_Hashable {
    method "hash" = @Int_hash
    method "equals" = @Int_equals
}
```

**2. GenericSpecializer** — clone generic functions for concrete type args:
- Find all `cir.apply` with substitutions
- Clone the generic function body
- Replace type parameters with concrete types
- Replace `cir.witness_method` with direct `func.call` (devirtualize)
- Remove substitution attributes

**3. ExistentialSpecializer** (optional optimization):
- Find `cir.init_existential` immediately followed by `cir.open_existential`
- Replace with direct value use (eliminate the container)

---

## Frontend Syntax

### ac (kitchen sink)
```
trait Hashable {
    fn hash(self) -> i64
}

impl Hashable for Point {
    fn hash(self) -> i64 { return self.x as i64 * 31 + self.y as i64 }
}

fn process[T: Hashable](value: T) -> i64 {
    return value.hash()
}

// Concrete call — specialized
let x: i64 = process(my_point)

// Dynamic dispatch — existential
let h: dyn Hashable = my_point
let y: i64 = process(h)
```

### Zig
```zig
// Zig has no traits — uses comptime + anytype (always monomorphized)
fn process(comptime T: type, value: T) i64 {
    return value.hash();
}
// CIR: always-specialize, no witness tables needed
```

### TypeScript
```typescript
// TS has interfaces (structural typing, erased at runtime)
interface Hashable { hash(): number; }

function process<T extends Hashable>(value: T): number {
    return value.hash();
}
// CIR: either monomorphize or witness dispatch
```

### Swift
```swift
protocol Hashable {
    func hash() -> Int64
}

extension Point: Hashable {
    func hash() -> Int64 { return Int64(x) * 31 + Int64(y) }
}

func process<T: Hashable>(_ value: T) -> Int64 {
    return value.hash()
}

// Concrete call
let x = process(myPoint)  // Specialized to process_Point

// Existential
let h: any Hashable = myPoint
let y = process(h)  // Witness dispatch
```

---

## Implementation Order

### Phase 7a: Monomorphized Generics (simplest, works for Zig)
1. Add `!cir.type_param<"T">` placeholder type
2. Add `cir.generic_sig` attribute on functions
3. Frontend emits generic functions with type_param types
4. Add `GenericSpecializer` pass that:
   - Finds call sites with concrete type args
   - Clones generic body, substitutes types
   - Replaces call with monomorphized version
5. All 4 frontends emit generic functions

### Phase 7b: Traits / Protocols (static dispatch via monomorphization)
1. Add trait/protocol/interface declaration syntax to ac/Swift/TS
2. Add conformance/implementation syntax
3. Trait method calls → monomorphize to direct calls (like Zig comptime)
4. No witness tables yet — pure static dispatch

### Phase 7c: Witness Tables (dynamic dispatch)
1. Add `!cir.witness_table` type + global op
2. Add `cir.witness_method` op
3. Add `WitnessTableGeneration` pass
4. Generic calls that can't be specialized use witness dispatch

### Phase 7d: Existential Containers
1. Add `!cir.existential<"Protocol">` type
2. Add `cir.init_existential` / `cir.open_existential` ops
3. ac `dyn Trait`, Swift `any Protocol`, TS interface variable

### Phase 7e: Specialization Optimization
1. `DevirtualizationPass` — convert witness_method to direct call when type known
2. `ExistentialSpecializerPass` — eliminate init/open pairs
3. Performance: specialized code should match hand-written concrete code

---

## Lowering to LLVM

**Witness tables** → LLVM global constant struct of function pointers:
```llvm
@Int_Hashable_witness = constant { ptr, ptr } { @Int_hash, @Int_equals }
```

**witness_method** → GEP into witness table + load function pointer:
```llvm
%fn_ptr = getelementptr { ptr, ptr }, ptr @witness_table, i32 0, i32 0
%fn = load ptr, ptr %fn_ptr
```

**Existential container** → struct { value_buffer, type_metadata, witness_ptr }:
```llvm
%container = alloca { [24 x i8], ptr, ptr }  ; 24 bytes for inline value
```

**Specialized functions** → regular LLVM functions (no generic overhead):
```llvm
define i32 @process_Int(i32 %value) { ... }
```

---

## Reference Code to Port

| What | Port from | Source |
|------|-----------|--------|
| Generic signature | Swift GenericSignature | `~/claude/references/swift/include/swift/AST/GenericSignature.h` |
| Requirements | Swift Requirement | `~/claude/references/swift/include/swift/AST/Requirement.h` |
| Witness table | Swift SILWitnessTable | `~/claude/references/swift/include/swift/SIL/SILWitnessTable.h` |
| Witness method | Swift WitnessMethodInst | `~/claude/references/swift/include/swift/SIL/SILInstruction.h` |
| Existential ops | Swift Init/OpenExistential | Same as above (lines 7931-8182) |
| Substitution map | Swift SubstitutionMap | `~/claude/references/swift/include/swift/AST/SubstitutionMap.h` |
| Specializer | Swift GenericSpecializer | `~/claude/references/swift/lib/SILOptimizer/Transforms/GenericSpecializer.cpp` |
| Reabstraction | Swift Generics utils | `~/claude/references/swift/include/swift/SILOptimizer/Utils/Generics.h` |

---

## What This Enables

With Phase 7 complete, CIR can express:
- Generic functions that work with any conforming type
- Protocol/trait requirements enforced at compile time
- Both static dispatch (monomorphized, zero-cost) and dynamic dispatch (witness tables)
- Existential types for runtime polymorphism
- The same generic function can be specialized for hot paths and use witness dispatch for cold paths

This is Lattner's vision for Swift, applied to a universal IR.
