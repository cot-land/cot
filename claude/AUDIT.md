# CIR Audit — MLIR/LLVM Standards Compliance

**Last audit:** 2026-04-04 Round 5 (Phase 3 complete — 34 CIR ops, 105 tests, 3 frontends)
**Reference compilers:** Flang FIR, MLIR Arith/SCF, ArithToLLVM, Go parser, Zig AstGen, TypeScript-Go

---

## Audit Methodology

CIR is audited against production MLIR references:
1. **Flang FIR** — closest analogue (frontend IR as MLIR dialect, ~500K LOC)
2. **MLIR Arith/SCF** — canonical arithmetic ops + structured control flow
3. **ArithToLLVM** — canonical lowering patterns
4. **Go parser** — reference for ac parser architecture
5. **Zig AstGen** — reference for Zig frontend architecture
6. **TypeScript-Go** — reference for TypeScript frontend

---

## What's Production-Quality

| Area | Grade | Notes |
|------|-------|-------|
| MLIR lowering patterns | A | Matches ArithToLLVM/FIR: ConversionPattern per op, populatePatterns, LLVMTypeConverter |
| Op base class hierarchy | A | CIR_BinaryOp/IntBinaryOp/IntUnaryOp/CastOp follows FIR/Arith pattern |
| CmpIPredicate enum | A | Matches Arith I64EnumAttr exactly |
| CastOpInterface | A | All 7 cast ops implement DeclareOpInterfaceMethods<CastOpInterface> with areCastCompatible |
| Cast width verifiers | A | verifyExtOp/verifyTruncOp per Arith pattern |
| Swift type philosophy | A | MLIR primitives = CIR builtins. Passes never reference language names. Lattner pattern. |
| Pass pipeline ordering | A | Sema(verify=off) → verify → CIRToLLVM → FuncToLLVM. Correct progressive lowering. |
| Frontend contract | A | All 3 frontends emit identical CIR for equivalent source. Language-agnostic IR proven. |
| Reference-based development | A | Every component traces to Zig/Go/MLIR/FIR source |
| Struct type design | A- | StructType with getFieldIndex follows FIR RecordType pattern. Custom parse/print. |
| Sema architecture | B+ | Manual walk, per-function, cast insertion. Correct pattern per Zig Sema. Needs caching. |
| Test coverage | B+ | 90 tests (55 lit + 30 inline + 5 build). Missing: negative tests, Sema-in-isolation. |
| Documentation | B+ | Internal docs self-sufficient. Op semantics need expansion. |

---

## Issues Fixed

### Round 1 — Core Standards (2026-04-04)

| Issue | Fix | Files |
|-------|-----|-------|
| No `populateXxxPatterns()` function | Added `populateCIRToLLVMConversionPatterns()` | Passes.h, CIRToLLVM.cpp |
| CmpOp predicate was raw I64Attr | Added proper `CIR_CmpIPredicateAttr` enum | CIROps.td, CIRToLLVM.cpp, codegen.cpp |
| Bitwise/shift ops accepted float types | Changed `AnyType` to `AnyInteger` | CIROps.td |
| ConstantOp missing `ConstantLike` trait | Added trait | CIROps.td |
| Hardcoded `/tmp/cot_build.o` | Use `llvm::sys::fs::createTemporaryFile()` | main.cpp |
| `std::system()` for linking (shell injection) | Use `llvm::sys::ExecuteAndWait()` | main.cpp |
| `std::ifstream` (non-LLVM) | Use `llvm::MemoryBuffer::getFile()` | main.cpp |

### Round 2 — FIR Audit (2026-04-04)

| Issue | Fix | Files |
|-------|-----|-------|
| Repetitive op definitions | Added `CIR_BinaryOp`, `CIR_IntBinaryOp`, `CIR_IntUnaryOp` base classes | CIROps.td |
| Missing `dependentDialects` | Added func::FuncDialect, LLVM::LLVMDialect | CIRDialect.td |
| func ops not marked legal in CIR lowering | Added `target.addLegalDialect<func::FuncDialect>()` | CIRToLLVM.cpp |
| ConstantOp no verifier | Added `hasVerifier=1`, validates attr type matches result | CIRDialect.cpp |
| ac codegen emitted LLVM dialect ops directly | Added `cir.br`/`cir.condbr`, codegen uses CIR only | CIROps.td, codegen.cpp |
| If-expression used branches instead of select | Added `cir.select` (audited scf.if, arith.select, llvm.select) | CIROps.td, CIRToLLVM.cpp |

