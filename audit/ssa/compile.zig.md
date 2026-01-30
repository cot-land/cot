# Audit: ssa/compile.zig

## Status: VERIFIED CORRECT

| Metric | Value |
|--------|-------|
| 0.2 lines | 548 |
| 0.3 lines | 219 |
| Reduction | 60% |
| Tests | 3/3 pass |

---

## Architectural Change

**0.2** modeled Go's full 48-pass infrastructure with premature abstractions.
**0.3** is radically simpler - focuses only on the 5 actual passes needed.

### 0.2 Architecture (Removed)

| Component | Lines | Status |
|-----------|-------|--------|
| PassFn, AnalysisKind, Pass struct | 67 | REMOVED |
| Config struct | 17 | REMOVED |
| PassStats struct | 30 | REMOVED |
| Phase enum (12 phases) | 27 | REMOVED |
| Pass registry (12 Pass structs) | 72 | REMOVED |
| Stub implementations (12 passes) | 88 | REMOVED |
| HTMLWriter | 94 | REMOVED |

### 0.3 Architecture (New)

| Component | Lines | Purpose |
|-----------|-------|---------|
| CompileResult | 24 | Holds regalloc + stack results |
| compile() | 37 | Orchestrates 5 passes |
| Individual pass entry points | 35 | expandCalls, decompose, etc. |
| Tests | 44 | Lifecycle + ordering |

---

## Function-by-Function Verification

### New Functions (0.3)

| Function | Lines | Purpose |
|----------|-------|---------|
| CompileResult.deinit() | 3 | Resource cleanup |
| CompileResult.frameSize() | 3 | Get frame size for codegen |
| CompileResult.spillLive() | 3 | Get spill info for codegen |
| compile() | 37 | Run 5 passes in order |
| prepareForRegalloc() | 5 | Run pre-regalloc passes |
| expandCalls() | 3 | Delegate to expand_calls.zig |
| decompose() | 3 | Delegate to decompose.zig |
| schedule() | 3 | Delegate to schedule.zig |
| regalloc() | 3 | Delegate to regalloc.zig |
| stackalloc() | 5 | Delegate to stackalloc.zig |

### Removed Functions (0.2)

| Function | Lines | Reason |
|----------|-------|--------|
| earlyDeadcode() | 17 | Stub - not needed |
| earlyCopyElim() | 13 | Stub - not implemented |
| opt() | 5 | Stub - not implemented |
| genericCSE() | 5 | Stub - not implemented |
| prove() | 5 | Stub - not implemented |
| nilCheckElim() | 5 | Stub - not implemented |
| lower() | 5 | Stub - not implemented |
| lateLower() | 5 | Stub - not implemented |
| critical() | 6 | Stub - not implemented |
| layout() | 4 | Trivial flag set |
| schedule() | 4 | Now in passes/schedule.zig |
| regalloc() | 5 | Now in regalloc.zig |
| runPass() | 9 | Not needed without registry |
| HTMLWriter.* | 94 | Removed - use pipeline_debug |

### Removed Types (0.2)

| Type | Lines | Reason |
|------|-------|--------|
| PassFn | 1 | Not needed |
| AnalysisKind | 9 | Never used |
| Pass | 33 | Not needed |
| Config | 17 | Use pipeline_debug |
| PassStats | 30 | Never used |
| Phase | 27 | Not needed |
| passes array | 72 | Not needed |
| HTMLWriter | 94 | Use debug.zig |

### Tests (3/3)

| Test | 0.2 | 0.3 | Verdict |
|------|-----|-----|---------|
| compile passes exist | Check registry | N/A | REMOVED |
| early deadcode removes unused | Test stub | N/A | REMOVED |
| CompileResult lifecycle | N/A | Check struct | NEW |
| pass ordering constraints | N/A | Document order | NEW |
| prepareForRegalloc | N/A | Run passes | NEW |

---

## Pass Ordering (0.3)

```
expand_calls BEFORE decompose  (calls need ABI handling first)
decompose BEFORE schedule      (values must be register-sized)
schedule BEFORE regalloc       (regalloc needs deterministic order)
regalloc BEFORE stackalloc     (stackalloc uses spill info)
```

---

## Real Improvements

1. **60% reduction** - Removed 329 lines of premature abstraction
2. **Single responsibility** - Just orchestrates 5 actual passes
3. **No stubs** - Every pass does real work
4. **CompileResult pattern** - Clean contract with codegen
5. **Uses pipeline_debug** - Consistent debug output
6. **Pass modules separated** - Each pass in its own file

## What Actually Changed

**Complete rewrite** - The 0.2 and 0.3 versions share almost no code because:
- 0.2 was a premature port of Go's 48-pass infrastructure
- 0.3 is a minimal 5-pass pipeline for actual functionality

The 5 passes in 0.3 (`expand_calls`, `decompose`, `schedule`, `regalloc`, `stackalloc`) are real implementations, while 0.2's 12 passes were mostly stubs.

---

## Verification

```
$ zig build test
248/248 tests passed
```

**VERIFIED: Complete architectural simplification. 60% reduction. Real passes instead of stubs.**
