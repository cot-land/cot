# Handoff — COT Compiler Toolkit

**Date:** 2026-04-04 (session handoff)

---

## What COT Is

A compiler toolkit built on MLIR/LLVM. CIR (Cot Intermediate Representation) is a universal IR that any language frontend can target. Passes transform CIR. LLVM produces native/wasm. Think: the layer above MLIR that Lattner designed MLIR to enable.

**ac (agentic cot)** is our dogfood language — syntax designed by AI agents. **libzc** is a Zig frontend proving CIR is language-agnostic.

---

## What Works Right Now

```bash
make              # Build everything (libcir → libcot → libzc → cot)
make test         # Run all test layers (lit, gate, inline, build)
```

**Pipeline stages:**
```bash
./cot emit-cir file.ac     # Print CIR after Sema (typed)
./cot emit-cir file.zig    # Same for Zig
./cot emit-llvm file.ac    # Print LLVM dialect (after lowering)
./cot build file.ac -o out # Full compile to native
./cot test file.ac          # Run inline test blocks
```

**Total: 79 lit + 16 inline files + 1 gate + 4 build = 100 test targets, all passing.**

---

## CIR Ops (40 ops, 5 custom types)

| Op | Description | LLVM Lowering |
|----|-------------|---------------|
| `cir.constant` | integer/float/bool constant (ConstantLike + verifier) | `llvm.mlir.constant` |
| `cir.add/sub/mul/div/rem` | arithmetic (AnyType — int + float) | `llvm.add/sub/mul/sdiv/srem` |
| `cir.neg` | integer negation | `llvm.sub(0, x)` |
| `cir.bit_and/bit_or/xor/bit_not` | bitwise (AnyInteger) | `llvm.and/or/xor` |
| `cir.shl/shr` | shifts (AnyInteger) | `llvm.shl/lshr` |
| `cir.cmp` | comparison (CmpIPredicate enum: eq/ne/slt/sle/sgt/sge) | `llvm.icmp` |
| `cir.select` | conditional value (ternary) | `llvm.select` |
| `cir.extsi/extui/trunci` | integer casts (1:1 Arith pattern) | `llvm.sext/zext/trunc` |
| `cir.sitofp/fptosi` | int↔float casts | `llvm.sitofp/fptosi` |
| `cir.extf/truncf` | float casts | `llvm.fpext/fptrunc` |
| `cir.alloca` | stack allocation → `!cir.ptr` | `llvm.alloca` |
| `cir.store/load` | memory access | `llvm.store/load` |
| `cir.struct_init` | construct struct from field values | `llvm.mlir.undef` + `llvm.insertvalue` chain |
| `cir.field_val` | extract field value from struct | `llvm.extractvalue` |
| `cir.field_ptr` | pointer to struct field | `llvm.getelementptr` |
| `cir.br` | unconditional branch (with block args) | `llvm.br` |
| `cir.condbr` | conditional branch | `llvm.cond_br` |
| `cir.trap` | abort (assertion failure) | `llvm.trap + unreachable` |
| `cir.string_constant` | string literal → slice<i8> | `llvm.mlir.global` + addressof + struct |
| `cir.slice_ptr` | extract pointer from slice | `llvm.extractvalue [0]` |
| `cir.slice_len` | extract length from slice | `llvm.extractvalue [1]` |
| `cir.slice_elem` | index into slice (unchecked) | extractvalue + GEP + load |

**Types:** `!cir.ptr` (opaque pointer), `!cir.ref<T>` (typed safe reference), `!cir.struct<"Name", fields...>`, `!cir.array<N x T>`, `!cir.slice<T>` (fat pointer {ptr, len})

---

## Project Structure

