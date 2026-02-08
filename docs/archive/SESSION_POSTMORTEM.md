# Session Postmortem: February 5, 2026

## Executive Summary

**47 commits in one day. Massive progress. Then context loss caused chaos.**

This document records what was achieved in ~10+ hours of work, and what went catastrophically wrong when Claude lost context and started behaving erratically.

---

## Part 1: What Was Achieved (47 commits)

### Native AOT Fixes (Morning Session)

The day started with native AOT being broken for anything beyond trivial cases. By midday, extensive fixes were completed:

| Commit | Fix | Impact |
|--------|-----|--------|
| `94cab3c` | Document native AOT progress | Baseline documentation |
| `89dedc6` | Fix single-param function crash (ValueListPool bug) | Functions with 1 param work |
| `4d6baa1` | vmctx pinned to x21 register | Params + early return works |
| `04e200c` | if/else control flow, call_ind regalloc, recursion | Control flow works |
| `9c7cfc4` | Document struct/pointer testing | Testing documentation |
| `b05cdcd` | Wasm codegen: pointer arithmetic, struct-by-value | Wasm fixes |
| `c36314a` | Sequential function calls, E2E test suite | Multiple calls work |
| `ab278ba` | Port processRedundantMoveSideEffects | Register allocation fix |
| `f1e8c43` | x64 global_value lowering | x64 backend |
| `2193ec0` | Mark Phase 7 complete | Milestone achieved |

### x64 Backend Work

| Commit | Fix |
|--------|-----|
| `2e01012` | Fix multiple x64 issues, remove ARM64 hardcoding |
| `9685267` | jmp_table_seq LEA displacement |
| `5b60022` | Register allocation callback for reuse |
| `9b6617d` | jmp_table_seq register overlap |
| `6362ec5` | IMUL instruction |
| `d54a3ef` | Port early_defs from Cranelift |
| `395496d` | Remove unused regUseLate |
| `139de6e` | Memory leak fixes |
| `9d83f98` | x64 Linux local variables and function calls |
| `5f5de79` | x64 division, comparison, jump offsets |
| `6d7c0f2` | x64 conditional branches, enable E2E tests |

### M17-M22 Milestones

| Commit | Milestone | Description |
|--------|-----------|-------------|
| `069953b` | M17 | Frontend emits retain/release for ARC |
| `b36bdfb` | M18 | Heap Allocation (new keyword) |
| `bfa1edd` | M21 | Array append builtin |
| `9b9b3d9` | M21 | Add capacity to slices (Go pattern) |
| `121967c` | M21 | Fix stack corruption, cap argument |
| `ac2b559` | M21 | Fix append to match Go exactly |
| `62d0b6c` | M22 | for-range index binding (for i, x in arr) |

### Infrastructure & Documentation

| Commit | Change |
|--------|--------|
| `ac8b7a8` | Add ARC insertion reference to TROUBLESHOOTING.md |
| `d0db035` | Add Pattern 4: no ISA-specific code in shared files |
| `11de9b3` | Make vcode.zig ISA-aware |
| `e86756c` | Fix ARM64 STP/LDP encoding |
| `c9c77e8` | Parse and initialize Wasm data segments |
| `938a46c` | Fix EntryLivein (Args instruction memory) |
| `5336232` | Separate Go slice functions from Swift ARC |
| `949367b` | Disable native_e2e_test.zig (slow, not broken) |
| `2d77fb3` | Fix memory leaks in native AOT |
| `138f577` | Remove obsolete planning documents |
| `a8c4407` | Fix skipped string dedup tests |
| `f359474` | Rewrite VISION.md accurately |

### Phase 3 Language Features (Afternoon/Evening Session)

| Commit | Wave | Features |
|--------|------|----------|
| `72e1fb4` | Plan | Add PHASE3_LANGUAGE_FEATURES.md |
| `0c8daa1` | Wave 1 | Bitwise ops, compound assign, type aliases, char literals |
| `8e6a464` | Wave 2 | Optional types with cond_select and const_nil |
| `c8c50eb` | Wave 3 | Enums, unions, switch expressions |
| `8ff8469` | Wave 3 | Add Go reference comments |
| `c02bc19` | Wave 4 | Methods on structs (impl blocks) |
| `a11937d` | Wave 3 | @intCast wasm codegen, builtins complete |

