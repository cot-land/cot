# COT — Compiler Toolkit Architecture

**Date:** 2026-04-03

---

## What COT Is

COT is a compiler platform. Frontends for any language produce CIR (Cot Intermediate Representation). COT transforms CIR through passes and produces native binaries or WebAssembly via LLVM.

```
Any Frontend  →  CIR  →  COT passes  →  LLVM  →  native / wasm
```

CIR is built on MLIR. A CIR module IS an MLIR module. CIR bytecode IS MLIR bytecode. Standard MLIR tools work on CIR files.

---

## CIR — The Universal IR

### Type Philosophy: Builtins vs Language Types (from Swift)

Chris Lattner's proudest Swift design decision: `Int`, `Float`, `Bool`, `String`
are NOT compiler builtins — they're stdlib structs wrapping a small set of
compiler-known primitives (`Builtin.Int64`, `Builtin.FPIEEE32`, etc.). This means:
- Users can define types as powerful as `Int` (same protocols, same optimization)
- The compiler stays small (only knows ~50 builtin types)
- SIL passes never reference stdlib types — only builtins

**CIR adopts this principle:**

| Layer | What it knows | Example |
|-------|---------------|---------|
| **CIR ops** | MLIR primitive types only | `IntegerType(32)`, `Float32Type`, `!cir.ptr` |
| **Frontends** | Language-level type names | ac `i32`, Zig `i32`, future `Int` |
| **Sema pass** | Maps language types → MLIR types | `i32` → `IntegerType(32)` |
| **CIR passes** | MLIR types only — never language names | ARC, optimization see `i32` not `ac::i32` |
| **Lowering** | MLIR → LLVM type conversion | `IntegerType(32)` → `LLVM::IntegerType(32)` |

MLIR's built-in `IntegerType(N)` and `FloatType` ARE our builtins — equivalent
to Swift's `Builtin.Int64` and `Builtin.FPIEEE32`. CIR ops work on these
directly. Language-level types (when we add structs, enums, traits) are
user-defined types that frontends construct and Sema resolves.

**Rule: CIR passes must never hardcode language-specific type names.**
If a pass needs to know about "strings" or "arrays", it should work with
the CIR type (`!cir.array`, `!cir.struct`) not the language name.

Reference: Swift stdlib (`~/claude/references/swift/stdlib/public/core/`),
SIL type lowering (`~/claude/references/swift/lib/SIL/IR/SILType.cpp`).

### Core Ops

CIR captures what every compiler IR has in common. We audited five reference compilers:

| | Zig (ZIR) | Swift (SIL) | Rust (MIR) | Go (SSA) | TypeScript |
|---|---|---|---|---|---|
| Lines | ~6K | ~30K | ~15K | ~20K | N/A (AST) |
| Typed? | No | Yes | Yes | Yes | Erased |
| Form | Sequential | SSA+CFG | CFG | SSA+CFG | AST |

### Core Ops (~60)

These exist in every compiler IR we studied:

**Arithmetic** (all four IRs have these)
```
cir.add, cir.sub, cir.mul, cir.div, cir.rem
cir.add_wrap, cir.sub_wrap, cir.mul_wrap    (wrapping variants)
cir.shl, cir.shr                             (shifts)
cir.bit_and, cir.bit_or, cir.xor, cir.bit_not
cir.neg
```

**Comparison** (all four)
```
cir.cmp_eq, cir.cmp_ne
cir.cmp_lt, cir.cmp_le, cir.cmp_gt, cir.cmp_ge
```

**Control Flow** (all four use basic blocks + terminators)
```
cir.func          function declaration
cir.block         basic block / labeled block
cir.br            unconditional branch
cir.condbr        conditional branch (condition, true_block, false_block)
cir.switch        multi-way branch
cir.ret           return from function
cir.call          direct function call
cir.call_indirect indirect function call (closures, vtables)
cir.unreachable   unreachable code marker
```

