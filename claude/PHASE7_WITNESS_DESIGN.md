# Phase 7 — Witness Table Architecture (Revised)

**Date:** 2026-04-06
**Status:** Design document. Replaces the monomorphization-only approach.
**Primary reference:** Swift SIL. Designed for ARC from day one.

---

## The Critical Insight: Two Kinds of Witness Tables

Swift has TWO distinct witness table concepts that CIR must support:

### 1. Protocol Witness Table (PWL) — "What can T do?"

Maps protocol/trait requirements to concrete implementations.
One per (Type, Protocol) conformance pair.

```
@Int_Hashable_pwt = {
    hash: @Int_hash,           // protocol method → concrete implementation
    equals: @Int_equals,
}
```

**Used by:** `cir.witness_method` for dynamic protocol dispatch.

### 2. Value Witness Table (VWT) — "How do I manage T's memory?"

Maps type operations: size, alignment, copy, destroy, move.
One per concrete type. **This is what ARC needs.**

```
// Reference type (class) — needs ARC
@Dog_vwt = {
    size: 8, alignment: 8,
    copy: @arc_retain,         // copy = retain (increment refcount)
    destroy: @arc_release,     // destroy = release (decrement, maybe free)
    move: @noop,               // move = just copy the pointer
}

// Value type (struct) — no ARC
@Point_vwt = {
    size: 8, alignment: 4,
    copy: @memcpy,             // copy = memcpy
    destroy: @noop,            // destroy = nothing
    move: @memcpy,             // move = memcpy
}
```

**Used by:** Generic function memory management, ARC insertion.

### Why Both?

A generic function `fn store<T: Hashable>(x: T)` needs:
- **PWL** to call `x.hash()` (protocol method dispatch)
- **VWT** to allocate memory for x, copy x, destroy x when done

These are orthogonal. A type can have a VWT (always) and zero or more PWTs.

---

## How ARC + Generics Work Together

### The Problem

```ac
fn cache<T>(value: T) {
    let ptr = allocate(???)     // How many bytes?
    copy(value, ptr)            // How to copy? ARC retain or memcpy?
    // ... later ...
    destroy(ptr)                // How to destroy? ARC release or noop?
}
```

Without knowing T, the compiler can't decide. **This is why VWT exists.**

### The Solution

The VWT is passed as hidden metadata to generic functions:

```mlir
// Generic function — VWT passed as hidden parameter
func.func @cache(%value: !cir.type_param<"T">,
                 %T_vwt: !cir.ptr)  // ← value witness table for T
{
    // Load size from VWT
    %size = cir.vwt_size %T_vwt : i64

    // Allocate
    %ptr = cir_arc.alloc %size : !cir.ptr

    // Copy (calls retain for ref types, memcpy for value types)
    cir.vwt_copy %T_vwt, %value, %ptr

    // Later: destroy (calls release for ref types, noop for value types)
    cir.vwt_destroy %T_vwt, %ptr
}
```

### After Specialization (T = Int32)

The specializer inlines all VWT operations:

```mlir
func.func @cache_Int32(%value: i32) {
    %ptr = cir_arc.alloc 4 : !cir.ptr    // size=4 inlined
    cir.store %value, %ptr : i32          // copy=memcpy inlined
    // destroy = noop (eliminated)
}
```

**Zero-cost abstraction.** Specialized code is identical to hand-written.

---

## Reference Compiler Comparison

| | Zig | Rust | Swift | CIR (planned) |
|-|-----|------|-------|---------------|
| **Generic IR** | No (comptime) | No (monomorphize) | Yes (SIL) | **Yes** |
| **Protocol witness** | N/A | Vtable (dyn only) | Yes (all protocols) | **Yes** |
| **Value witness** | N/A | Drop glue in vtable | Yes (all types) | **Yes** |
| **ARC + generics** | N/A (manual) | Monomorphize drop | VWT drives ARC | **VWT drives ARC** |
| **Specialization** | N/A (always) | N/A (always) | Optimization pass | **Optimization pass** |
| **Dynamic dispatch** | N/A | dyn Trait only | Protocols + existentials | **Protocols + existentials** |