```
libcir/          CIR MLIR dialect (C++/TableGen) — 29 ops, 3 types
  include/CIR/   CIRDialect.td, CIROps.td, CIRTypes.td, CIROps.h
  lib/           CIRDialect.cpp (types, verifiers, custom parsing)

libcot/          Compiler passes (C++)
  include/COT/   Passes.h, CIRToLLVMPatterns.h
  lib/
    Transforms/              CIR → CIR passes
      SemanticAnalysis.cpp   Sema: type check, insert casts at call boundaries
    CIRToLLVM/               CIR → LLVM lowering
      CIRToLLVM.cpp          Pass definition + type conversions
      ArithmeticPatterns.cpp  add/sub/mul/div/rem/neg/constant/cmp/select + 7 casts
      BitwisePatterns.cpp     bit_and/or/xor/not/shl/shr
      MemoryPatterns.cpp      alloca/store/load
      ControlFlowPatterns.cpp br/condbr/trap

libac/           ac frontend (C++) — Agentic-Cot, scanner/parser/codegen → CIR
libzc/           Zig frontend (Zig) — Zig-Cot, uses std.zig.Ast parser → CIR
libtc/           TypeScript frontend (Go) — TypeScript-Cot, uses TypeScript-Go parser → CIR

cot/             CLI driver (C++)
  main.cpp       Commands: build, test, emit-cir, emit-llvm, version
                 Pipeline: Sema → verify → CIRToLLVM → func-to-llvm → LLVM IR → native

test/            Test suite
  lit/ac/        ac frontend lit tests (28)
  lit/zig/       Zig frontend lit tests (22)
  lit/ts/        TypeScript frontend lit tests (18)
  lit/lowering/  CIR→LLVM lowering tests (7)
  inline/        Runtime correctness tests (15 files)
  *.ac           Build tests (exit code 42 = pass)

claude/          Internal docs
  ARCHITECTURE.md    Design + pass pipeline + Sema design + Swift type philosophy
  REFERENCES.md      Component-to-reference mapping (Zig, Go, MLIR, FIR, Swift)
  FEATURES.md        80 features, Phases 1-2 complete (20/80), Phase 3 in progress (4/10)
  AUDIT.md           3 audit rounds, scaling plan, open issues
  AC_SYNTAX.md       ac language syntax reference
```

---

## Key Documents — Read Order

1. **CLAUDE.md** — Rules + feature checklist (11 steps). READ THIS FIRST.
2. **claude/ARCHITECTURE.md** — Design, CIR ops, Sema pass, Swift type philosophy, pass pipeline.
3. **claude/REFERENCES.md** — Which reference to study for each component.
4. **claude/FEATURES.md** — 80 features with Zig syntax column. Implementation order.
5. **claude/AUDIT.md** — Compliance findings, open issues, scaling plan.

---

## What's Done

**Phase 1 (10/10):** Integer constants, arithmetic, functions, calls, div/mod, booleans, comparisons, negation, bitwise, shifts.

**Phase 2 (10/10):** Let/var bindings, assignment, compound assignment, if/else statement, if/else expression (select), while loop, break/continue, for loop, nested calls.

**Phase 4 (8/10):**
- ✓ #031 Pointer type — `!cir.ref<T>` typed safe reference (non-null, known pointee). Dual pointer design: `!cir.ref<T>` (safe) + `!cir.ptr` (raw). Both lower to `!llvm.ptr`. ac `*T`, Zig `*T`. See `claude/PHASE4_DESIGN.md`.
- ✓ #032 Address-of — `&x` → `cir.addr_of` (alloca `!cir.ptr` → `!cir.ref<T>`). Identity lowering.
- ✓ #033 Dereference — `*p` → `cir.deref` (`!cir.ref<T>` → T). Lowers to `llvm.load`.
- ✓ #034 Pointer field access + auto-deref — `p.x` where `p: *Point` auto-inserts `cir.deref` before `cir.field_val`. Zig/Rust/Go pattern. Also works on method calls.
- ✓ #035-036 String type + literal — `!cir.slice<T>` fat pointer type `{ptr, len}`. `string` = `!cir.slice<i8>`. `"hello"` → `cir.string_constant` → `llvm.mlir.global` + `llvm.mlir.addressof` + `{ptr, len}` struct. All 3 frontends: ac `string`/"hello", Zig `[]const u8`/"hello", TS `string`/"hello".
- ✓ #037-038 Slice ops — `cir.slice_len` (extractvalue [1]), `cir.slice_ptr` (extractvalue [0]), `cir.slice_elem` (extractvalue + GEP + load). All 3 frontends: `s.len`, `s.ptr`, `s[i]`. Runtime verified: string length, element access.