**Memory** (all four)
```
cir.alloc         stack allocation (Zig alloc, Swift alloc_stack, Rust StorageLive, Go LocalAddr)
cir.load          load from address (all four)
cir.store         store to address (all four)
cir.field_ptr     struct field address (Zig field_ptr, Rust Place projection, Go StructSelect addr)
cir.field_val     struct field value (Swift struct_extract, Rust Field projection, Go StructSelect)
cir.elem_ptr      array element address (all four)
cir.elem_val      array element value (all four)
cir.ref           address-of (&x)
cir.deref         dereference (*p)
```

**Constants**
```
cir.const_int     integer literal
cir.const_float   float literal
cir.const_bool    boolean literal
cir.const_string  string literal
cir.const_null    null/nil/undefined
```

**Aggregates** (all four)
```
cir.struct_init   construct struct value
cir.array_init    construct array value
cir.tuple_init    construct tuple value
```

**Type Casts** (separate ops per direction — Arith dialect pattern)
```
cir.extsi         sign-extend integer (i32 → i64)
cir.extui         zero-extend integer (u32 → u64)
cir.trunci        truncate integer (i64 → i32)
cir.sitofp        signed int → float
cir.fptosi        float → signed int
cir.extf          extend float (f32 → f64)
cir.truncf        truncate float (f64 → f32)
cir.bitcast       reinterpret bits
```
NOT a single cir.cast mega-op. Each op maps 1:1 to one LLVM op.
Frontends emit the specific cast they need; Sema inserts casts at
type boundaries (e.g., i32 argument to i64 parameter).
Reference: mlir/Dialect/Arith/IR/ArithOps.td cast hierarchy.

### Frontend Ops (~40)

Emitted by frontends, consumed by passes. Not all frontends emit all of these.

**Declarations** (frontends declare, passes resolve)
```
cir.param         function parameter with type reference
cir.ret_type      return type annotation
cir.decl          variable/constant declaration
cir.type_ref      reference to a named type (unresolved until type resolution pass)
```

**Type Construction** (frontends describe types, passes resolve)
```
cir.int_type      integer type (sign + bits)
cir.float_type    float type (bits)
cir.ptr_type      pointer type (pointee + qualifiers)
cir.array_type    array type (element + length)
cir.slice_type    slice type (element)
cir.optional_type optional type (?T)
cir.error_union   error union type (E!T)
cir.fn_type       function type (params + return)
cir.struct_type   struct type declaration
cir.enum_type     enum type declaration
cir.union_type    union type declaration
```

**Error Handling** (Zig, Rust, Swift all have error-like constructs)
```
cir.try           try expression (unwrap or propagate error)
cir.err_payload   extract payload from error union
cir.err_code      extract error code from error union
```

**Comptime / Const Evaluation**
```
cir.comptime_block    block to evaluate at compile time
cir.comptime_val      compile-time known value
```

### Pass-Injected Ops

These don't come from frontends. Passes introduce them during transformation.

**ARC (from Swift — injected by ARCInsertion pass)**
```
cir.arc_retain    increment reference count
cir.arc_release   decrement reference count, dealloc if zero
cir.arc_alloc     allocate heap object with refcount header
cir.arc_dealloc   free heap object
cir.arc_is_unique check refcount == 1
cir.arc_move      transfer ownership without retain/release
```

**Concurrency (from Swift — injected by ConcurrencyLower pass)**
```
cir.async_suspend   suspend coroutine
cir.async_resume    resume coroutine
cir.task_spawn      spawn child task
cir.task_await      await task result
cir.channel_send    send to channel
cir.channel_recv    receive from channel
```

**Safety (injected by safety passes)**
```
cir.bounds_check    array bounds check
cir.null_check      null pointer check
cir.overflow_check  arithmetic overflow check
```

---

## Pass Pipeline

```
CIR (from frontend — unresolved types at call boundaries)
  │
  ├─ Sema                  validate types, insert casts, resolve fields  [Phase 3]
  ├─ ComptimeEval          evaluate cir.comptime_block → constants       [Phase 10]
  ├─ GenericInstantiation   monomorphize generic functions                [Phase 7]
  ├─ TraitResolution       resolve trait impls → concrete dispatch       [Phase 7]
  ├─ ARCInsertion          insert cir.arc_retain / cir.arc_release      [Phase 8]
  ├─ ARCOptimization       eliminate redundant retain/release pairs      [Phase 8]
  ├─ ConcurrencyLower      lower cir.async_* → coroutine ops            [Phase 9]
  │
  └─ LLVMLowering          cir.* → func.* + llvm.* (MLIR LLVM dialect)  [Phase 1 ✓]
         │
         ▼
   LLVM IR → native binary or .wasm
```

