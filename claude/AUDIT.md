# CIR Audit — MLIR/LLVM Standards Compliance

**Last audit:** 2026-04-04 (Phase 3 in progress — 28 CIR ops, 71 tests)
**Reference compilers:** Flang FIR, MLIR Arith/SCF, ArithToLLVM, Go parser, Zig AstGen

---

## Audit Methodology

CIR is audited against production MLIR references:
1. **Flang FIR** — closest analogue (frontend IR as MLIR dialect, ~500K LOC)
2. **MLIR Arith/SCF** — canonical arithmetic ops + structured control flow
3. **ArithToLLVM** — canonical lowering patterns
4. **Go parser** — reference for ac parser architecture
5. **Zig AstGen** — reference for Zig frontend architecture

---

## What's Production-Quality

| Area | Grade | Notes |
|------|-------|-------|
| MLIR lowering patterns | A | Matches ArithToLLVM/FIR: ConversionPattern per op, populatePatterns, LLVMTypeConverter |
| Op base class hierarchy | A | CIR_BinaryOp/IntBinaryOp/IntUnaryOp/CastOp follows FIR/Arith pattern |
| CmpIPredicate enum | A | Matches Arith I64EnumAttr exactly |
| ConstantOp | B+ | ConstantLike + verifier. Missing folder (OK for now) |
| Cast ops | B+ | 7 ops, Arith pattern, type constraints, width verifiers. Missing CastOpInterface. |
| Type safety via traits | A- | Pure, SameOperandsAndResultType, AllTypesMatch on select, AnyInteger on bitwise |
| Swift type philosophy | A | MLIR primitives = CIR builtins. Passes never reference language names. Lattner pattern. |
| Sema pass architecture | A- | Manual walk, per-function, symbol table from module, cast insertion. Minor issues. |
| Reference-based development | A | Every component traces to Zig/Go/MLIR/FIR source |
| Documentation | A | Internal docs self-sufficient for onboarding |
| Test coverage | B+ | 71 tests. Per-test timeouts. Missing: integration, Sema-in-isolation tests. |
| Multi-frontend validation | A | Both ac and Zig emit identical CIR — proves language-agnostic IR |
| Test framework | A- | Auto-discovery, 10s timeouts, `llvm::sys::ExecuteAndWait`. No silent hangs. |

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

---

## Known Issues — Open

### CIR Dialect (fix before #024 Structs)

| # | Issue | Severity | Status | Notes |
|---|-------|----------|--------|-------|
| D1 | **Missing CastOpInterface** | HIGH | OPEN | Arith_CastOp declares `DeclareOpInterfaceMethods<CastOpInterface>`. CIR cast ops lack this. Without it, MLIR fold/verify infrastructure won't recognize cast ops. Fix: add to CIR_CastOp base class. |
| D2 | **Sema result type mutation** | HIGH | OPEN | `callOp.getResult(0).setType()` directly mutates SSA types — fragile, breaks invariants if result is used. Replace with op rebuild or trust frontends to emit correct return types. |
| D3 | **Sema silent failures** | HIGH | OPEN | Arg count mismatch returns silently (line 70). No `signalPassFailure()`. Should emit diagnostics and halt pipeline. |
| D4 | **Type constraints too broad** | MEDIUM | OPEN | `AnyInteger` accepts i0, signed, and index types. Arith uses `SignlessFixedWidthIntegerLike`. Define CIR-specific constraint excluding i0. |
| D5 | **`cir.shr` — no signed variant** | MEDIUM | OPEN | Only logical shift right. Need `cir.shr_s` for signed types. |
| D6 | **No `hasConstantMaterializer`** | MEDIUM | OPEN | Needed for constant folding across passes. |
| D7 | **No memory model distinction** | MEDIUM | OPEN | Stack (alloca) vs heap vs global all conflated. FIR has separate alloca/allocmem/global. |

### Frontend (fix during Phase 3)

