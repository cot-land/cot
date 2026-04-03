# CIR Audit — MLIR/LLVM Standards Compliance

**Last audit:** 2026-04-04
**Reference compilers:** Flang FIR (`~/claude/references/flang-ref/flang/`), MLIR Arith, ArithToLLVM

---

## Audit Methodology

CIR is audited against three production MLIR references:
1. **Flang FIR** — closest analogue (frontend IR as MLIR dialect)
2. **MLIR Arith** — canonical arithmetic ops
3. **ArithToLLVM** — canonical lowering patterns

## Issues Fixed (2026-04-04)

### Round 1 — Core Standards

| Issue | Fix | Files |
|-------|-----|-------|
| No `populateXxxPatterns()` function | Added `populateCIRToLLVMConversionPatterns()` | Passes.h, CIRToLLVM.cpp |
| CmpOp predicate was raw I64Attr | Added proper `CIR_CmpIPredicateAttr` enum | CIROps.td, CIRToLLVM.cpp, codegen.cpp |
| Bitwise/shift ops accepted float types | Changed `AnyType` to `AnyInteger` | CIROps.td |
| ConstantOp missing `ConstantLike` trait | Added trait | CIROps.td |
| Hardcoded `/tmp/cot_build.o` | Use `llvm::sys::fs::createTemporaryFile()` | main.cpp |
| `std::system()` for linking (shell injection) | Use `llvm::sys::ExecuteAndWait()` | main.cpp |
| `std::ifstream` (non-LLVM) | Use `llvm::MemoryBuffer::getFile()` | main.cpp |

### Round 2 — FIR Audit

| Issue | Fix | Files |
|-------|-----|-------|
| Repetitive op definitions (10+ identical patterns) | Added `CIR_BinaryOp`, `CIR_IntBinaryOp`, `CIR_IntUnaryOp` base classes | CIROps.td |
| Missing `dependentDialects` | Added func::FuncDialect, LLVM::LLVMDialect | CIRDialect.td |
| func ops not marked legal in CIR lowering | Added `target.addLegalDialect<func::FuncDialect>()` | CIRToLLVM.cpp |
| ConstantOp no verifier | Added `hasVerifier=1`, validates attr type matches result | CIRDialect.cpp |

---

## Known Issues — Fix Next

### Fix with Phase 2 features

| Issue | Severity | Notes |
|-------|----------|-------|
| **ac codegen emits LLVM dialect ops** | HIGH | `codegen.cpp` creates `LLVM::CondBrOp`/`LLVM::BrOp` directly for assert/if. Fix when adding `cir.condbr`/`cir.br` (feature #015). |
| **`cir.shr` — no signed variant** | MEDIUM | Only logical (unsigned) shift right. Need `cir.shr_s` (arithmetic) for signed types. Fix when adding signed type semantics. |

### Fix before Phase 3 (types/structs)

| Issue | Severity | Notes |
|-------|----------|-------|
| **No custom CIR types** | HIGH | Need `!cir.ptr<T>`, `!cir.struct<name>`, `!cir.array<N x T>` before Phase 3. Reference: FIR's FIRTypes.td. |
| **No custom LLVMTypeConverter** | HIGH | Needed when custom CIR types exist. Reference: Flang's TypeConverter.h. |
| **No `hasConstantMaterializer`** | MEDIUM | Needed for constant folding. Add to CIRDialect.td + implement `materializeConstant()` in CIRDialect.cpp. |

### Fix eventually

| Issue | Severity | Notes |
|-------|----------|-------|
| `std::string_view` → `llvm::StringRef` | LOW | Throughout libac (scanner.h, parser.h, codegen.cpp). Large migration, do incrementally. |
| `std::unordered_map` → `llvm::StringMap` | LOW | codegen.cpp namedValues. |
| Generated pass from .td | LOW | Currently manual PassWrapper. Migrate when pass pipeline grows. |
| Op folders/canonicalizers | LOW | No ops define `hasFolder=1` or `hasCanonicalizer=1`. Add when optimization passes exist. |
| Custom type/attribute printing | LOW | Currently default MLIR format. Add when custom types exist. |
| FIROpPatterns-style helper base | LOW | Shared helper methods for lowering patterns. Add when patterns get complex. |

---

## Reference Patterns to Follow

### Adding a new binary integer op

```tablegen
// In CIROps.td — one line:
def CIR_NewOp : CIR_IntBinaryOp<"new_op"> { let summary = "description"; }
```

Then add lowering pattern in CIRToLLVM.cpp and register in `populateCIRToLLVMConversionPatterns()`.

### Adding a new CIR type (when needed)

Reference: `~/claude/references/flang-ref/flang/include/flang/Optimizer/Dialect/FIRTypes.td`

1. Create `libcir/include/CIR/CIRTypes.td`
2. Add `-gen-typedef-decls`/`-gen-typedef-defs` to CMakeLists.txt
3. Include generated files in CIROps.h
4. Register types in `CIRDialect::initialize()`
5. Add custom `parseType()`/`printType()` in CIRDialect.cpp

### Adding a new pass

Reference: `~/claude/references/flang-ref/flang/lib/Optimizer/CodeGen/CodeGen.cpp`

1. Add `createXxxPass()` to `libcot/include/COT/Passes.h`
2. Implement in `libcot/lib/Xxx.cpp`
3. Add `populateXxxPatterns()` if conversion-based
4. Register in driver's PassManager pipeline

---

## Audit Checklist (run before major milestones)

- [ ] All ops use appropriate base class (`CIR_BinaryOp`, `CIR_IntBinaryOp`, `CIR_IntUnaryOp`, or custom)
- [ ] All ops have correct type constraints (no `AnyType` on integer-only ops)
- [ ] All lowering patterns registered in `populateCIRToLLVMConversionPatterns()`
- [ ] `dependentDialects` up to date in CIRDialect.td
- [ ] No frontend code emitting LLVM dialect ops directly
- [ ] No `std::system()`, `std::ifstream`, or hardcoded paths in driver
- [ ] All tests pass: `bin/lit test/lit/ -v`, `cot test`, `test/run.sh`
- [ ] CIR text output is readable (named predicates, not magic numbers)