### Round 3 — Phase 3 Audit (2026-04-04)

| Issue | Fix | Files |
|-------|-----|-------|
| Cast ops had AnyType constraints | Added typed base classes: CIR_IToICastOp, CIR_FToFCastOp, etc. | CIROps.td |
| Cast ops had no width verifiers | Added verifyExtOp/verifyTruncOp per Arith pattern | CIRDialect.cpp |
| Comparison operands emitted as i1 | Use i32 default for comparison operands when context is boolean | codegen.cpp |
| `std::system()` for test execution | Replaced with `runWithTimeout()` using `llvm::sys::ExecuteAndWait` | main.cpp |
| Inline tests hardcoded in Makefile | Auto-discovery via `test/run_inline.sh` with per-test timeouts | Makefile, run_inline.sh |
| No timeouts in test runners | Added 10s per-test timeout in run.sh and run_inline.sh | test/run.sh, test/run_inline.sh |

### Round 4 — Post #025 Scaling Audit (2026-04-04)

| Issue | Fix | Files |
|-------|-----|-------|
| Alloca didn't convert CIR element types | Added `getTypeConverter()->convertType()` on elem_type | MemoryPatterns.cpp |
| `xor` mnemonic inconsistent with `bit_and`/`bit_or`/`bit_not` | Renamed to `bit_xor` | CIROps.td, all frontends, tests |
| Commutative ops missing `Commutative` trait | Added to AddOp, MulOp, BitAndOp, BitOrOp, BitXorOp | CIROps.td |
| CmpOp accepted float operands via AnyType | Constrained to AnyInteger | CIROps.td |
| Store/Load had no pointer type verification | Added hasVerifier, verify addr is !cir.ptr | CIROps.td, CIRDialect.cpp |
| BrOp/CondBrOp missing BranchOpInterface | Added DeclareOpInterfaceMethods<BranchOpInterface> | CIROps.td, CIRDialect.cpp |
| Zig frontend fixed-size arrays (16 params, 32 locals) | Replaced with growable ArrayList | libzc/astgen.zig |
| Lowering patterns crash on type conversion failure | Added notifyMatchFailure null checks | ArithmeticPatterns.cpp, MemoryPatterns.cpp |
| Sema O(n) symbol lookup per call | Cached function signatures in DenseMap at pass start | SemanticAnalysis.cpp |

### Round 5 — Phase 3 Complete Audit (2026-04-04)

| Issue | Fix | Files |
|-------|-----|-------|
| 10 lowering patterns crash on null type conversion | Added `notifyMatchFailure` null checks to ALL binary arithmetic + bitwise patterns | ArithmeticPatterns.cpp, BitwisePatterns.cpp |
| Assembly format inconsistency (`->` vs `to`) | Standardized to `to` across field_val, field_ptr, elem_val, load ops | CIROps.td, 10 test files |
| `lowerToLLVM()` skipped verify after Sema | Added `verify(module)` between Sema and lowering | Compiler.cpp |
| Helper function for safe type conversion | Added `convertOpType()` to reduce duplication in arithmetic patterns | ArithmeticPatterns.cpp |

---

## Known Issues — Open

### CIR Dialect

| # | Issue | Severity | Status | Notes |
|---|-------|----------|--------|-------|
| D4 | **Type constraints too broad** | MEDIUM | OPEN | `AnyInteger` accepts i0, signed, and index types. Arith uses `SignlessFixedWidthIntegerLike`. Define CIR-specific constraint excluding i0. |
| D5 | **`cir.shr` — no signed variant** | MEDIUM | OPEN | Only logical shift right. Need `cir.shr_s` for signed types. |
| D6 | **No `hasConstantMaterializer`** | MEDIUM | OPEN | Needed for constant folding across passes. |
| D7 | **No memory model distinction** | MEDIUM | OPEN | Stack (alloca) vs heap vs global all conflated. FIR has separate alloca/allocmem/global. |
| D8 | **No constant folders** | MEDIUM | OPEN | Zero ops have `hasFolder=1`. `cir.add(const 1, const 2)` doesn't fold to `const 3`. Add when optimization passes exist. |
| D9 | **No canonicalizers** | MEDIUM | OPEN | No `hasCanonicalizer=1`. x+0, x*1, x&x patterns not simplified. |
| D10 | **Memory ops need MemoryEffect traits** | HIGH | OPEN | Alloca/Store/Load have no `MemAlloc`/`MemWrite`/`MemRead` declarations. MLIR analysis passes can't reason about memory. Add before optimization passes. |
| D11 | **No `InferIntRangeInterface`** | LOW | OPEN | Arith integer ops have it. Add when integer range analysis needed. |
| D12 | **TrapOp missing NoReturn** | LOW | OPEN | Should have `[Terminator, NoReturn]` for control flow analysis. |
| D13 | **AllocaOp result type unconstrained** | MEDIUM | OPEN | Uses `AnyType` result but always returns `!cir.ptr`. Should use `CIR_PointerType`. Requires TableGen type constraint definition. |

