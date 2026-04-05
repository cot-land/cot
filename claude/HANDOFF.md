# Handoff — COT Compiler Toolkit

**Date:** 2026-04-05 (Phase 6 COMPLETE — enums, switch/match, tagged unions. 4 frontends.)

---

## What COT Is

A compiler toolkit built on MLIR/LLVM. CIR (Cot Intermediate Representation) is a universal IR that any language frontend can target. Passes transform CIR. LLVM produces native/wasm. Think: the layer above MLIR that Lattner designed MLIR to enable.

**ac (agentic cot)** is our dogfood language — syntax designed by AI agents. **libzc** (Zig), **libtc** (TypeScript), and **libsc** (Swift) are reference language frontends proving CIR is truly universal.

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

**Total: 153 lit + 26 inline files + 1 gate + 4 build = 184 test targets, all passing.**

---

## CIR Ops (59 ops, 9 custom types)

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
| `cir.array_to_slice` | array range → slice | GEP + sub + struct |
| `cir.none` | null optional constant | undef + insertvalue(false, [1]) |
| `cir.wrap_optional` | wrap T → ?T | undef + insertvalue(val, [0]) + insertvalue(true, [1]) |
| `cir.is_non_null` | test ?T → i1 | extractvalue [1] or icmp ne null |
| `cir.optional_payload` | extract T from ?T | extractvalue [0] or identity |

| `cir.wrap_result` | wrap T → E!T (success, error_code=0) | undef + insertvalue {val, i16 0} |
| `cir.wrap_error` | wrap i16 → E!T (error, payload=undef) | undef + insertvalue {code} |
| `cir.is_error` | test E!T → i1 | extractvalue [1] + icmp ne 0 |
| `cir.error_payload` | extract T from E!T (unchecked) | extractvalue [0] |
| `cir.error_code` | extract i16 error code from E!T | extractvalue [1] |

**Types:** `!cir.ptr` (opaque pointer), `!cir.ref<T>` (typed safe reference), `!cir.struct<"Name", fields...>`, `!cir.array<N x T>`, `!cir.slice<T>` (fat pointer {ptr, len}), `!cir.optional<T>` (nullable value), `!cir.error_union<T>` (success value or error code)

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

1. **CLAUDE.md** — Rules + 12-step feature checklist. READ THIS FIRST.
2. **claude/ADVANCED_ARCHITECTURE.md** — Phase 7+ plan: generics, classes, closures, ARC, async.
2b. **claude/PHASE6_DESIGN.md** — Phase 6 design (complete): enums, tagged unions, match/switch.
2c. **claude/PHASE5_DESIGN.md** — Phase 5 design (complete): optionals, error unions, exceptions.
3. **claude/ARCHITECTURE.md** — Design, CIR ops, Sema pass, Swift type philosophy, pass pipeline.
4. **claude/REFERENCES.md** — Which reference to study for each component.
5. **claude/FEATURES.md** — 80 features with Zig syntax column. Implementation order.
6. **claude/DISTRIBUTION_DESIGN.md** — CMake super-build, C API, pass plugin design (Phase A+B done).
7. **claude/AUDIT.md** — Round 6 compliance findings, open issues.

---

## What's Done

**Phase 1 (10/10):** Integer constants, arithmetic, functions, calls, div/mod, booleans, comparisons, negation, bitwise, shifts.

**Phase 2 (10/10):** Let/var bindings, assignment, compound assignment, if/else statement, if/else expression (select), while loop, break/continue, for loop, nested calls.

**Phase 4 (10/10 — COMPLETE):**
- ✓ #031 Pointer type — `!cir.ref<T>` typed safe reference (non-null, known pointee). Dual pointer design: `!cir.ref<T>` (safe) + `!cir.ptr` (raw). Both lower to `!llvm.ptr`. ac `*T`, Zig `*T`. See `claude/PHASE4_DESIGN.md`.
- ✓ #032 Address-of — `&x` → `cir.addr_of` (alloca `!cir.ptr` → `!cir.ref<T>`). Identity lowering.
- ✓ #033 Dereference — `*p` → `cir.deref` (`!cir.ref<T>` → T). Lowers to `llvm.load`.
- ✓ #034 Pointer field access + auto-deref — `p.x` where `p: *Point` auto-inserts `cir.deref` before `cir.field_val`. Zig/Rust/Go pattern. Also works on method calls.
- ✓ #035-036 String type + literal — `!cir.slice<T>` fat pointer type `{ptr, len}`. `string` = `!cir.slice<i8>`. `"hello"` → `cir.string_constant` → `llvm.mlir.global` + `llvm.mlir.addressof` + `{ptr, len}` struct. All 3 frontends: ac `string`/"hello", Zig `[]const u8`/"hello", TS `string`/"hello".
- ✓ #037-038 Slice ops — `cir.slice_len` (extractvalue [1]), `cir.slice_ptr` (extractvalue [0]), `cir.slice_elem` (extractvalue + GEP + load). All 3 frontends: `s.len`, `s.ptr`, `s[i]`. Runtime verified: string length, element access.
- ✓ #039 Array-to-slice — `cir.array_to_slice` (`arr[lo..hi]`). Lowers to GEP(start) + sub(len) + struct. ac syntax with `..` range. Runtime verified: length, element access, function params.
- ✓ #040 Slice type syntax — ac `[]T` in params/returns/locals. Zig `[]const u8` already handled. `!cir.slice<T>` type resolves from frontend syntax.

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

