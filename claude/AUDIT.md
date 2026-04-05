# CIR Audit — MLIR/LLVM Standards Compliance

**Last audit:** 2026-04-05 Round 8 (Phase 6 in progress — 56 CIR ops, 8 types, 142 test targets, 3 frontends)
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
| MLIR lowering patterns | A | 39 ConversionPatterns, all with notifyMatchFailure. Matches ArithToLLVM/FIR. |
| Op base class hierarchy | A | CIR_BinaryOp/IntBinaryOp/IntUnaryOp/CastOp follows FIR/Arith pattern |
| CmpIPredicate enum | A | Matches Arith I64EnumAttr exactly |
| CastOpInterface | A | All 7 cast ops implement DeclareOpInterfaceMethods<CastOpInterface> with areCastCompatible |
| Cast width verifiers | A | verifyExtOp/verifyTruncOp per Arith pattern |
| Swift type philosophy | A | MLIR primitives = CIR builtins. Passes never reference language names. Lattner pattern. |
| Pass pipeline | A | PipelineBuilder with 3 extension points. Sema→verify→[post-sema]→CIRToLLVM. Progressive lowering correct. |
| Frontend contract | A | All 3 frontends use CIR C API (cirBuild*). Zero raw mlirOperationCreate for CIR ops. |
| Reference-based development | A | Every component traces to Zig/Go/MLIR/FIR source |
| C API | A | 50 functions: types, queries, all op builders. Language-agnostic frontend enablement. |
| CMake distribution | A | Super-build, install targets, find_package(CIR)/find_package(COT) config files. |
| Type system | A | 7 custom types (ptr, ref, struct, array, slice, optional, error_union). All with parse/print + verifiers. |
| Sema architecture | B+ | Manual walk, per-function, cast insertion. Correct pattern per Zig Sema. |
| Test coverage | B+ | 100 lit + 22 inline + 4 build. All ops tested. TS narrowing. |
| Documentation | B+ | DISTRIBUTION_DESIGN.md, PHASE4_DESIGN.md. Missing FRONTEND.md. |

---

## Issues Fixed

### Round 1-5 — See prior audit entries (all fixes preserved)

### Round 6 — Phase 4 Complete + Distribution (2026-04-04)

| Issue | Fix | Files |
|-------|-----|-------|
| I1: C API too minimal (was 1 function) | Expanded to 50 functions: type constructors, queries, all op builders | CIRCApi.h/cpp, COTCApi.h/cpp |
| F8: Type resolution duplicated 3x (partial) | C API provides cirPointerTypeGet, cirStructTypeGet etc. — shared across languages | CIRCApi.h |
| Pipeline hardcoded in Compiler.cpp | PipelineBuilder with 3 extension points, Compiler.cpp delegates | Pipeline.h, Pipeline.cpp, Compiler.cpp |
| No install targets / no find_package support | CMake super-build with CIRConfig.cmake, COTTargets.cmake | CMakeLists.txt (top), cmake/ |
| 3 isolated build directories | Single build/ directory, Makefile is thin wrapper | Makefile, all CMakeLists.txt |
| Frontends used raw mlirOperationCreate | Migrated libzc + libtc to cirBuild* C API | astgen.zig, mlir.zig, codegen.go, mlir.go |
| No CLI plugin support | --load-pass-plugin flag, mlirGetPassPluginInfo convention | cot/main.cpp |

---

## Known Issues — Open

### CIR Dialect

| # | Issue | Severity | Status | Notes |
|---|-------|----------|--------|-------|
| D4 | **Type constraints too broad** | MEDIUM | OPEN | `AnyInteger` accepts i0, signed, and index types. Arith uses `SignlessFixedWidthIntegerLike`. |
| D5 | **`cir.shr` — no signed variant** | MEDIUM | OPEN | Only logical shift right. Need `cir.shr_s` for signed types. |
| D6 | **No `hasConstantMaterializer`** | MEDIUM | OPEN | Needed for constant folding across passes. |
| D7 | **No memory model distinction** | MEDIUM | OPEN | Stack (alloca) vs heap vs global. FIR has separate alloca/allocmem/global. |
| D8 | **No constant folders** | MEDIUM | OPEN | Zero ops have `hasFolder=1`. Add when optimization passes exist. |
| D9 | **No canonicalizers** | MEDIUM | OPEN | No `hasCanonicalizer=1`. x+0, x*1 not simplified. |
| D10 | ~~Memory ops need MemoryEffect traits~~ | HIGH | **FIXED** | Alloca=MemAlloc, Store=MemWrite, Load=MemRead. Added Round 6. |
| D13 | ~~AllocaOp missing verifier~~ | LOW | **FIXED** | hasVerifier=1, verify result is !cir.ptr. Added Round 6. |
| D14 | **Assembly format: `->` vs `to`** | LOW | NEW | elem_ptr and array_to_slice use `->` while others use `to`. Minor inconsistency. |