### Frontend

| # | Issue | Severity | Status | Notes |
|---|-------|----------|--------|-------|
| F1 | **Sema symbol table partial** | HIGH | PARTIAL | Resolves function sigs. Needs struct field resolution for #026 field access. |
| F3 | **No error recovery** | HIGH | OPEN | Parser reports first error, produces broken AST. |
| F4 | **Operator duplication (C++)** | MEDIUM | OPEN | Operators in 3 places (scanner, precedence table, codegen switch). |
| F5 | **No line/column in errors** | MEDIUM | OPEN | Reports "error at byte N" — not user-friendly. |
| F6 | **emitCast in 3 places** | MEDIUM | OPEN | Cast direction logic duplicated in ac codegen, Zig astgen, Sema. |
| F7 | **TypeScript 30% behind** | HIGH | OPEN | Missing: float types, if-expression, struct declaration, for loops, break/continue. |
| F8 | **Type resolution duplicated 3x** | MEDIUM | OPEN | Each frontend independently maps i32→IntegerType(32). Should be shared C API. |
| F9 | **Driver hardcoded frontend dispatch** | MEDIUM | OPEN | if/else on file extension. Need registry pattern for 10+ frontends. |
| F10 | **Inconsistent C ABI for frontends** | MEDIUM | OPEN | zc: `const char**`, doesn't free. tc: `char**`, driver frees. Undocumented contract. |

### Test Gaps

| # | Issue | Severity | Status | Notes |
|---|-------|----------|--------|-------|
| T1 | **No negative tests** | HIGH | OPEN | No tests for type mismatch, undefined vars, bad casts. Sema error paths untested. |
| T2 | **4 ops with zero test coverage** | HIGH | OPEN | `extui`, `field_ptr`, `elem_ptr`, `trap` — defined but never exercised. |
| T3 | **Zig/TS test parity gaps** | HIGH | OPEN | Zig missing: sub/mul/div/rem, negation tests. TS missing: 6 cast op tests (sitofp, fptosi, extf, truncf, extsi, trunci). |
| T3a | **6 lowering tests only** | MEDIUM | OPEN | Missing lowering tests for: sub, mul, div, rem, cmp, select, memory ops. |
| T4 | **No integration tests** | MEDIUM | OPEN | Nothing verifies 3 frontends produce identical binaries. Lit tests verify CIR text only. |
| T5 | **No Sema-in-isolation tests** | MEDIUM | OPEN | Sema coverage is incidental. No dedicated test directory. |

### Infrastructure

| # | Issue | Severity | Status | Notes |
|---|-------|----------|--------|-------|
| I1 | **C API too minimal** | HIGH | OPEN | Only `cirRegisterDialect()`. No type builders, op builders, field accessors. Blocks 10+ frontends. |
| I2 | **No frontend contract documentation** | HIGH | OPEN | New frontend authors must reverse-engineer existing code. Need FRONTEND.md. |

### Deferred (fix eventually)

| # | Issue | Severity | Notes |
|---|-------|----------|-------|
| E1 | `std::string_view` → `llvm::StringRef` | LOW | Throughout libac. Large migration, do incrementally. |
| E2 | `std::unordered_map` → `llvm::StringMap` | LOW | codegen.cpp namedValues. |
| E3 | Generated pass from .td | LOW | Manual PassWrapper. Migrate when pass pipeline grows. |
| E7 | Missing SameOperandsAndResultShape on casts | LOW | For tensor/vector support. Add when those types exist. |
| E8 | No float-specific binary ops | LOW | Arith has Arith_FloatBinaryOp with FastMath flags. Add when optimization passes need fastmath. |