**Phase 5 (8/8 — COMPLETE):**
- ✓ #041 Optional type — `!cir.optional<T>` with null-pointer optimization for `?*T`. Non-pointer: `!llvm.struct<(T, i1)>`. Pointer: `!llvm.ptr` (null = none).
- ✓ #042 Optional wrap — `cir.wrap_optional` (T → ?T). Auto-wrap on assignment to optional vars.
- ✓ #043 Null literal — `cir.none`. ac `null`, Zig `null`, TS `null`.
- ✓ #044 If-unwrap — `if x |val| { use(val) }`. Desugars to `cir.is_non_null` + `cir.condbr` + `cir.optional_payload` in then-block. Captured variable scoped to then-block. Runtime verified: unwrap Some, unwrap None, if-else both branches.
- ✓ #045 Error union type — `!cir.error_union<T>` with i16 error code. Lowers to `!llvm.struct<(T, i16)>`. Error code 0 = success. All 3 frontends: ac `!i32`, Zig `E!i32`, TS `number | Error`.
- ✓ #046 Try expression — `try foo()` unwraps or propagates. Desugars to `cir.is_error` + `cir.condbr` + `cir.error_payload` (success) / `cir.error_code` + `cir.wrap_error` + return (error). ac and Zig `try`, TS via try/catch blocks.
- ✓ #047 Catch expression — `foo() catch |e| { handler }`. Desugars to `cir.is_error` + `cir.condbr` + handler (error) / `cir.error_payload` (success). Merge via block argument (phi). ac and Zig `catch`, TS via catch clause.
- ✓ #048 Error set declaration — Frontend assigns i16 codes. ac `error(N)`, Zig `error { Name }` + `error.Name`, TS `throw N`.

**Phase 5c — Exception-Based Error Handling (3 ops):**
- ✓ `cir.throw` — throw exception value. ac `throw expr`, TS `throw expr`. Phase 1 lowers to trap+unreachable.
- ✓ `cir.invoke` — call with normal/unwind successors. Phase 1 lowers to regular call+br.
- ✓ `cir.landingpad` — catch exception in unwind block. Phase 1 lowers to undef (unreachable).
- Phase 2 will add full C++ ABI: `__cxa_throw`/`__cxa_begin_catch`, personality functions, real stack unwinding.

---

## What To Do Next

### Phase 6 COMPLETE — Start Phase 7 (Generics and Traits)

**Phase 6 delivered:** 6 features (#049-054), 4 new CIR ops, 2 new types.
- ✓ #049-050 Enum type + value — `!cir.enum`, `cir.enum_constant`, `cir.enum_value`
- ✓ #051 Switch/match statement — `cir.switch` (integer multi-way branch)
- ✓ #052 Switch/match expression — value-producing switch with block argument phi
- ✓ #053-054 Tagged union — `!cir.tagged_union`, `cir.union_init`, `cir.union_tag`, `cir.union_payload`

**Also completed this session:**
- Phase 5b-c: Error unions + exceptions (8 new CIR ops)
- libsc: Swift frontend (4th language, 29 lit tests)
- DX: Source locations, MLIR debug flags, Sema diagnostics, negative tests
- Architecture docs: Advanced plan, construct master list, DX design, library architecture

**Read `claude/ADVANCED_ARCHITECTURE.md`** for Phase 7+ plans.

**Next: Phase 7 (Generics and Traits)**
- #055 Generic function — monomorphized (Zig comptime pattern)
- #056 Generic struct — monomorphized
- #057-060 Traits/protocols — static dispatch first, then witness tables

**4 frontends:** ac (C++), Zig (Zig), TypeScript (Go), Swift (Swift). All stay in sync.

### Distribution & Plugin Architecture — IMPLEMENTED

**See `claude/DISTRIBUTION_DESIGN.md`** for full design. Phase A (CMake super-build) and Phase B (C API) are done. Phase C (pass plugins) is partial — `--load-pass-plugin` flag works, full pipeline integration pending.

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