| # | Issue | Severity | Status | Notes |
|---|-------|----------|--------|-------|
| F1 | **No symbol table** | CRITICAL | PARTIAL | Sema resolves function sigs from MLIR module. Full symbol table (struct fields, type defs) needed for #024+. |
| F2 | **Zig fixed-size arrays** | HIGH | OPEN | `param_names: [16]`, `local_names: [32]` — hard limits. Need HashMap migration before structs add more locals. |
| F3 | **No error recovery** | HIGH | OPEN | Parser reports first error, produces broken AST. |
| F4 | **Operator duplication (C++)** | MEDIUM | OPEN | Operators in 3 places (scanner, precedence table, codegen switch). |
| F5 | **No line/column in errors** | MEDIUM | OPEN | Reports "error at byte N" — not user-friendly. |
| F6 | **emitCast in 3 places** | MEDIUM | OPEN | Cast logic duplicated in ac codegen, Zig astgen, and Sema pass. Explicit casts (frontend) vs implicit coercion (Sema) is correct separation. But direction-selection logic should be a shared utility when we add unsigned casts (extui). |

### Infrastructure

| # | Issue | Severity | Status | Notes |
|---|-------|----------|--------|-------|
| I5 | **No integration tests** | MEDIUM | OPEN | Nothing verifies ac and Zig produce identical binaries. Lit tests verify CIR text, not binary equivalence. |

### Deferred (fix eventually)

| # | Issue | Severity | Notes |
|---|-------|----------|-------|
| E1 | `std::string_view` → `llvm::StringRef` | LOW | Throughout libac. Large migration, do incrementally. |
| E2 | `std::unordered_map` → `llvm::StringMap` | LOW | codegen.cpp namedValues. |
| E3 | Generated pass from .td | LOW | Manual PassWrapper. Migrate when pass pipeline grows. |
| E4 | Op folders/canonicalizers | LOW | No ops define `hasFolder=1`. Add when optimization passes exist. |
| E5 | Driver command splitting | LOW | main.cpp OK now. Split at 500+ LOC. |
| E6 | Missing InferIntRangeInterface | LOW | Arith integer ops have it. Add when integer range analysis needed. |
| E7 | Missing SameOperandsAndResultShape on casts | LOW | For tensor/vector support. Add when those types exist. |
| E8 | No float-specific binary ops | LOW | Arith has Arith_FloatBinaryOp with FastMath flags. Add when optimization passes need fastmath. |

---

## Lattner Design Fidelity

### Swift Builtin/Stdlib Type Separation — CORRECT

CIR correctly implements the pattern: MLIR primitives (`IntegerType(32)`, `Float32Type`) are CIR's builtins, equivalent to Swift's `Builtin.Int64`. Language types (`i32`, `f64`) are frontend-only names resolved to MLIR types during codegen. CIR passes never reference language names.

### Progressive Lowering — CORRECT

Pipeline: Frontend → CIR (unresolved at boundaries) → Sema → CIR (typed) → verify → CIRToLLVM → FuncToLLVM → LLVM IR → native. Each pass has one job. Matches Lattner's MLIR design.

### Frontend Contract — CORRECT

Frontends emit CIR ops with MLIR types. Explicit casts emitted by frontend; implicit coercion by Sema. Both frontends produce identical CIR for equivalent source. Division of labor matches Zig (AstGen for explicit casts, Sema for coercion).

---

## Feature Implementation Workflow

Every feature follows this refined checklist. Step 2 (audit check) was added after Round 3 audit.

```
 1. Study reference (Zig/MLIR/FIR/Swift source)
 2. Check AUDIT.md — fix related open issues NOW, not later
 3. CIR ops: base class, type constraints, traits, verifiers
 4. Lowering: ConversionPattern, register in populatePatterns
 5. ac frontend: scanner → parser → codegen (emit CIR only)
 6. Zig frontend: AST dispatch → CIR emission (match ac output)
 7. Sema: add implicit resolution if feature needs it
 8. Lit tests: BOTH frontends + lowering test
 9. Inline test: runtime correctness
10. Build + full test suite (make test)
11. Docs: FEATURES.md ✓, AC_SYNTAX.md, HANDOFF.md, AUDIT.md
```

---

## Scaling Plan

### Before 10K LOC (Phase 3-4)

