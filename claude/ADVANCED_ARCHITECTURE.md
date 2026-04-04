# CIR Advanced Architecture — Planning for Phases 7-12

**Date:** 2026-04-05
**Purpose:** Get the hard features right the first time by studying reference compilers BEFORE implementing. This document plans the CIR types, ops, and passes needed for generics, classes, closures, and dynamic dispatch.

**Rule:** Study reference, then port. Never invent. This document IS the study.

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

## 1. Generic Functions & Monomorphization

### The Problem

```
fn max<T>(a: T, b: T) -> T { if a > b { a } else { b } }
max(1, 2)       // needs max_i32
max(3.14, 2.71) // needs max_f64
```

The compiler must generate separate `max_i32` and `max_f64` functions. This is monomorphization.

### Reference Architecture

**Rust (canonical):** `Instance<'tcx> { def: InstanceKind, args: GenericArgsRef }`
- Every concrete use of a generic produces an `Instance`
- A monomorphization collector pass discovers all reachable instances
- Source: `rustc_middle/src/ty/instance.rs`, `rustc_monomorphize/src/collector.rs`

**Zig:** `FuncInstance { generic_owner, ty }` in InternPool
- Comptime evaluation drives instantiation — when a comptime param is resolved, a new function instance is created
- Source: `InternPool.zig` line 4268

### CIR Plan

**Phase 7a: Representation**

No new CIR ops needed for the IR itself. Generic functions are represented as regular `func.func` with type parameters as attributes:

```mlir
// Generic definition (not emitted to LLVM — template only)
func.func @max(%a: !generic.T, %b: !generic.T) -> !generic.T
    attributes { cir.generic_params = ["T"] }

// Monomorphized instance (emitted to LLVM)
func.func @max_i32(%a: i32, %b: i32) -> i32 { ... }
func.func @max_f64(%a: f64, %b: f64) -> f64 { ... }
```

**Phase 7b: Monomorphization Pass**

New MLIR pass: `MonomorphizePass`
1. Scan all `func.call` ops in the module
2. For each call to a generic function, collect the concrete type arguments
3. Clone the generic function body, substituting type parameters
4. Replace the call with a call to the monomorphized instance
5. Remove the generic template (or keep for further instantiation)

Reference: Rust's `collector.rs` algorithm — discover roots, traverse calls, collect instances.

**What this avoids:** We do NOT need generic types in CIR's type system. MLIR's type system doesn't support type variables well. Instead, generics exist only at the frontend level. By the time CIR is emitted, all generics are resolved to concrete types. The monomorphization pass handles the cloning.

This is exactly Zig's approach — comptime resolves everything before AIR emission.

---

## 2. Traits / Interfaces / Protocols

### The Problem

```
trait Printable { fn print(self) }
impl Printable for Point { fn print(self) { ... } }

fn show(x: dyn Printable) { x.print() }  // dynamic dispatch
fn show<T: Printable>(x: T) { x.print() }  // static dispatch (monomorphized)
```

### Reference Architecture

**Swift (most sophisticated):** Witness tables + existential containers
- `SILWitnessTable` maps protocol requirements → concrete implementations
- `witness_method` instruction looks up a method through the witness table
- Existential containers hold `value + type_metadata + witness_table_ptr`
- Source: `SILWitnessTable.h`, `SILInstruction.h`

**Rust:** Trait objects use vtables
- `VtblEntry { MetadataDropInPlace, MetadataSize, MetadataAlign, Method(Instance), TraitVPtr }`
- Source: `rustc_middle/src/ty/vtable.rs`

### CIR Plan

**Static dispatch (Phase 7):** No special ops needed. Monomorphization resolves all trait method calls to concrete functions. `show<Point>(p)` becomes `show_Point(p)` which calls `Point_print(p)` directly.

**Dynamic dispatch (Phase 7, later):** New CIR ops:

```mlir
// Witness table type — maps trait methods to implementations
// Created by a WitnessTableGeneration pass
!cir.witness_table<"Printable", print: @Point_print>

// Existential container — holds value + witness table pointer
!cir.existential<"Printable">  // → { ptr_to_value, ptr_to_witness_table }

// Pack a concrete value into an existential
%e = cir.init_existential %point, @Point_Printable_witness
    : !cir.struct<"Point"> to !cir.existential<"Printable">

// Dynamic method dispatch through witness table
%fn = cir.witness_method %e, "print"
    : !cir.existential<"Printable"> to () -> ()
func.call_indirect %fn(%e)

// Unpack existential to access concrete value
%val = cir.open_existential %e : !cir.existential<"Printable"> to !cir.ptr
```