Passes are in `libcot/`. Transformation passes (CIR→CIR) are separate from
lowering passes (CIR→LLVM). Reference: Flang splits `lib/Optimizer/Transforms/`
from `lib/Optimizer/CodeGen/`.

```
libcot/
  lib/
    Transforms/              CIR → CIR passes (semantic analysis, optimization)
      SemanticAnalysis.cpp   Sema pass — type checking, cast insertion, field resolution
    CIRToLLVM/               CIR → LLVM lowering (conversion patterns)
      CIRToLLVM.cpp          Pass definition + pipeline
      ArithmeticPatterns.cpp
      BitwisePatterns.cpp
      MemoryPatterns.cpp
      ControlFlowPatterns.cpp
```

### Sema Pass Design

The Sema pass is a **manual walk pass** (not pattern-based). It runs per-function
(`OperationPass<func::FuncOp>`), walks operations in post-order, and maintains
context across the walk.

Reference: Zig Sema (`~/claude/references/zig/src/Sema.zig`) — transforms ZIR
(untyped) → AIR (typed) via sequential instruction dispatch. Also informed by
Flang's `lib/Optimizer/Transforms/` pass organization.

**What Sema does (Phase 3):**
1. **Build symbol table** from module — function signatures, struct type definitions
2. **Validate call argument types** — check actual types match callee's parameter types
3. **Insert cast ops** at type boundaries — e.g., `cir.extsi` when passing i32 to i64 param
4. **Resolve struct field access** — validate field exists, determine result type
5. **Report semantic errors** with source locations

**Why manual walk, not patterns:**
- Patterns (greedy rewrite) don't maintain context across operations
- Sema needs a symbol table that persists across the walk
- Type resolution has ordering dependencies (resolve operands before uses)
- Validation is a constraint check, not a rewrite
- Reference: MLIR canonicalizer uses patterns; Zig Sema uses sequential dispatch

**Why NOT in the frontend:**
- Frontends should emit unresolved CIR and let the pass pipeline handle the rest
- This matches Lattner's progressive lowering — each pass does one job
- Multiple frontends (ac, Zig) share the same Sema pass — no duplication
- The pass is testable in isolation (feed it CIR, check output CIR)

| Pass | Reference | Source | Status |
|------|-----------|--------|--------|
| Sema | Zig Sema + Flang Transforms | `~/claude/references/zig/src/Sema.zig` | Phase 3 |
| ComptimeEval | Zig comptime interpreter | `~/claude/references/zig/src/Sema.zig` | Phase 10 |
| GenericInstantiation | Zig + Rust monomorphization | `~/claude/references/rust/compiler/rustc_monomorphize/` | Phase 7 |
| TraitResolution | Rust trait dispatch | `~/claude/references/rust/compiler/rustc_hir_analysis/` | Phase 7 |
| ARCInsertion | Swift SILOptimizer/ARC | `~/claude/references/swift/lib/SILOptimizer/ARC/` | Phase 8 |
| ARCOptimization | Swift bidirectional dataflow | `~/claude/references/swift/lib/SILOptimizer/ARC/` | Phase 8 |
| ConcurrencyLower | Swift async transform | `~/claude/references/swift/lib/SILOptimizer/Mandatory/` | Phase 9 |
| LLVMLowering | MLIR conversion patterns | `~/claude/references/llvm-project/mlir/lib/Conversion/` | ✓ |

---

## Targets

LLVM handles all targets. COT sets the target triple on the MLIR module.