### Frontend

| # | Issue | Severity | Status | Notes |
|---|-------|----------|--------|-------|
| F3 | **No error recovery** | HIGH | OPEN | Parser reports first error, produces broken AST. |
| F5 | ~~No line/column in errors~~ | MEDIUM | **FIXED** | FileLineColLoc on every op. All 3 frontends. `--mlir-print-debuginfo` shows locations. |
| F7 | **TypeScript test parity gap** | HIGH | OPEN | 19 TS tests vs 31 ac tests. Missing: float types, if-expression, for loops, casts, pointers. |
| F9 | **Driver hardcoded frontend dispatch** | MEDIUM | OPEN | if/else on file extension. Need registry for 10+ frontends. |
| F10 | **Inconsistent C ABI for frontends** | MEDIUM | OPEN | zc: const char**, doesn't free. tc: char**, driver frees. |

### Test Gaps

| # | Issue | Severity | Status | Notes |
|---|-------|----------|--------|-------|
| T1 | **No negative tests** | HIGH | **PARTIAL** | 3 negative tests: arg_count, type_mismatch_return, bad_optional_unwrap. More needed for undefined vars, bad casts. |
| T2 | ~~4 ops with zero test coverage~~ | HIGH | **FIXED** | `extui` (unsigned cast), `field_ptr` (field mutation), `elem_ptr` (array mutation), `trap` (assert fail). All tested in untested_ops.ac + inline 047. |
| T3 | **Zig/TS test parity gaps** | MEDIUM | **PARTIAL** | Zig added: comparison, negation. TS added: for_loop, if_expr. Remaining: TS float_types, type_casts, pointers (not valid TS — deferred). |
| T4 | **No integration tests** | MEDIUM | OPEN | Nothing verifies 3 frontends produce identical binaries. |
| T5 | **No Sema-in-isolation tests** | MEDIUM | OPEN | Sema coverage is incidental. |

### Infrastructure

| # | Issue | Severity | Status | Notes |
|---|-------|----------|--------|-------|
| I2 | **No frontend contract documentation** | HIGH | OPEN | Need FRONTEND.md for new frontend authors. |
| I3 | **--post-sema-pass not fully wired** | MEDIUM | NEW | Plugin loading works but pass injection into PipelineBuilder needs parsePassPipeline integration. |

### Deferred (fix eventually)

| # | Issue | Severity | Notes |
|---|-------|----------|-------|
| E1 | `std::string_view` → `llvm::StringRef` | LOW | Throughout libac. |
| E2 | `std::unordered_map` → `llvm::StringMap` | LOW | codegen.cpp namedValues. |
| E3 | Generated pass from .td | LOW | Manual PassWrapper. |

### Closed Since Last Audit (Round 8)

| # | Issue | Resolution |
|---|-------|------------|
| F5 | No line/column in errors | FIXED — FileLineColLoc on every op, all 3 frontends |
| T1 | No negative tests | PARTIAL — 3 negative tests added (arg_count, type_mismatch, bad_optional) |
| T2 | 4 ops with zero test coverage | FIXED — extui, field_ptr, elem_ptr, trap all tested |
| D10 | Memory ops need MemoryEffect traits | FIXED — Alloca/Store/Load have correct traits |
| D13 | AllocaOp missing verifier | FIXED — verify result is !cir.ptr |
| — | Frontend segfaults on invalid input | FIXED — hasError_ flag + dummy values + null module return |
| — | No MLIR debug flags in CLI | FIXED — --mlir-print-debuginfo, --mlir-print-ir-after-all |
| — | Sema errors lack context | FIXED — notes point to callee declaration |

