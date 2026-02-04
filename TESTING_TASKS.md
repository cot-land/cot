# Testing Framework Implementation Tasks

Quick reference checklist for implementing the testing framework. See `TESTING_FRAMEWORK_PLAN.md` for full details.

---

## Phase 1: Source Location Tracking

- [ ] **1.1** Add `SourceLoc` struct to `compiler/ssa/value.zig`
- [ ] **1.2** Add `loc` field to `Value` struct
- [ ] **1.3** Update `SSABuilder` to propagate locations from AST
- [ ] **1.4** Create `compiler/core/sourcemap.zig`
- [ ] **1.5** Wire source maps into Wasm codegen
- [ ] **1.6** Wire source maps into Native codegen

## Phase 2: Pretty Output

- [ ] **2.1** Create `compiler/core/pretty.zig`
- [ ] **2.2** Add color support with `NO_COLOR` env var
- [ ] **2.3** Add TTY detection
- [ ] **2.4** Create `compiler/test/formatter.zig`

## Phase 3: Runtime Error Handling

- [ ] **3.1** Add `assert()` builtin to parser
- [ ] **3.2** Implement `__cot_assert_fail` for Wasm
- [ ] **3.3** Implement `__cot_assert_fail` for Native
- [ ] **3.4** Create `compiler/runtime/stacktrace.zig`
- [ ] **3.5** Wire stack traces into assertion failures

## Phase 4: Inline Test Syntax

- [ ] **4.1** Add `test` keyword to scanner
- [ ] **4.2** Add `test_decl` node to AST
- [ ] **4.3** Parse `test "name" { ... }` syntax
- [ ] **4.4** Create `compiler/test/harness.zig`
- [ ] **4.5** Generate test harness main function

## Phase 5: E2E Test Suite

- [ ] **5.1** Create `tests/e2e/all_tests.cot`
- [ ] **5.2** Port Tier 1-6 tests (basic functionality)
- [ ] **5.3** Port Tier 7-15 tests (compound types)
- [ ] **5.4** Port Tier 16-26 tests (advanced features)
- [ ] **5.5** Create `compiler/test/parity_runner.zig`
- [ ] **5.6** Set up CI with `.github/workflows/test.yml`

## Phase 6: Integration

- [ ] **6.1** Add `test-e2e-wasm` step to `build.zig`
- [ ] **6.2** Add `test-e2e-native` step to `build.zig`
- [ ] **6.3** Add `test-parity` step to `build.zig`
- [ ] **6.4** Add `cot test` CLI subcommand
- [ ] **6.5** Implement `--filter`, `--target`, `--verbose` flags

---

## Quick Start: Minimum Viable Testing

To get TDD working with minimal effort, implement in this order:

1. **Phase 5.1-5.2** - Port first 30 tests to `tests/e2e/all_tests.cot`
2. **Phase 2.1** - Basic pretty output
3. **Phase 6.1-6.2** - Build system integration

This gives you a working E2E test suite immediately. Then add features incrementally:

- **Week 2**: Add source locations (Phase 1)
- **Week 3**: Add inline tests (Phase 4)
- **Week 4**: Add parity testing (Phase 5.5)
- **Week 5**: Polish (Phase 3, remaining tasks)

---

## Files to Create

| File | Purpose |
|------|---------|
| `compiler/core/sourcemap.zig` | Map code offsets to source lines |
| `compiler/core/pretty.zig` | Colored terminal output |
| `compiler/test/formatter.zig` | Format test results |
| `compiler/test/harness.zig` | Generate test main() |
| `compiler/test/parity_runner.zig` | Run same test on Wasm + Native |
| `compiler/runtime/assert.zig` | Runtime assertion support |
| `compiler/runtime/stacktrace.zig` | Stack trace capture |
| `tests/e2e/all_tests.cot` | 166+ E2E tests |
| `.github/workflows/test.yml` | CI configuration |

---

## Current Status

### Native AOT Bugs (from NATIVE_AOT_FIXES.md)

| Feature | Status |
|---------|--------|
| Return constant | ✅ Works |
| Simple expression | ✅ Works |
| Local variables | ✅ FIXED |
| Function calls (0 params) | ✅ FIXED |
| Function calls (1 param) | ✅ FIXED |
| Function calls (2+ params) | ✅ FIXED |
| If/else | ✅ FIXED |
| While loops | ✅ FIXED |
| Recursion | ✅ **FIXED** (Feb 5, 2026) |
| Structs (local) | ✅ Works |
| Structs (as params) | ✅ **FIXED** (Feb 5, 2026) |
| Pointers (read/write) | ✅ Works |
| Pointer arithmetic | ✅ **FIXED** (Feb 5, 2026) |
| Arrays | ✅ Works |

**Note:** Native AOT is now feature-complete for basic programs. Remaining issues are in Wasm codegen, not native.