---

## Part 2: Final State After Good Work

**790 tests passing** (all Wasm E2E tests)

**Native AOT status:**
- ARM64: return, expressions, locals, function calls, if/else, loops, recursion, structs, pointers, arrays - ALL WORKING
- x64: Extensive fixes, E2E tests enabled
- Native E2E tests: Disabled in test framework due to 15s compile time (NOT broken)

**Phase 3 features on Wasm:**
- Wave 1-4 complete: bitwise, compound assign, type aliases, chars, optionals, enums, unions, switch, methods, builtins

---

## Part 3: What Went Wrong (Context Loss)

### The Trigger

A new conversation was started from a summary. The summary mentioned:
- F6 (imports) and F7 (extern functions) were "partial"
- Need to "complete them by porting from proven languages"

### What Claude Did Wrong

1. **Ignored existing work**: Instead of reading MEMORY.md, NATIVE_AOT_FIXES.md, or git history, Claude started implementing F6/F7 from scratch.

2. **Marked native as "?" or "❌"**: After 47 commits fixing native AOT, Claude marked ALL native features as untested/broken in PHASE3_LANGUAGE_FEATURES.md.

3. **Ran tests blindly**: Started spawning compilation processes that hung, without understanding why native_e2e_test.zig was disabled (it's slow, not broken).

4. **Lost all context**: Had no idea that:
   - Native AOT works for basic features
   - M17-M23 were complete
   - Extensive x64 work was done
   - 790 tests pass

5. **Ran multiple hanging processes**: Started multiple native compilations that hung (the methods test uses features that may not be tested on native yet), nearly crashing the user's computer.

### The Damage

1. **PHASE3_LANGUAGE_FEATURES.md** was modified to mark F6/F7 as complete with implementation evidence, but marked native as all "?" when extensive work was done.

2. **Time wasted**: User had to explain what was already done instead of making progress.

3. **Trust broken**: After 47 commits of careful work, Claude acted like a "new agent with zero idea what the project does."

---

## Part 4: What Should Have Happened

1. **Read MEMORY.md first** - It clearly states:
   - "Native AOT: Phase 0-7 complete, all 52 E2E tests pass"
   - "M17-M23 complete, 790 tests pass"

2. **Read NATIVE_AOT_FIXES.md** - Shows all native features as FIXED

3. **Check git log** - 47 commits showing extensive work

4. **Understand why native_e2e_test.zig is disabled** - It's slow (15s per test), not broken

5. **Test carefully** - Not spawn multiple processes blindly

---

## Part 5: Current State (Post-Chaos)

### What's Actually Working

**Wasm (790 tests pass):**
- All M1-M23 features
- All Phase 3 Wave 1-4 features
- F6 (imports) - was already working
- F7 (extern functions) - now wired to wasm import section

**Native (E2E tests disabled but work individually):**
- Basic: return, expressions, locals, calls ✅
- Control flow: if/else, loops, recursion ✅
- Data: structs, pointers, arrays ✅
- Phase 3 features: UNTESTED on native

### What Needs Verification

Phase 3 features (enums, unions, switch, methods) need to be tested on native. They compile to standard Wasm instructions, so they SHOULD work, but haven't been verified.

### Files Modified in Chaos

- `PHASE3_LANGUAGE_FEATURES.md` - F6/F7 marked complete (correct), but native status may be wrong
- `compiler/frontend/ir.zig` - Added ExternFunc struct
- `compiler/frontend/lower.zig` - Collect extern functions
- `compiler/driver.zig` - Wire extern to wasm imports
- `test/cases/extern/simple.cot` - New test file

---

## Part 6: Root Cause Analysis

**Why did Claude lose context?**

1. **Conversation compaction**: The previous conversation was summarized, losing detailed context about native AOT work.

2. **Summary focused on incomplete items**: F6/F7 being "partial" became the focus, ignoring everything that was complete.

3. **No proactive context gathering**: Claude should have read MEMORY.md, NATIVE_AOT_FIXES.md, and git history BEFORE doing anything.

4. **Overconfidence**: Claude started implementing without verifying what already existed.

**Why did Claude spawn hanging processes?**

1. **Didn't understand native compile time**: Each native compilation takes ~15 seconds.

2. **Didn't read why native_e2e_test.zig was disabled**: Clear comment explains it's slow, not broken.

3. **Tested methods without checking if it's native-compatible**: The methods feature was added for Wasm, native support wasn't verified.

---

## Part 7: Lessons Learned

1. **ALWAYS read MEMORY.md first** after conversation compaction

2. **ALWAYS check git log** to understand recent work

3. **NEVER mark features as broken without evidence**

4. **NEVER spawn multiple long-running processes**

5. **UNDERSTAND why tests are disabled** before trying to run them

6. **ASK the user** if context seems incomplete

---

## Appendix: The 47 Commits

```
a11937d Phase 3 Wave 3 complete: Add @intCast wasm codegen
c02bc19 Phase 3 Wave 4: Methods on structs (impl blocks)
c8c50eb Phase 3 Wave 3: Enums, unions, and switch expressions
8ff8469 Add Go reference comments for compound assignment and type aliases
8e6a464 Phase 3 Wave 2: Optional types with cond_select and const_nil
0c8daa1 Phase 3 Wave 1: Complete bitwise ops, compound assign, type aliases, char literals
72e1fb4 Add Phase 3 Language Features execution plan
f359474 Rewrite VISION.md with accurate phase status
a8c4407 Fix skipped string deduplication tests, remove M24
62d0b6c Complete M22: Add for-range index binding syntax (for i, x in arr)
138f577 Remove obsolete planning documents
2d77fb3 Fix memory leaks in native AOT compilation
949367b Disable native_e2e_test.zig with better explanation
ac2b559 Fix append to match Go's walkAppend exactly
5336232 Refactor: separate Go slice functions from Swift ARC
938a46c Fix EntryLivein error by fixing Args instruction memory ownership
121967c Fix M21 bugs: stack corruption and missing cap argument
6d7c0f2 Fix x64 conditional branches and comparisons, enable E2E tests
9b9b3d9 M21: Add capacity to slices (copy Go runtime/slice.go exactly)
11de9b3 Make vcode.zig ISA-aware for ARM64 and x64 prologue/epilogue
d0db035 Add Pattern 4 to TROUBLESHOOTING.md: no ISA-specific code in shared files
e86756c Fix ARM64 STP/LDP encoding and update milestone checklists
c9c77e8 Fix native AOT: parse and initialize Wasm data segments
bfa1edd Implement M21: Array append builtin
5f5de79 x64: Fix division, comparison, and jump offset issues
9d83f98 x64 Linux: Fix local variables and function calls for native AOT
139de6e x64: Add deinit for Inst/CallInfo/CallInfoUnknown to fix memory leaks
395496d Cleanup: Remove unused regUseLate function
d54a3ef Port early_defs from Cranelift for proper operand position handling
6362ec5 x64: Implement IMUL instruction for multiplication
9b6617d x64: Fix jmp_table_seq register overlap in emit
5b60022 x64: Fix register allocation callback for reuse patterns
9685267 x64: Fix jmp_table_seq LEA displacement and patch addend handling
2e01012 x64: Fix multiple backend issues and remove hardcoded ARM64 code
b36bdfb Complete M18: Heap Allocation (new keyword)
069953b Implement M17: Frontend emits retain/release for ARC
ac8b7a8 Add ARC insertion reference to TROUBLESHOOTING.md
2193ec0 Mark Phase 7 (Native AOT Integration) as complete
f1e8c43 x64: Add global_value lowering, fix get_operands hwEnc bug
ab278ba Port processRedundantMoveSideEffects from Cranelift
c36314a Fix native AOT sequential function calls and add E2E test suite
b05cdcd Fix Wasm codegen: pointer arithmetic and struct-by-value params
9c7cfc4 Update docs: Native AOT struct/pointer testing results
04e200c Fix native AOT: if/else control flow, call_ind regalloc, and recursion
4d6baa1 Fix native AOT vmctx preservation with pinned register (x21)
89dedc6 Fix native AOT single-param function crash (ValueListPool reallocation bug)
94cab3c Update NATIVE_AOT_FIXES.md with Feb 5 progress
7c0d552 Fix native AOT local variables SIGSEGV with vmctx wrapper
5467009 Document root cause analysis for local variables SIGSEGV
445d89b Fix native AOT function calls: add prologue/epilogue for link register
```