### Closed Prior (Rounds 1-7)

| # | Issue | Resolution |
|---|-------|------------|
| I1 | C API too minimal | FIXED — 60+ functions now |
| F8 | Type resolution duplicated 3x | PARTIALLY FIXED — C API type constructors shared |
| D11 | No InferIntRangeInterface | DEFERRED — not needed before optimization |
| D12 | TrapOp missing NoReturn | LOW — trap has Terminator trait which is sufficient |

---

## Lattner Design Fidelity

### Swift Builtin/Stdlib Type Separation — CORRECT
CIR builtins = MLIR types. Language types resolved by frontends. Passes never reference language names.

### Progressive Lowering — CORRECT
Frontend → CIR → Sema → verify → [post-sema plugins] → CIRToLLVM → LLVM IR → native.

### Frontend Contract — CORRECT + IMPROVED
All 3 frontends use cirBuild* C API. Zero raw mlirOperationCreate for CIR ops. Language-agnostic IR proven.

### Compiler-as-Library — CORRECT
PipelineBuilder, COT/Compiler.h, COT/Pipeline.h. CLI is thin wrapper. External consumers can link and use.

### Distribution Model — NEW, CORRECT
Matches LLVM/MLIR Homebrew pattern: lib/libCIR.a, include/CIR/, lib/cmake/cir/CIRConfig.cmake.

---

## Pre-Phase 6 Recommendations

### Should Fix (quality)

| # | Action | Why | Effort |
|---|--------|-----|--------|
| I2 | Write FRONTEND.md | Distribution design assumes external frontend authors | 2 hr |
| T1 | Add negative tests | No tests for type mismatch, undefined vars | 1 hr |
| T4 | Integration test: identical CIR from 3 frontends | Validates universal IR promise | 1 hr |

### Can Defer

| # | Action | Why |
|---|--------|-----|
| D14 | Assembly format `->` vs `to` | Cosmetic, changing would break existing tests |
| D5 | Signed shift right | Not needed until signed integer semantics |
| D8/D9 | Folders/canonicalizers | Not needed until optimization passes |
| D6 | hasConstantMaterializer | Not needed until constant folding |
| E1-E3 | LLVM container/StringRef migration | Low priority cleanup |

---

## Audit Checklist

- [x] All ops use appropriate base class
- [x] All ops have correct type constraints
- [x] Cast ops have CastOpInterface
- [x] Commutative ops have Commutative trait
- [x] Branch ops have BranchOpInterface
- [x] Memory ops verify pointer types
- [x] All lowering patterns registered in populateCIRToLLVMConversionPatterns()
- [x] All lowering patterns have notifyMatchFailure null checks
- [x] dependentDialects up to date
- [x] No frontend code emitting LLVM dialect ops
- [x] No std::system(), std::ifstream, or hardcoded paths in driver
- [x] All tests pass: lit, gate, inline, build
- [x] CIR text output is readable
- [x] Sema pass emits diagnostics and signals failure
- [x] All 3 frontends produce identical CIR for equivalent source
- [x] All 3 frontends use CIR C API (cirBuild*) — no raw emit for CIR ops
- [x] C API covers all CIR types and ops
- [x] CMake install produces correct layout with find_package support
- [x] PipelineBuilder has extension points for plugin passes
- [x] Negative tests for Sema error paths (3 tests: arg_count, type_mismatch, bad_optional)
- [ ] All CIR ops tested in all 3 frontends
- [x] MemoryEffect traits on memory ops (Alloca=MemAlloc, Store=MemWrite, Load=MemRead)
- [ ] FRONTEND.md documentation
- [x] Source locations on all CIR ops (FileLineColLoc, all 3 frontends)
- [x] MLIR CLI debug flags (--mlir-print-debuginfo, --mlir-print-ir-after-all)
- [x] Sema diagnostics with notes (arg count, type mismatch → "declared here")
- [x] Graceful frontend error handling (no segfaults on invalid input)
- [ ] Error codes (E001+) with documentation
- [ ] "Did you mean?" suggestions
- [ ] SourceMgrDiagnosticHandler for source-context underlines
- [ ] DWARF debug info emission