**CIR follows Swift** because:
1. We need ARC (Phase 8) — VWT is required
2. We need dynamic dispatch — PWL is required
3. Specialization is an optimization, not the only path
4. All four reference languages can target this model

---

## CIR Types and Ops

### New Types

```mlir
// Generic type parameter — unresolved until specialization
!cir.type_param<"T">

// Protocol witness table — maps protocol methods to implementations
!cir.protocol_witness<"Hashable", hash: @fn_ptr, equals: @fn_ptr>

// Value witness table — maps type operations for memory management
!cir.value_witness<size: i64, align: i64, copy: @fn, destroy: @fn, move: @fn>

// Existential container — runtime value of "any Protocol"
!cir.existential<"Hashable">
// Lowers to: { [inline_buffer x i8], type_metadata_ptr, witness_table_ptr }
```

### New Ops — Protocol Dispatch

```mlir
// Look up method in protocol witness table
%fn = cir.witness_method %pwt, "hash"
    : !cir.ptr to ((!cir.ptr) -> i64)

// Pack value into existential container
%e = cir.init_existential %value, %vwt, %pwt
    : (T, !cir.ptr, !cir.ptr) to !cir.existential<"Hashable">

// Unpack existential
%value, %vwt, %pwt = cir.open_existential %e
    : !cir.existential<"Hashable"> to (!cir.ptr, !cir.ptr, !cir.ptr)
```

### New Ops — Value Witness (ARC integration)

```mlir
// Query type size from value witness table
%size = cir.vwt_size %vwt : i64

// Query type alignment
%align = cir.vwt_align %vwt : i64

// Copy value through witness (retain for ref types, memcpy for value types)
cir.vwt_copy %vwt, %src, %dst : (!cir.ptr, !cir.ptr, !cir.ptr)

// Destroy value through witness (release for ref types, noop for value types)
cir.vwt_destroy %vwt, %ptr : (!cir.ptr, !cir.ptr)

// Move value through witness (transfer ownership without copy)
cir.vwt_move %vwt, %src, %dst : (!cir.ptr, !cir.ptr, !cir.ptr)
```

### New Ops — Generic Function Calls

```mlir
// Call generic function with substitutions + witness metadata
%result = cir.generic_apply @process(%value)
    subs [T = i32]
    value_witnesses [@Int32_vwt]
    protocol_witnesses [@Int32_Hashable_pwt]
    : (i32) -> i64

// After specialization, becomes a regular call:
%result = func.call @process_Int32(%value) : (i32) -> i64
```

### New Passes

```
GenericSpecializer     — clone generic functions for concrete types,
                        inline VWT operations, devirtualize witness methods

WitnessTableGenerator  — emit PWTs and VWTs for each (Type, Protocol) pair
                        and each concrete type

ARCInsertion           — insert retain/release using VWT for generic types,
                        direct calls for concrete types
```

---

## Implementation Order

### Phase 7a: Generic Functions in CIR (type_param + generic_apply)
- Add `!cir.type_param<"T">` type
- Add `cir.generic_apply` with substitution attributes
- Frontends emit generic templates INTO CIR (not monomorphized)
- GenericSpecializer pass clones + substitutes → concrete functions
- **Existing frontend monomorphization continues to work as fallback**

### Phase 7b: Protocol/Trait Declarations + Conformances
- Add protocol declaration syntax to all frontends
- Add conformance/implementation syntax
- Generate protocol witness tables (PWTs)
- Store PWTs as LLVM globals

### Phase 7c: Protocol Dispatch (witness_method)
- Add `cir.witness_method` op
- Add `cir.init_existential` / `cir.open_existential`
- Dynamic dispatch through PWTs
- Specializer devirtualizes when type is known

