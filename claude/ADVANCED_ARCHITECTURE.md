# CIR Advanced Architecture — Planning for Phases 7-12

**Date:** 2026-04-05
**Purpose:** Get the hard features right the first time by studying reference compilers BEFORE implementing. This document plans the CIR types, ops, and passes needed for generics, classes, closures, and dynamic dispatch.

**Rule:** Study reference, then port. Never invent. This document IS the study.

**Primary references:** Zig (Andrew Kelley) and Swift SIL (Chris Lattner). These are the
two compilers that innovated on classic approaches. Zig proved comptime can replace
generics. Swift SIL proved witness tables + existential containers are the right
abstraction for dynamic dispatch. CIR follows Lattner's MLIR design — it should follow
his SIL design for the features MLIR doesn't cover.

Rust is consulted for layout/ABI details only. TypeScript for class semantics only.

---

## The Complexity Cliff

Phases 1-6 are "easy" — they map cleanly to LLVM primitives (integers, structs, branches, function calls). The CIR ops are thin wrappers over LLVM ops.

Phases 7-12 are where compiler engineering gets hard:
- **Generics** require monomorphization (generating N copies of a function)
- **Classes** require vtables (runtime dispatch through function pointers)
- **Closures** require environment structs (capturing variables by value/reference)
- **Traits/Interfaces** require witness tables (mapping requirements to implementations)
- **Async** requires coroutine frames (suspendable stack state)

MLIR/LLVM handle NONE of this. We must build it ourselves. This document plans the architecture so we build it once, correctly.

---

## 1. Generics & Monomorphization

### Why Zig's Approach Wins

Zig has no "generics" keyword. Instead, `comptime` parameters naturally produce
monomorphized functions. When you write:

```zig
fn max(comptime T: type, a: T, b: T) T { ... }
_ = max(i32, 1, 2);   // compiler evaluates T=i32 at comptime, emits max_i32
_ = max(f64, 3.0, 2.0); // evaluates T=f64, emits max_f64
```

There is no generic IR. There is no monomorphization pass. The frontend resolves
everything. The IR only ever contains concrete types. This is:
- Simpler (no type variables in the IR)
- Faster (no collector pass scanning the whole module)
- More powerful (comptime can compute types, not just substitute them)

Swift also specializes generics — but as an optimization pass, not as the default.
Unspecialized Swift code uses witness tables (dynamic dispatch) and the specializer
converts to static dispatch when it can prove the concrete type. This is more
flexible but more complex.

**Rust's approach (separate monomorphization collector) is the least innovative.**
It's a brute-force solution that Zig and Swift both improved upon.

### CIR Plan: Zig-First, Swift-Later