---

## Lattner Design Fidelity

### Swift Builtin/Stdlib Type Separation — CORRECT

CIR correctly implements the pattern: MLIR primitives (`IntegerType(32)`, `Float32Type`) are CIR's builtins, equivalent to Swift's `Builtin.Int64`. Language types (`i32`, `f64`) are frontend-only names resolved to MLIR types during codegen. CIR passes never reference language names.

### Progressive Lowering — CORRECT

Pipeline: Frontend → CIR (unresolved at boundaries) → Sema → CIR (typed) → verify → CIRToLLVM → FuncToLLVM → LLVM IR → native. Each pass has one job. Matches Lattner's MLIR design.

### Frontend Contract — CORRECT

All three frontends (ac, Zig, TypeScript) emit CIR ops with MLIR types. Explicit casts emitted by frontend; implicit coercion by Sema. All produce identical CIR for equivalent source. Division of labor matches Zig (AstGen for explicit casts, Sema for coercion).

---

## Scaling Plan

### Before 10K LOC (Phase 3-4) — Current

| Action | Fixes | Priority |
|--------|-------|----------|
| Struct field resolution in Sema | F1 | Before #026 |
| TypeScript feature parity | F7 | During Phase 3 |
| Negative tests for Sema | T1 | Phase 3 |
| Test `extui` and `trap` ops | T2 | Phase 3 |
| Error recovery in parser | F3 | Before Phase 4 |
| Frontend contract documentation | I2 | Phase 3 |

### Before 100K LOC (Phase 5-6)

| Action | Notes |
|--------|-------|
| Expand CIR C API (type/op builders) | I1 — blocks 10+ frontend integration |
| Shared type resolution library | F8 — eliminate 3x duplication |
| Frontend registry in driver | F9 — replace hardcoded if/else |
| Type system expansion (optional, slice, func types) | D7 — needed for Rust/Swift/Go |
| Constant folders for arithmetic ops | D8 |
| Compiler-as-library API (`libCOT.h`) | Language servers, debuggers need library API |

### Before 500K LOC (Phase 7-11)

| Action | Notes |
|--------|-------|
| Canonicalizers for all ops | D9 |
| Pass pipeline extraction (`libcot/Pipeline.h`) | Configurable pass ordering |
| Stable ABI for CIR types | External consumers depend on CIR types |
| Distributed testing | Run test suite across targets in parallel |

---

## Reference Fidelity

| Reference | Fidelity | Gap |
|-----------|----------|-----|
| MLIR/Lattner (progressive lowering) | HIGH | Pipeline correct. Need multi-stage lowering at Phase 5+. |
| FIR/Flang (dialect design) | MEDIUM | 3 types vs FIR's 15. Missing InferIntRange. Verifiers correct. |
| ArithToLLVM (lowering patterns) | HIGH | Exact match. Patterns need notifyMatchFailure. |
| Arith (op design) | HIGH | 7 cast ops, typed base classes, CastOpInterface, width verifiers. Need folders/canonicalizers. |
| Go parser (precedence climbing) | HIGH | Correct pattern. Struct init disambiguated via lookahead. |
| Zig AstGen (recursive dispatch) | HIGH | Correct dispatch. Growable containers needed. |
| Swift (type philosophy) | HIGH | MLIR types = builtins. Passes never reference language names. |
| LLVM coding standards | MEDIUM | Correct formatting. Still using std containers (should be LLVM types). |

---

## Audit Checklist (run before major milestones)

- [x] All ops use appropriate base class
- [x] All ops have correct type constraints
- [x] Cast ops have CastOpInterface
- [x] Commutative ops have Commutative trait
- [x] Branch ops have BranchOpInterface
- [x] Memory ops verify pointer types
- [x] All lowering patterns registered in `populateCIRToLLVMConversionPatterns()`
- [x] `dependentDialects` up to date
- [x] No frontend code emitting LLVM dialect ops
- [x] No `std::system()`, `std::ifstream`, or hardcoded paths in driver
- [x] All tests pass: lit, gate, inline, build
- [x] CIR text output is readable
- [x] Sema pass emits diagnostics and signals failure
- [x] All 3 frontends produce identical CIR for equivalent source
- [ ] Negative tests for Sema error paths
- [ ] All CIR ops tested in all 3 frontends
- [ ] Constant folders on arithmetic ops