| Action | Fixes | Priority |
|--------|-------|----------|
| Add CastOpInterface to cast ops | D1 | **NOW** |
| Fix Sema result type mutation | D2 | **NOW** |
| Add Sema diagnostics | D3 | **NOW** |
| Add integration test harness | I5 | Phase 3 |
| Design symbol table for structs | F1 | Before #024 |
| Zig HashMap migration | F2 | Before #024 |
| Error recovery in parser | F3 | Before Phase 4 |

### Before 100K LOC (Phase 1-6 done)

| Action | Notes |
|--------|-------|
| Compiler-as-library API (`libCOT.h`) | Language servers, debuggers need library API, not CLI |
| Unified build (Bazel/CMake `add_subdirectory`) | Can't manage 5+ sub-builds manually |
| Comprehensive diagnostics engine | Clang-quality error messages with source context |
| Per-pass test infrastructure | Verify intermediate IR transformations |
| Public C API for CIR dialect | External tools, Python bindings |

### Before 500K LOC (Phase 7-11)

| Action | Notes |
|--------|-------|
| Stable ABI | External consumers depend on CIR types |
| Distributed testing | Run test suite across targets in parallel |
| Per-component design docs | Break ARCHITECTURE.md into CIR_DIALECT.md, PASSES.md, etc. |
| Pass pipeline extraction | `libcot/Pipeline.h` — configurable pass ordering |

---

## Reference Fidelity

| Reference | Fidelity | Gap |
|-----------|----------|-----|
| MLIR/Lattner (progressive lowering) | HIGH | Pipeline correct. Need multi-stage lowering at Phase 5+. |
| FIR/Flang (dialect design) | MEDIUM | 3 types vs FIR's 15. Missing CastOpInterface. Verifiers correct. |
| ArithToLLVM (lowering patterns) | HIGH | Exact match. Cast ops follow Arith CastOp hierarchy. |
| Arith (cast op design) | HIGH | 7 ops, typed base classes, width verifiers. Missing CastOpInterface + InferIntRange. |
| Go parser (precedence climbing) | HIGH | Correct pattern. Need operator table to avoid 3-place duplication. |
| Zig AstGen (recursive dispatch) | HIGH | Correct dispatch. Builtin cast handling added. Fixed arrays still deviate. |
| Swift (type philosophy) | HIGH | MLIR types = builtins. Passes never reference language names. |
| LLVM coding standards | MEDIUM | Correct formatting. Still using std containers (should be LLVM types). |

---

## Reference Patterns

### Adding a new binary integer op
```tablegen
def CIR_NewOp : CIR_IntBinaryOp<"new_op"> { let summary = "description"; }
```
Then add lowering pattern in CIRToLLVM.cpp and register in `populateCIRToLLVMConversionPatterns()`.

### Adding a new CIR type
Reference: `~/claude/references/flang-ref/flang/include/flang/Optimizer/Dialect/FIRTypes.td`
1. Add type definition to `libcir/include/CIR/CIRTypes.td`
2. Generated files already wired (CIRTypes.h.inc/cpp.inc via CMake)
3. Register in `CIRDialect::initialize()`

### Adding a new pass
Reference: `~/claude/references/flang-ref/flang/lib/Optimizer/CodeGen/CodeGen.cpp`
1. Add `createXxxPass()` to `libcot/include/COT/Passes.h`
2. Implement in `libcot/lib/Xxx.cpp`
3. Add `populateXxxPatterns()` if conversion-based

---

## Audit Checklist (run before major milestones)

- [ ] All ops use appropriate base class
- [ ] All ops have correct type constraints
- [ ] Cast ops have CastOpInterface (D1)
- [ ] All lowering patterns registered in `populateCIRToLLVMConversionPatterns()`
- [ ] `dependentDialects` up to date
- [ ] No frontend code emitting LLVM dialect ops
- [ ] No `std::system()`, `std::ifstream`, or hardcoded paths in driver
- [ ] All tests pass: lit, gate, inline, build
- [ ] CIR text output is readable
- [ ] Sema pass emits diagnostics, not silent failures
- [ ] Codegen functions under 60 lines each (excluding dispatch switches)
- [ ] New types have verifiers
- [ ] Both frontends produce identical CIR for equivalent source