### Phase 7d: Value Witness Tables
- Add `!cir.value_witness` type
- Add `cir.vwt_size/align/copy/destroy/move` ops
- Generate VWTs for every concrete type
- Generic functions receive VWT as hidden parameter

### Phase 8: ARC Integration
- `ARCInsertion` pass uses VWT for generic code
- Direct retain/release for monomorphic code
- Indirect through VWT for polymorphic code
- `ARCOptimization` pass eliminates redundant ops

---

## Frontend Syntax

### ac
```
trait Hashable {
    fn hash(self) -> i64
}

impl Hashable for Point {
    fn hash(self) -> i64 { ... }
}

fn process[T: Hashable](value: T) -> i64 {
    return value.hash()
}

// Concrete call — specializer monomorphizes
let x = process(my_point)

// Dynamic — existential container + witness dispatch
let h: dyn Hashable = my_point
let y = process(h)
```

### Swift
```swift
protocol Hashable {
    func hash() -> Int64
}

extension Point: Hashable {
    func hash() -> Int64 { ... }
}

func process<T: Hashable>(_ value: T) -> Int64 {
    return value.hash()
}
```

### Zig
```zig
// Zig has no protocols — comptime duck typing
// Frontend emits always-specialized code
// No witness tables emitted for Zig-sourced generics
fn process(comptime T: type, value: T) i64 {
    return value.hash();
}
```

### TypeScript
```typescript
interface Hashable {
    hash(): number;
}

function process<T extends Hashable>(value: T): number {
    return value.hash();
}
```

---

## Lowering to LLVM

**Protocol witness table** → LLVM global constant struct of function pointers:
```llvm
@Point_Hashable_pwt = constant { ptr, ptr } { @Point_hash, @Point_equals }
```

**Value witness table** → LLVM global constant struct:
```llvm
@Int32_vwt = constant { i64, i64, ptr, ptr, ptr } {
    4,            ; size
    4,            ; alignment
    @memcpy,      ; copy
    @noop,        ; destroy
    @memcpy       ; move
}
```

**Existential container** → LLVM struct:
```llvm
; { inline_value_buffer, type_metadata_ptr, witness_table_ptr }
%existential = type { [24 x i8], ptr, ptr }
```

**witness_method** → GEP into witness table + load function pointer:
```llvm
%fn_ptr = getelementptr { ptr, ptr }, ptr @pwt, i32 0, i32 0  ; method index
%fn = load ptr, ptr %fn_ptr
call i64 %fn(ptr %value)
```

**vwt_copy** → load copy function from VWT + indirect call:
```llvm
%copy_ptr = getelementptr { i64, i64, ptr, ptr, ptr }, ptr %vwt, i32 0, i32 2
%copy_fn = load ptr, ptr %copy_ptr
call void %copy_fn(ptr %src, ptr %dst)
```

---

## Reference Code

| What | Source |
|------|--------|
| Protocol witness table structure | `~/claude/references/swift/include/swift/SIL/SILWitnessTable.h` |
| Value witness table structure | `~/claude/references/swift/include/swift/ABI/ValueWitness.def` |
| Type metadata (contains VWT ptr) | `~/claude/references/swift/include/swift/Runtime/Metadata.h` |
| ARC + generics | `~/claude/references/swift/lib/SILOptimizer/ARC/` |
| Generic specializer | `~/claude/references/swift/lib/SILOptimizer/Transforms/GenericSpecializer.cpp` |
| Substitution map | `~/claude/references/swift/include/swift/AST/SubstitutionMap.h` |
| Existential ops | `~/claude/references/swift/include/swift/SIL/SILInstruction.h` (lines 7931+) |
| Rust drop glue | `~/claude/references/rust/compiler/rustc_middle/src/ty/instance.rs` |
| Rust vtable entries | `~/claude/references/rust/compiler/rustc_middle/src/ty/vtable.rs` |