**Phase 3 (10/10 — COMPLETE):**
- ✓ #021 Multiple int types (i8-i64, u8-u64) — all three frontends
- ✓ #022 Float types (f32, f64) — all three frontends
- ✓ #023 Type casts — ac `x as i64`, Zig `@intCast`/`@floatCast`/`@truncate`/`@floatFromInt`
- ✓ #024 Struct declaration — ac `struct Point { x: i32, y: i32 }`, Zig `const Point = struct { ... }`, TS `interface Point { x: number; y: number; }`
- ✓ #025 Struct construction — ac `Point { x: 1, y: 2 }`, Zig `Point{ .x = 1, .y = 2 }`, TS `{ x: 1, y: 2 }` → `cir.struct_init` → `llvm.insertvalue` chain
- ✓ #026 Struct field access — `p.x` → `cir.field_val` → `llvm.extractvalue`. Also `cir.field_ptr` → `llvm.getelementptr` (for pointer-based access). Merged func-to-llvm into CIR lowering pass (shared type converter).
- ✓ #027 Struct method syntax — `p.sum()` desugars to `sum(p)` at frontend level. No new CIR ops. All 3 frontends handle method call dispatch.
- ✓ #028-030 Arrays — `[4]i32` type, `[1,2,3,4]` literal → `cir.array_init`, `arr[i]` → `cir.elem_val`/`cir.elem_ptr`. All 3 frontends: ac `[1,2,3]`, Zig `.{1,2,3}`, TS `[1,2,3]`.
- Infrastructure: Cast ops (7, CastOpInterface + verifiers), Sema pass, `!cir.struct` with field names, alloca type conversion fix

---

## What To Do Next

### Continue Phase 4 — Slice Operations (#037-040)

**Read `claude/PHASE4_DESIGN.md` first** — it has the full architectural plan.

**Next features in order:**
- #037 Slice type — `[]i32` generic slice syntax in all 3 frontends. Already have `!cir.slice<T>` type.
- #038 Slice indexing — `s[i]` → GEP on ptr field + load. Needs `cir.slice_elem` op.
- #039 Slice from array — `arr[1..3]` → build `{ptr+off, len}`. Needs `cir.array_to_slice` op.
- #040 Slice length/pointer — `s.len`, `s.ptr` → extract fields. Needs `cir.slice_len`, `cir.slice_ptr` ops.

**For each feature, follow the 12-step checklist in CLAUDE.md. ALL THREE frontends must stay in sync.**

### Distribution & Plugin Architecture

**Read `claude/DISTRIBUTION_DESIGN.md`** — full design for making libcir/libcot distributable via Homebrew, expanding the C API for cross-language frontends, and adding a pass plugin interface. Implement before Phase 5.

### Key Architecture Decisions Already Made

1. **Dual pointer types:** `!cir.ref<T>` (safe, typed, non-null) + `!cir.ptr` (raw, opaque). Both lower to `!llvm.ptr`. FIR/Zig/Rust pattern.
2. **Auto-deref:** `p.x` where `p: *Struct` auto-inserts `cir.deref`. Frontends handle this, not CIR.
3. **Compiler-as-library:** All pipeline logic in `libcot/lib/Compiler.cpp` (`COT/Compiler.h`). CLI (`cot/main.cpp`) is thin arg parsing only.
4. **Merged lowering pass:** `CIRToLLVM` includes `FuncToLLVM` patterns with shared `LLVMTypeConverter`. Single `applyFullConversion`.
5. **Cast ops:** 7 separate ops following Arith pattern. CastOpInterface on all.
6. **Sema pass:** Manual walk, cached symbol table (DenseMap), cast insertion at call boundaries.
7. **Type philosophy:** CIR builtins = MLIR types. Language names resolved by frontends. Swift Builtin pattern.
8. **Progressive lowering:** Frontend → CIR → Sema(verify=off) → verify → CIRToLLVM → LLVM IR → native.

### Audit Status

5 audit rounds completed. See `claude/AUDIT.md` for full findings. Key open issues:
- **D10:** Memory effect traits on Alloca/Store/Load (before optimization passes)
- **D12:** TrapOp NoReturn trait
- **T2:** 4 ops with zero test coverage (extui, field_ptr, elem_ptr, trap)
- **T3:** Zig/TS test parity gaps (Zig missing arithmetic, TS missing casts)

**Rule: After every substantial feature, run a full audit against MLIR/LLVM standards.**

---

## Rules (from CLAUDE.md)

1. **Study reference before writing.** Every component traces to Zig/Go/MLIR/FIR/Swift/TypeScript-Go.
2. **Never hack features.** If infrastructure is missing, build it first.
3. **All THREE frontends in sync.** Every feature works in ac AND Zig AND TypeScript.
4. **12-step feature checklist.** Study → audit → ops → lowering → ac → zig → ts → lit tests (3 frontends) → lowering test → inline test → build → docs.
5. **NEVER** git checkout/restore/reset. **NEVER** git add .
5. **NEVER** git checkout/restore/reset. **NEVER** git add .
