# Handoff — COT Compiler Toolkit

**Date:** 2026-04-04 (updated)

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

**Total: 55 lit + 30 inline + 1 gate + 4 build = 90 tests, all passing.**

---

## CIR Ops (29 ops, 3 custom types)

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
| `cir.br` | unconditional branch (with block args) | `llvm.br` |
| `cir.condbr` | conditional branch | `llvm.cond_br` |
| `cir.trap` | abort (assertion failure) | `llvm.trap + unreachable` |

**Types:** `!cir.ptr` (opaque pointer), `!cir.struct<"Name", fields...>`, `!cir.array<N x T>`

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
  lit/ac/        ac frontend lit tests (19)
  lit/zig/       Zig frontend lit tests (14)
  lit/ts/        TypeScript frontend lit tests (14)
  lit/lowering/  CIR→LLVM lowering tests (4)
  inline/        Runtime correctness tests (10 files, 30 tests)
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

**Phase 3 (5/10):**
- ✓ #021 Multiple int types (i8-i64, u8-u64) — all three frontends
- ✓ #022 Float types (f32, f64) — all three frontends
- ✓ #023 Type casts — ac `x as i64`, Zig `@intCast`/`@floatCast`/`@truncate`/`@floatFromInt`
- ✓ #024 Struct declaration — ac `struct Point { x: i32, y: i32 }`, Zig `const Point = struct { ... }`, TS `interface Point { x: number; y: number; }`
- ✓ #025 Struct construction — ac `Point { x: 1, y: 2 }`, Zig `Point{ .x = 1, .y = 2 }`, TS `{ x: 1, y: 2 }` → `cir.struct_init` → `llvm.insertvalue` chain
- Infrastructure: Cast ops (7, CastOpInterface + verifiers), Sema pass, `!cir.struct` with field names, alloca type conversion fix

---

## What To Do Next

### Continue Phase 3

**Next features in order:**
- #026 Struct field access — `p.x`. Need `cir.field_val` / `cir.field_ptr` ops + `llvm.extractvalue`/GEP lowering. Sema needs struct field resolution (F1).
- #027 Struct method syntax — `p.distance()`. Desugars to function call.
- #028-030 Arrays — `[4]i32`, `[1,2,3,4]`, `arr[i]`. `!cir.array` type exists.

**For each feature, follow the 12-step checklist in CLAUDE.md. ALL THREE frontends (ac, Zig, TypeScript) must stay in sync.**

### libtc Feature Parity Status
libtc has Phase 1-2 features (arithmetic, comparisons, booleans, bitwise, shifts, variables, if/else, while, for, break/continue, nested calls). Still needs:
- Phase 3: type casts (`as` in TS?), struct declarations (TS `interface`/`type`?)
- TypeScript `number` maps to i32 for now. Phase 4+ will need f64 for correctness.

### Key Architecture Decisions Already Made

1. **Cast ops:** 7 separate ops following Arith pattern (NOT a single mega-op). Each maps 1:1 to LLVM.
2. **Sema pass:** Manual walk pass in libcot/lib/Transforms/. Runs before lowering. Inserts casts at call boundaries.
3. **Type philosophy:** CIR builtins = MLIR types. Language names resolved by frontends. Passes never reference language-specific types (Swift Builtin pattern).
4. **Progressive lowering:** Frontend → CIR (unresolved) → Sema → CIR (typed) → verify → LLVM.
5. **Verification:** Sema runs with verification disabled (frontend may emit type mismatches). Verification happens after Sema.

---

## Rules (from CLAUDE.md)

1. **Study reference before writing.** Every component traces to Zig/Go/MLIR/FIR/Swift/TypeScript-Go.
2. **Never hack features.** If infrastructure is missing, build it first.
3. **All THREE frontends in sync.** Every feature works in ac AND Zig AND TypeScript.
4. **12-step feature checklist.** Study → audit → ops → lowering → ac → zig → ts → lit tests (3 frontends) → lowering test → inline test → build → docs.
5. **NEVER** git checkout/restore/reset. **NEVER** git add .
5. **NEVER** git checkout/restore/reset. **NEVER** git add .