**Phase 7a (monomorphized generics):**
- Frontends resolve ALL generic types before emitting CIR
- CIR never contains type variables — every type is concrete
- No MonomorphizePass needed (it's done in the frontend)
- This is exactly Zig's model and matches our "frontend fidelity" rule

```mlir
// Frontend emits concrete instances directly:
func.func @max_i32(%a: i32, %b: i32) -> i32 { ... }
func.func @max_f64(%a: f64, %b: f64) -> f64 { ... }
```

**Phase 7b (dynamic dispatch — when needed):**
- Add Swift SIL's witness tables for trait/protocol dispatch
- This is for `dyn Trait` / TS interfaces used dynamically / ac trait objects
- Most code stays monomorphized; dynamic dispatch is opt-in

**What this means for CIR:** No new types or ops for basic generics. The frontend
does the work. CIR stays simple. When we add dynamic dispatch later, we add it
as new ops on top of a working monomorphized foundation.

Reference:
- `~/claude/references/zig/src/InternPool.zig` — FuncInstance (line 4268)
- `~/claude/references/zig/src/Sema.zig` — comptime function evaluation

---

## 2. Traits / Protocols / Interfaces — Dynamic Dispatch

### Why Swift's SIL Approach Wins

Swift separates two distinct concepts that other languages conflate:

1. **Protocol witness tables** — mapping from abstract requirements to concrete
   implementations. One table per (Type, Protocol) conformance. Static data.
2. **Existential containers** — runtime representation of "any type conforming
   to Protocol P". Contains: value + type metadata + witness table pointer(s).

This separation is Lattner's key insight:
- Witness tables are **compile-time** data. They exist as LLVM globals.
- Existential containers are **runtime** data. They're stack/heap allocated.
- You can have witness tables without existential containers (static dispatch).
- You only pay for existential containers when you actually use `dyn`/`any`.

Zig has no traits — it uses `anytype` (comptime duck typing). This works for Zig
but doesn't help TypeScript (which has interfaces) or ac (which has traits).

**Rust trait objects use a single vtable per trait.** This is simpler but less
flexible — you can't easily compose multiple trait conformances. Swift can.

### CIR Plan: Swift SIL Witness Tables

**Types:**

```mlir
// Witness table — compile-time global, one per (Type, Protocol) pair
// Contains function pointers for each protocol requirement
!cir.witness_table<"Point_Printable",
    print: @Point_print,
    description: @Point_description>

// Existential container — runtime value for dynamic dispatch
// Contains: { value_buffer, type_metadata_ptr, witness_table_ptr }
!cir.existential<"Printable">
```

**Ops:**

```mlir
// Look up a method through a witness table (protocol dispatch)
%fn = cir.witness_method %existential, "print"
    : !cir.existential<"Printable"> to (ptr) -> ()

// Pack a concrete value into an existential container
%e = cir.init_existential %point, @Point_Printable_witness
    : !cir.struct<"Point", ...> to !cir.existential<"Printable">

// Unpack an existential to access the concrete value
%ptr, %witness = cir.open_existential %e
    : !cir.existential<"Printable"> to (!cir.ptr, !cir.ptr)
```

**Lowering:**
- `!cir.witness_table` → `llvm.mlir.global constant` (struct of function pointers)
- `!cir.existential` → `!llvm.struct<(array<3 x ptr>, ptr, ptr)>` — {value_buffer, type_metadata, witness_ptr}
- `cir.witness_method` → GEP into witness table + load function pointer
- `cir.init_existential` → store value + store metadata + store witness ptr
- `cir.open_existential` → extract pointers

**Passes:**
- `WitnessTableGeneration` — for each (Type, Protocol) conformance, emit a global
- `Devirtualization` (optimization) — replace witness_method with direct call when type is known

Reference:
- `~/claude/references/swift/include/swift/SIL/SILWitnessTable.h` (lines 40-200)
- `~/claude/references/swift/include/swift/SIL/SILInstruction.h` (witness_method, init/open_existential)

---

## 3. Classes and VTables

### Why Swift's Approach Wins (Again)

Swift separates class dispatch (vtable) from protocol dispatch (witness table).
This means:
- A class has ONE vtable (like C++ vtable)
- A class can conform to MANY protocols (multiple witness tables)
- Protocol conformance doesn't pollute the class vtable

The vtable is embedded as the first field of the class instance, exactly like C++:

```
// Memory layout of a class instance:
[ vtable_ptr | field_1 | field_2 | ... ]
```

**TypeScript class compilation** follows this same pattern — the prototype chain
is semantically equivalent to a vtable chain. TS `extends` maps to vtable
inheritance.

### CIR Plan: Struct + VTable Pointer

No new CIR *type* needed. A class is a struct with vtable_ptr as field 0.

```mlir
// "Class" is syntactic sugar for:
!cir.struct<"Dog", _vtable: !cir.ptr, name: !cir.slice<i8>>

// VTable as LLVM global constant
llvm.mlir.global constant @Dog_vtable =
    !llvm.struct<(ptr, ptr)> { @Dog_speak, @Dog_toString }

// Constructor: alloc + set vtable + init fields
%obj = cir.class_alloc "Dog"  // → malloc + store @Dog_vtable to field 0

// Virtual method call
%result = cir.class_method %obj, 0  // → load vtable_ptr, GEP slot 0, load fn, call
```

**New CIR ops:**
- `cir.class_alloc "Name"` — allocate + initialize vtable pointer
- `cir.class_method %obj, slot_index` — vtable dispatch (indirect call)
- `cir.upcast %obj : Child to Parent` — noop pointer cast
- `cir.downcast %obj : Parent to Child` — runtime type check

**Why NOT a separate `!cir.class` type:** Classes are structs. Adding a separate
type creates a parallel type hierarchy that complicates the type converter.
Instead, class semantics are in the ops (class_alloc, class_method), not the type.

Reference:
- `~/claude/references/swift/include/swift/SIL/SILVTable.h` (lines 42-176)
- `~/claude/references/swift/include/swift/SIL/SILInstruction.h` (ClassMethodInst)

---

## 4. Closures

### Why Swift's Approach Wins

Swift SIL has exactly two closure ops:
- `partial_apply %fn(%captures)` — bind a function with captured values
- `thin_to_thick_function %fn` — wrap a non-capturing function as a closure

A closure in SIL is a "thick function" = `{ function_pointer, context_pointer }`.
The context holds captured variables. This is the cleanest model because:
- No special "closure type" — it's just a function with a context
- Captures are explicit in the IR (not hidden behind syntactic sugar)
- The ABI is clear: every closure call passes context as a hidden argument

Zig has no closures (by design — closures hide allocations). Rust closures
desugar to anonymous structs implementing Fn/FnMut/FnOnce traits. Swift's
model is simpler.

### CIR Plan: Swift's Thick Functions

```mlir
// Create closure environment (captured variables)
%env = cir.closure_env(%x, %y) : (i32, i32) -> !cir.closure_env<x: i32, y: i32>

// Partial apply: bind function with environment
%closure = cir.partial_apply @add_xy, %env
    : (@add_xy, !cir.closure_env<...>) -> !cir.closure<(i32) -> i32>

// Call closure (passes env as hidden first arg)
%result = cir.call_closure %closure(%arg) : !cir.closure<(i32) -> i32>
```

**Lowering:**
- `!cir.closure<(Args) -> Ret>` → `!llvm.struct<(ptr, ptr)>` — {fn_ptr, env_ptr}
- `cir.closure_env` → alloca + store each captured variable
- `cir.partial_apply` → construct {fn_ptr, env_ptr} struct
- `cir.call_closure` → extract fn_ptr, call with env_ptr as hidden arg

Reference:
- `~/claude/references/swift/include/swift/SIL/SILInstruction.h` (PartialApplyInst, ThinToThickFunctionInst)

---

## 5. Async / Coroutines

### Why LLVM Coroutines Win (No Choice)

Async requires stack frame persistence across suspension points. There are two
approaches:
1. **Stackful coroutines** (Go goroutines) — separate stack per coroutine
2. **Stackless coroutines** (LLVM coro) — compiler splits function into state machine

LLVM's coroutine intrinsics are the production-grade solution. Both Swift and
C++20 coroutines use them. Zig has its own async model (being reworked).

### CIR Plan: LLVM Coroutines

```mlir
// Mark function as async
func.func @fetch() -> !cir.async<string>
    attributes { cir.async = true }

// Suspension point
%token = cir.async_suspend

// Resume (called by runtime scheduler)
cir.async_resume %token

// Await (caller side — suspends until result ready)
%result = cir.await @fetch() : string
```

**Lowering:** A `CIRToCoroutine` pass inserts LLVM coroutine intrinsics:
- `llvm.coro.id` at function entry
- `llvm.coro.begin` to allocate frame
- `llvm.coro.suspend` at each suspension point
- `llvm.coro.end` at function exit
- LLVM's `CoroSplit` pass then splits the function

Reference:
- LLVM coroutine intrinsics documentation
- `~/claude/references/swift/lib/IRGen/GenCoroutine.cpp` (Swift's coroutine lowering)

---

## 6. ARC Memory Management

### Why Swift's Approach Wins (Lattner Designed It)

Swift's ARC (Automatic Reference Counting) is the alternative to garbage collection:
- Every heap object has a reference count
- `retain` increments, `release` decrements
- When count reaches 0, object is freed
- Compiler inserts retain/release automatically
- Optimization passes remove redundant pairs

ARC is strictly better than GC for:
- Deterministic destruction (no GC pauses)
- Lower memory overhead (no GC metadata)
- Predictable performance (no stop-the-world)

### CIR Plan: Swift ARC Ops

```mlir
// Heap allocate with reference count
%obj = cir_arc.alloc !cir.struct<"Widget"> : !cir.ptr

// Reference counting
cir_arc.retain %obj : !cir.ptr
cir_arc.release %obj : !cir.ptr

// Weak reference (doesn't prevent deallocation)
%weak = cir_arc.weak_retain %obj : !cir.ptr
%strong = cir_arc.weak_to_strong %weak : !cir.ptr  // may return null

// Move (transfer ownership without retain/release)
%moved = cir_arc.move %obj : !cir.ptr
```

**Passes:**
- `ARCInsertion` — insert retain/release around value uses
- `ARCOptimization` — remove redundant retain/release pairs
- `ARCCodeMotion` — move retain/release for better codegen

Reference:
- `~/claude/references/swift/lib/SILOptimizer/ARC/` (entire directory)
- `~/claude/references/swift/include/swift/SIL/SILInstruction.h` (strong_retain, strong_release)

---

## 7. Implementation Order & Dependencies

```
Phase 7a: Monomorphized generics
  └── Frontend resolves generic types (no new CIR ops)
  └── Depends on: nothing new

Phase 7b: Traits/Protocols (static dispatch)
  └── Monomorphize trait methods (no new CIR ops)
  └── Depends on: Phase 7a

Phase 7c: Traits/Protocols (dynamic dispatch)
  └── NEW: witness_table type, witness_method op, existential type+ops
  └── Depends on: Phase 7b (need static dispatch working first)

Phase 7d: Classes + VTables
  └── NEW: class_alloc, class_method, upcast, downcast ops
  └── Depends on: struct infrastructure (done), indirect calls

Phase 8a: Closures
  └── NEW: closure_env type, partial_apply, call_closure ops
  └── Depends on: indirect calls (already have func.call)

Phase 8b: ARC
  └── NEW: cir_arc dialect (retain, release, move, weak_*)
  └── Depends on: heap allocation (class_alloc or cir_arc.alloc)

Phase 9: Async
  └── NEW: async_suspend, async_resume, await ops
  └── Depends on: closures (callbacks), LLVM coroutine intrinsics
```

---

## 8. Production Readiness Checklist

Before releasing CIR 1.0, these must be true:

- [ ] All CIR ops have verifiers that catch invalid IR
- [ ] All CIR ops have MemoryEffect traits where applicable
- [ ] All lowering patterns have notifyMatchFailure error handling
- [ ] Full type conversion coverage (no unrealized_conversion_cast at runtime)
- [ ] ABI correctness for struct passing (tested against C calling convention)
- [ ] Test coverage for every CIR op in all applicable frontends
- [ ] Kitchen sink integration test for each frontend
- [ ] Negative tests for error paths (type mismatch, undefined vars, etc.)
- [ ] Performance: compile time comparable to Zig (not 10x slower)
- [ ] Documentation: FRONTEND.md for new frontend authors
- [ ] No TODO or stub ops — every op fully functional

---

## 9. What Makes This Architecture Not Laughable

1. **It's Lattner's architecture.** MLIR is Lattner. SIL is Lattner. CIR follows both.
   The progressive lowering pipeline is proven across LLVM, Swift, and MLIR itself.

2. **Every feature traces to a production compiler.** Nothing is invented. Witness
   tables come from Swift (shipping on 2 billion devices). Monomorphization comes
   from Zig (production compiler). Coroutines come from LLVM (C++20 standard).

3. **The type system is sound.** CIR types are MLIR types with verifiers. Every op
   checks its inputs. The type converter handles every custom type. No runtime type
   confusion possible.

4. **Three frontends prove universality.** CIR isn't designed for one language — it
   compiles Zig, TypeScript, AND ac. This proves the IR is genuinely universal, not
   a language-specific hack.

5. **It's upstreamable.** CIR follows LLVM/MLIR coding standards. It could be proposed
   as an MLIR dialect. This is the bar for "not laughable."
