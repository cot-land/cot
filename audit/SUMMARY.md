# Audit Summary

## Overall Status: IN PROGRESS

**32 of 43 files refactored.** 11 files not yet in 0.3.

regalloc.zig has a memory corruption bug blocking test suite.

---

## Refactor Progress

| Category | Refactored | Remaining | Notes |
|----------|------------|-----------|-------|
| Core | 4/4 | 0 | Complete |
| Frontend | 11/11 | 0 | Complete |
| SSA | 15/15 | 0 | Complete |
| SSA Passes | 3/4 | 1 | lower.zig not started |
| Object Files | 0/3 | 3 | Not started |
| Codegen | 0/6 | 6 | Not started |
| Pipeline | 1/2 | 1 | driver.zig not started |
| **Total** | **34/45** | **11** | 76% complete |

---

## Files NOT YET IN 0.3

These files exist in 0.2 but haven't been refactored:

| File | 0.2 Lines |
|------|-----------|
| ssa/passes/lower.zig | 322 |
| obj/macho.zig | 1,175 |
| obj/elf.zig | 784 |
| dwarf.zig | 475 |
| driver.zig | 707 |
| codegen/generic.zig | 308 |
| codegen/arm64.zig | 3,589 |
| codegen/amd64.zig | 3,946 |
| arm64/asm.zig | 989 |
| amd64/asm.zig | 1,628 |
| amd64/regs.zig | 218 |
| **Total remaining** | **~14,000** |

---

## Audit Files (30/30 complete)

### Core (4/4)
- [x] core/errors.zig.md
- [x] core/target.zig.md
- [x] core/testing.zig.md
- [x] core/types.zig.md

### Frontend (11/11)
- [x] frontend/ast.zig.md
- [x] frontend/checker.zig.md
- [x] frontend/errors.zig.md
- [x] frontend/ir.zig.md
- [x] frontend/lower.zig.md
- [x] frontend/parser.zig.md
- [x] frontend/scanner.zig.md
- [x] frontend/source.zig.md
- [x] frontend/ssa_builder.zig.md
- [x] frontend/token.zig.md
- [x] frontend/types.zig.md

### SSA (15/15)
- [x] ssa/abi.zig.md
- [x] ssa/block.zig.md
- [x] ssa/compile.zig.md
- [x] ssa/debug.zig.md
- [x] ssa/dom.zig.md
- [x] ssa/func.zig.md
- [x] ssa/liveness.zig.md
- [x] ssa/op.zig.md
- [x] ssa/regalloc.zig.md
- [x] ssa/stackalloc.zig.md
- [x] ssa/test_helpers.zig.md
- [x] ssa/value.zig.md
- [x] ssa/passes/decompose.zig.md
- [x] ssa/passes/expand_calls.zig.md
- [x] ssa/passes/schedule.zig.md

---

## Refactored Files Summary

| File | 0.2 | 0.3 | Reduction |
|------|-----|-----|-----------|
| core/errors.zig | 291 | 195 | 33% |
| core/target.zig | 132 | 103 | 22% |
| core/testing.zig | 170 | 121 | 29% |
| core/types.zig | 548 | 265 | 52% |
| frontend/ast.zig | 764 | 332 | 57% |
| frontend/checker.zig | 2167 | 936 | 57% |
| frontend/errors.zig | 346 | 223 | 36% |
| frontend/ir.zig | 1751 | 548 | 69% |
| frontend/lower.zig | 3488 | 2295 | 34% |
| frontend/parser.zig | 1814 | 881 | 51% |
| frontend/scanner.zig | 753 | 461 | 39% |
| frontend/source.zig | 336 | 226 | 33% |
| frontend/ssa_builder.zig | 3044 | 1176 | 61% |
| frontend/token.zig | 465 | 289 | 38% |
| frontend/types.zig | 896 | 396 | 56% |
| ssa/abi.zig | 704 | 387 | 45% |
| ssa/block.zig | 449 | 228 | 49% |
| ssa/compile.zig | 547 | 218 | 60% |
| ssa/debug.zig | 645 | 352 | 45% |
| ssa/dom.zig | 395 | 255 | 35% |
| ssa/func.zig | 650 | 257 | 60% |
| ssa/liveness.zig | 947 | 947 | 0% |
| ssa/op.zig | 1569 | 366 | 77% |
| ssa/regalloc.zig | 1472 | 859 | 42% |
| ssa/stackalloc.zig | 493 | 363 | 26% |
| ssa/test_helpers.zig | 359 | 164 | 54% |
| ssa/value.zig | 673 | 259 | 62% |
| ssa/passes/decompose.zig | 477 | 285 | 40% |
| ssa/passes/expand_calls.zig | 662 | 256 | 61% |
| ssa/passes/schedule.zig | 193 | 234 | +21% |

**Refactored total: ~26,000 → ~13,000 (50% reduction)**

---

## New in 0.3 (no 0.2 equivalent)

| File | Lines | Purpose |
|------|-------|---------|
| main.zig | 57 | Entry point |
| pipeline_debug.zig | 153 | Debug infrastructure |
| frontend/e2e_test.zig | 946 | End-to-end tests |
| frontend/integration_test.zig | 267 | Integration tests |

---

## Issues

### Broken
| File | Issue |
|------|-------|
| ssa/regalloc.zig | Memory corruption in getLiveOut after saveEndRegs |

### Needs Investigation
| File | Issue |
|------|-------|
| ssa/liveness.zig | 0% reduction - may need review |
| ssa/passes/schedule.zig | +21% growth - may need review |

---

## Priority

1. **Fix regalloc.zig memory corruption** - BLOCKING
2. Complete remaining 11 files
3. Run full test suite
