# CIR Audit — MLIR/LLVM Standards Compliance

**Last audit:** 2026-04-04 (Phase 2 complete — 3.3K LOC, 21 CIR ops, 55 tests)
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
| Op base class hierarchy | A | CIR_BinaryOp/IntBinaryOp/IntUnaryOp follows FIR fir_Op/fir_SimpleOp pattern |
| CmpIPredicate enum | A | Matches Arith I64EnumAttr exactly |
| ConstantOp | B+ | ConstantLike + verifier. Missing folder (OK for now) |
| Type safety via traits | A- | Pure, SameOperandsAndResultType, AllTypesMatch on select, AnyInteger on bitwise |
| Reference-based development | A | Every component traces to Zig/Go/MLIR/FIR source |
| Documentation | A | 1.5K LOC internal docs, self-sufficient for onboarding |
| Test coverage | B+ | 55 tests for 3.3K LOC. Missing: integration, error cases, lowering coverage |
| Multi-frontend validation | A | Both ac and Zig emit identical CIR — proves language-agnostic IR |
| Go parser fidelity | A | Precedence climbing, recursive descent, synthetic semicolons correctly ported |
| Zig AstGen fidelity | B+ | Recursive dispatch correct. Fixed arrays deviate from Zig's HashMap scoping |

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

---

## Known Issues — Open

### Infrastructure (fix before Phase 3 features)

| # | Issue | Severity | Notes |
|---|-------|----------|-------|
| I1 | **CIR type system — only 1 type** | CRITICAL | FIR has 15+ types. Need `!cir.struct` and `!cir.array` for Phase 3. Without them, struct semantics lost at lowering. |
| I2 | **Codegen mega-functions** | HIGH | ac `emitStmt()` 180 lines (CC=12), Zig `mapStmt()` 110 lines. Will exceed 300 at Phase 3. Extract per-statement helpers. |
| I3 | **CIRToLLVM.cpp monolithic** | HIGH | 330 lines, 24 patterns. At FIR scale (60+) becomes 700+. Split into ArithmeticPatterns, MemoryPatterns, ControlFlowPatterns. |
| I4 | **No unified build** | HIGH | 4 manual steps in exact order. Need top-level Makefile. |
| I5 | **No integration tests** | MEDIUM | Nothing verifies ac and Zig produce identical binaries for equivalent programs. |

### Frontend (fix during Phase 3)

| # | Issue | Severity | Notes |
|---|-------|----------|-------|
| F1 | **No symbol table** | CRITICAL | Neither frontend can resolve struct fields, check type compatibility, or track type definitions. Blocks #024-#027. |
| F2 | **Zig fixed-size arrays** | HIGH | `param_names: [16]`, `local_names: [32]` — hard limits. Nested scopes will overflow. Need HashMap migration. |
| F3 | **No error recovery** | HIGH | Parser reports first error, produces broken AST. Flang/Clang both had recovery before adding types. |
| F4 | **Operator duplication (C++)** | MEDIUM | Operators appear in 3 places (scanner, precedence table, codegen switch). Use operator table. |
| F5 | **No line/column in errors** | MEDIUM | Reports "error at byte N" — not user-friendly. Need line counter in scanner. |

### CIR Dialect (fix before Phase 4)

| # | Issue | Severity | Notes |
|---|-------|----------|-------|
| D1 | **`cir.shr` — no signed variant** | MEDIUM | Only logical shift right. Need `cir.shr_s` for signed types. |
| D2 | **No `hasConstantMaterializer`** | MEDIUM | Needed for constant folding across passes. |
| D3 | **No memory model distinction** | MEDIUM | Stack (alloca) vs heap vs global all conflated. FIR has separate alloca/allocmem/global. |

### Deferred (fix eventually)

| # | Issue | Severity | Notes |
|---|-------|----------|-------|
| E1 | `std::string_view` → `llvm::StringRef` | LOW | Throughout libac. Large migration, do incrementally. |
| E2 | `std::unordered_map` → `llvm::StringMap` | LOW | codegen.cpp namedValues. |
| E3 | Generated pass from .td | LOW | Manual PassWrapper. Migrate when pass pipeline grows. |
| E4 | Op folders/canonicalizers | LOW | No ops define `hasFolder=1`. Add when optimization passes exist. |
| E5 | Driver command splitting | LOW | main.cpp (291 LOC) OK now. Split at 500+ LOC into Compiler/Tester/Emitter. |

---

## Scaling Plan

### Before 10K LOC (Phase 3-4)

| Action | Fixes | Effort | Priority |
|--------|-------|--------|----------|
| Add `!cir.struct` and `!cir.array` types | I1 | 200 LOC | **NOW** |
| Top-level Makefile | I4 | 50 LOC | **NOW** |
| Refactor codegen mega-functions | I2 | 200 LOC | **NOW** |
| Split CIRToLLVM.cpp by category | I3 | 200 LOC | **NOW** |
| Add integration test harness | I5 | 200 LOC | Phase 3 start |
| Design symbol table | F1 | 300 LOC | Phase 3 start |
| Zig HashMap migration | F2 | 150 LOC | Phase 3 start |
| Error recovery in parser | F3 | 200 LOC | Before Phase 4 |

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
| MLIR/Lattner (progressive lowering) | HIGH | Need multi-stage lowering (CIR→CIR opt, CIR→LLVM) at Phase 5+ |
| FIR/Flang (dialect design) | MEDIUM | Missing type depth (FIR: 15 types, CIR: 1), verifiers, custom builders |
| ArithToLLVM (lowering patterns) | HIGH | Exact match on pattern structure. Need to split file at scale. |
| Go parser (precedence climbing) | HIGH | Correct pattern. Need operator table to avoid 3-place duplication. |
| Zig AstGen (recursive dispatch) | MEDIUM-HIGH | Correct dispatch. Fixed arrays deviate from Zig's HashMap scoping. |
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
- [ ] All lowering patterns registered in `populateCIRToLLVMConversionPatterns()`
- [ ] `dependentDialects` up to date
- [ ] No frontend code emitting LLVM dialect ops
- [ ] No `std::system()`, `std::ifstream`, or hardcoded paths in driver
- [ ] All tests pass: lit, gate, inline, build
- [ ] CIR text output is readable
- [ ] Integration tests pass (ac ↔ Zig produce same CIR)
- [ ] Codegen functions under 60 lines each
- [ ] New types have verifiers