**Lowering to LLVM:**
- `!cir.existential` → `!llvm.struct<(ptr, ptr)>` — {value_ptr, witness_table_ptr}
- `cir.witness_method` → GEP into witness table struct + load function pointer
- `cir.init_existential` → alloca + store value + store witness_table_ptr
- Witness tables → LLVM global constants (arrays of function pointers)

---

## 3. Classes and VTables (TypeScript)

### The Problem

```typescript
class Animal { name: string; speak(): string { return "..."; } }
class Dog extends Animal { speak(): string { return "Woof!"; } }

function makeSpeak(a: Animal) { return a.speak(); }  // virtual dispatch
```

### Reference Architecture

**Swift:** `SILVTable { Class, entries: [Entry { Method, Implementation }] }`
- `class_method` instruction for vtable dispatch
- Source: `SILVTable.h`

### CIR Plan

Classes lower to structs + vtable pointer:

```mlir
// Class layout: { vtable_ptr, ...fields }
!cir.struct<"Animal", _vtable: !cir.ptr, name: !cir.slice<i8>>

// VTable: global constant with function pointers
llvm.mlir.global constant @Animal_vtable = { @Animal_speak }
llvm.mlir.global constant @Dog_vtable = { @Dog_speak }

// Virtual method call
%vtable_ptr = cir.field_val %obj, 0  // extract vtable pointer
%vtable = cir.load %vtable_ptr       // load vtable struct
%method = cir.field_val %vtable, 0   // extract method slot
cir.call_indirect %method(%obj)      // indirect call
```

**New CIR ops for classes:**

```mlir
// Allocate class instance (heap + vtable init)
%obj = cir.class_alloc "Dog" : !cir.ptr

// Virtual method dispatch (sugar for vtable lookup + indirect call)
%result = cir.class_method %obj, "speak" : (!cir.ptr) -> !cir.slice<i8>

// Upcast (Dog → Animal) — noop at LLVM level, type change in CIR
%animal = cir.upcast %dog : !cir.class<"Dog"> to !cir.class<"Animal">

// Downcast (Animal → Dog) — runtime check
%dog = cir.downcast %animal : !cir.class<"Animal"> to !cir.class<"Dog">
```

**Lowering:** All class ops lower to struct ops + indirect calls. No new LLVM features needed.

---

## 4. Closures

### The Problem

```
fn make_adder(x: i32) -> fn(i32) -> i32 {
    return fn(y: i32) -> i32 { x + y }  // captures x
}
let add5 = make_adder(5)
add5(3)  // returns 8
```

### Reference Architecture

**Swift:** `partial_apply(fn, captured_args) → thick_function`
- Thin function = bare function pointer (no captures)
- Thick function = function pointer + context pointer
- Source: `SILInstruction.h` — PartialApplyInst, ThinToThickFunctionInst

**Rust:** Closures are anonymous structs implementing `Fn`/`FnMut`/`FnOnce` traits
- Each captured variable becomes a struct field
- Source: `rustc_middle/src/ty/closure.rs`

### CIR Plan

```mlir
// Closure environment — auto-generated struct for captures
!cir.closure_env<x: i32>  // captures x by value

// Create closure — pack function + environment
%env = cir.make_closure_env(%x) : (i32) -> !cir.closure_env<x: i32>
%closure = cir.partial_apply @adder_body, %env
    : (!cir.closure_env<x: i32>) -> !cir.closure<(i32) -> i32>

// Call closure
%result = cir.call_closure %closure(%arg) : !cir.closure<(i32) -> i32>
```

**Lowering:**
- `!cir.closure` → `!llvm.struct<(ptr, ptr)>` — {fn_ptr, env_ptr}
- `cir.make_closure_env` → alloca + store captures
- `cir.partial_apply` → create {fn_ptr, env_ptr} struct
- `cir.call_closure` → extract fn_ptr, call with env_ptr as hidden first arg

---

## 5. Async / Coroutines

### The Problem

```
async fn fetch() -> string { ... }
let result = await fetch()
```

### Reference Architecture

**LLVM coroutines:** `llvm.coro.id`, `llvm.coro.begin`, `llvm.coro.suspend`, `llvm.coro.end`
- Coroutine frame holds local variables across suspension points
- Split pass divides function into resume/destroy/cleanup functions