| Target | Triple | Linker |
|--------|--------|--------|
| macOS ARM64 | `aarch64-apple-darwin` | system `cc` |
| macOS x86_64 | `x86_64-apple-darwin` | system `cc` |
| Linux ARM64 | `aarch64-unknown-linux-gnu` | system `cc` |
| Linux x86_64 | `x86_64-unknown-linux-gnu` | system `cc` |
| WebAssembly | `wasm32-unknown-unknown` | `wasm-ld` |
| WASI | `wasm32-wasi` | `wasm-ld` |

Same MLIR → LLVM IR → TargetMachine pipeline for all targets.

---

## Project Structure

```
~/cot-land/cot/
  libcir/        CIR MLIR dialect definition (C++ / TableGen)
  libcot/        Compiler passes (C++ MLIR passes) — CIRToLLVM lowering
  libac/         ac (agentic cot) frontend (C++) — agent-designed syntax, dogfoods CIR
  libzc/         Zig frontend (Zig) — uses std.zig.Ast parser, C ABI or bytecode
  libts/         TypeScript frontend [planned]
  cot/           CLI driver (C++)
  test/          Build tests (exit-code based) + inline tests (Zig pattern)
  claude/        Internal docs
```

## Frontends

Three frontends prove CIR is language-agnostic. Same CIR ops, same backend, different syntax:

```
libac/   ac:   fn add(a: i32, b: i32) -> i32 { return a + b }
libzc/   zig:  pub fn add(a: i32, b: i32) i32 { return a + b; }
libts/   ts:   function add(a: number, b: number): number { return a + b }
                    ↓               ↓               ↓
               same CIR ops → same lowering → same binary
```

**ac (agentic cot)** — syntax designed by AI agents. Uses the patterns LLMs predict most naturally. C++ frontend, exercises every CIR feature first.

**libzc** — Zig frontend in Zig. Uses `std.zig.Ast` parser (battle-tested). Two modes:
1. C ABI link — `cot` links `libzc.a`, calls `zc_parse()` directly
2. Bytecode file — `zc` CLI writes `.cir` file, `cot` reads it

**libts** — TypeScript frontend (planned). Proves CIR handles structural typing, type erasure → reification, etc.

Each feature we add to CIR gets a test in all active frontends.

**Language boundaries:**
- C++ for anything that touches MLIR/LLVM (dialect, passes, driver, ac frontend)
- Zig for the Zig frontend (uses Zig's std parser)
- Any language for any frontend (via CIR C API or bytecode file)
- C ABI is the bridge between languages

---

## Frontend Contract

A frontend produces CIR by either:

1. **C API** — call `cir_*` functions to build an MLIR module in memory, serialize to bytecode
2. **Bytecode file** — write `.cir` file (MLIR bytecode format), COT reads it

The frontend is responsible for:
- Parsing source language
- Mapping source constructs to CIR ops
- Emitting type annotations (cir.param, cir.ret_type, cir.type_ref)
- Emitting debug info (cir.dbg_stmt, source locations)

The frontend is NOT responsible for:
- Type checking (TypeResolution pass does this)
- Generic instantiation (GenericInstantiation pass)
- Memory management (ARCInsertion pass)
- Optimization (LLVM handles this)

---

## Rules

1. **CIR is MLIR.** No custom binary format. Standard MLIR tools work.
2. **Best-of-breed passes.** Every pass comes from a reference compiler. Read the source before writing.
3. **One backend — LLVM.** All targets go through MLIR LLVM dialect.
4. **No stubs, no TODOs.** Every function works or doesn't exist yet.
5. **Start minimal.** Get one function compiling end-to-end before adding features.
6. **C ABI is the bridge.** Zig for frontends, C++ for passes. They talk through C.

---

## Gate Tests (in order)

1. `fn add(a: i32, b: i32) i32 { return a + b; }` → native binary, returns 42
2. `fn main() void { const x = add(19, 23); }` → function calls work
3. `if (x > 0) { ... } else { ... }` → control flow works
4. `var x: i32 = 0; x = x + 1;` → mutable locals work
5. `const Point = struct { x: i32, y: i32 };` → struct types work
6. `fn add(a: i32, b: i32) i32 { return a + b; }` → compiles to .wasm
7. Hello world with stdout → system calls work

Each gate test proves a layer of the compiler. Don't move to the next until the current one works end-to-end.