**Swift:** Structured concurrency with `async_let`, `TaskGroup`
**Zig:** Stackless coroutines via `@Frame`, `suspend`, `resume`

### CIR Plan

```mlir
// Async function — emits coroutine frame setup
func.func @fetch() -> !cir.async<string>
    attributes { cir.async = true }

// Suspend point
%token = cir.async_suspend

// Resume
cir.async_resume %token

// Await (caller side)
%result = cir.await @fetch() : string
```

**Lowering:** Maps to LLVM coroutine intrinsics. The `cir.async` attribute triggers a pass that inserts `coro.id`/`coro.begin`/`coro.suspend` calls and splits the function.

---

## 6. What Must Be Built Per Phase

| Phase | New Types | New Ops | New Passes | Reference |
|-------|-----------|---------|------------|-----------|
| 7 (generics) | None (monomorphize before CIR) | None | MonomorphizePass | Rust collector.rs |
| 7 (traits static) | None | None | (resolved during monomorphization) | Zig comptime |
| 7 (traits dynamic) | `!cir.witness_table`, `!cir.existential` | `witness_method`, `init/open_existential` | WitnessTableGeneration | Swift SIL |
| 7b (classes) | `!cir.class` (sugar for struct+vtable) | `class_alloc`, `class_method`, `upcast`, `downcast` | VTableGeneration | Swift SILVTable |
| 8 (closures) | `!cir.closure_env`, `!cir.closure` | `make_closure_env`, `partial_apply`, `call_closure` | ClosureSpecialization | Swift partial_apply |
| 8 (ARC) | None (use existing ptr) | `cir_arc.retain/release/move` | ARCOptimization | Swift ARC passes |
| 9 (async) | `!cir.async<T>` | `async_suspend`, `async_resume`, `await` | CoroutineSplit | LLVM coroutines |

---

## 7. Key Architectural Decision: When Do Generics Resolve?

**Option A (Zig pattern):** Resolve ALL generics in the frontend. CIR never sees generic types.
- Pro: CIR stays simple. No type variables in the IR.
- Con: Frontend must handle all monomorphization. Large frontend.

**Option B (Rust pattern):** Emit generic CIR, resolve in a pass.
- Pro: Frontend is simpler. Pass can optimize across instances.
- Con: CIR type system must support type variables. Complex pass.

**Option C (Swift pattern):** Emit generic SIL, specialize in passes, lower remaining generics to runtime dispatch.
- Pro: Best optimization opportunities. Supports both static and dynamic dispatch.
- Con: Most complex. Requires existential containers and witness tables.

**Recommendation for CIR: Option A for Phase 7, evolve to Option C.**

Start with Zig-style frontend resolution. This means:
- Frontends resolve generics before emitting CIR
- CIR never contains type variables
- MonomorphizePass is simple: just verify all types are concrete
- Later (Phase 7+): add existential types and witness tables for dynamic dispatch

This matches CLAUDE.md's "start minimal" rule. Get monomorphized generics working first. Add dynamic dispatch later.

---

## 8. Files to Study Before Implementation

| Feature | Primary Reference | File |
|---------|------------------|------|
| Monomorphization | Rust collector | `~/claude/references/rust/compiler/rustc_monomorphize/src/collector.rs` |
| Instance types | Rust Instance | `~/claude/references/rust/compiler/rustc_middle/src/ty/instance.rs` |
| Witness tables | Swift SIL | `~/claude/references/swift/include/swift/SIL/SILWitnessTable.h` |
| VTable layout | Swift SIL | `~/claude/references/swift/include/swift/SIL/SILVTable.h` |
| Existential containers | Swift SIL | `~/claude/references/swift/include/swift/SIL/SILInstruction.h` (lines 7120+) |
| Closures (Rust) | Closure types | `~/claude/references/rust/compiler/rustc_middle/src/ty/closure.rs` |
| Closures (Swift) | PartialApply | `~/claude/references/swift/include/swift/SIL/SILInstruction.h` |
| Coroutines | LLVM | `~/claude/references/llvm-project/llvm/include/llvm/IR/Intrinsics.td` (coro.*) |
| VTable entries | Rust vtable | `~/claude/references/rust/compiler/rustc_middle/src/ty/vtable.rs` |
| Comptime | Zig Sema | `~/claude/references/zig/src/Sema.zig` (comptime blocks) |
