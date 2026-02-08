# Native AOT Fixes Required

## Executive Summary

**Status: Native AOT is NOT production-ready.**

On February 4, 2026, E2E testing revealed that native AOT compilation only works for the most trivial cases. The documentation was prematurely updated to claim "Native AOT Done" when in reality:

| Feature | Status |
|---------|--------|
| Return constant (`return 42`) | ✅ Works |
| Return simple expression (`return 10 + 5`) | ✅ Works |
| Local variables (`let x = 10`) | ✅ **FIXED** (Feb 5, 2026) |
| Function calls (no params) | ✅ **FIXED** (Feb 4, 2026) |
| Nested function calls | ✅ **FIXED** (Feb 5, 2026) |
| Function calls (2+ params) | ✅ **FIXED** (Feb 5, 2026) |
| Function calls (1 param) | ✅ **FIXED** (Feb 5, 2026) |
| If/else control flow | ✅ **FIXED** (Feb 5, 2026) |
| While loops | ✅ **FIXED** (Feb 5, 2026) |
| Params + early return | ✅ **FIXED** (Feb 5, 2026) |
| Recursion | ✅ **FIXED** (Feb 5, 2026) |
| Structs (local) | ✅ Works |
| Structs (as params) | ✅ **FIXED** (Feb 5, 2026) - Wasm codegen |
| Pointers (read/write) | ✅ Works |
| Pointer arithmetic | ✅ **FIXED** (Feb 5, 2026) - Wasm codegen |
| Arrays | ✅ Works |
| Multiple/sequential calls | ✅ **FIXED** (Feb 5, 2026) |

**Feb 5 update (PM):** Fixed vmctx pinned register - params + early return pattern now works.
- vmctx is now moved to x21 at function entry, excluded from register allocation

**Feb 5 update (late PM):** Fixed if/else with early return pattern AND recursion.
- translateEnd now has two-path logic matching Cranelift exactly (reachable vs unreachable handlers)
- Fixed call_ind register allocation (mutable pointer for allocation application)
- Fixed callee-saved register preservation across calls (x19-x28 save/restore in prologue/epilogue)

---

## CRITICAL: Methodology for ALL Fixes

> **READ THIS BEFORE EVERY TASK**

Every fix in this document MUST follow the process in `TROUBLESHOOTING.md`. The summary:

1. **NEVER invent logic** - If you're reasoning about what code "should" do, STOP
2. **ALWAYS find reference** - Every line of native codegen is ported from Cranelift
3. **ALWAYS copy exactly** - Translate Rust→Zig syntax, but preserve ALL logic
4. **NEVER simplify** - Even if reference code seems unnecessarily complex, copy it

**Reference locations for native AOT:**

| Our Code | Reference Code |
|----------|----------------|
| `compiler/codegen/native/wasm_to_clif/` | `~/learning/wasmtime/crates/cranelift/src/translate/` |
| `compiler/codegen/native/wasm_to_clif/translator.zig` | `~/learning/wasmtime/crates/cranelift/src/translate/code_translator.rs` |
| `compiler/codegen/native/wasm_to_clif/func_translator.zig` | `~/learning/wasmtime/crates/cranelift/src/translate/func_translator.rs` |
| `compiler/codegen/native/wasm_to_clif/stack.zig` | `~/learning/wasmtime/crates/cranelift/src/translate/state.rs` |
| `compiler/ir/clif/` | `~/learning/wasmtime/cranelift/codegen/src/ir/` |
| `compiler/codegen/native/machinst/` | `~/learning/wasmtime/cranelift/codegen/src/machinst/` |
| `compiler/codegen/native/isa/aarch64/` | `~/learning/wasmtime/cranelift/codegen/src/isa/aarch64/` |

---

## Task 0: Create Native E2E Test Infrastructure

**Priority: HIGHEST - Do this first**

Before fixing any bugs, we need a test harness that:
1. Compiles Cot source → native executable
2. Runs the executable
3. Checks the exit code matches expected value

**Location:** Create `compiler/codegen/native_e2e_test.zig`

**Model after:** `compiler/codegen/wasm_e2e_test.zig`

**Test cases to include (start with failing ones):**
```
test_return_42        -> expect 42
test_return_add       -> expect 15 (10 + 5)
test_local_var        -> expect 15 (let x=10; let y=5; return x+y)
test_func_no_params   -> expect 5 (fn get_five() -> return 5; fn main -> return get_five())
test_func_one_param   -> expect 20 (fn double(x) -> x+x; fn main -> return double(10))
test_func_two_params  -> expect 15 (fn add(a,b) -> a+b; fn main -> return add(10,5))
test_if_true          -> expect 1 (if 10 > 5 { return 1 } else { return 0 })
test_if_false         -> expect 0 (if 5 > 10 { return 1 } else { return 0 })
test_while_sum        -> expect 55 (sum 1 to 10)
```

**DO NOT invent the test harness design.** Look at how Cranelift's filetest infrastructure works:
- Reference: `~/learning/wasmtime/cranelift/filetests/`

---

## Task 1: Fix Stack Underflow in Function Calls ✅ FIXED

**Status:** FIXED on February 4, 2026

**Original Error:** Functions calling other functions would hang in infinite loop

**Root Cause Analysis:**

The issue was NOT a stack underflow in Wasm→CLIF translation. The actual issue was:

1. Functions that make calls need to save the link register (x30/LR) in the prologue
2. Without saving LR, after a `bl` instruction overwrites x30 with the return address
3. When main's `ret` executed, x30 still pointed to main's `ret` → infinite loop!

**Fix Applied (Following TROUBLESHOOTING.md methodology):**

1. **Found reference:** `cranelift/codegen/src/machinst/vcode.rs:687-745` - `compute_clobbers_and_function_calls()`
2. **Found reference:** `cranelift/codegen/src/isa/aarch64/abi.rs:1158` - checks `function_calls != .None`
3. **Copied pattern exactly:**

**Changes made:**

| File | Change |
|------|--------|
| `compiler/codegen/native/isa/aarch64/inst/mod.zig` | Added `callType()` method to classify call instructions |
| `compiler/codegen/native/isa/x64/inst/mod.zig` | Added `callType()` method to classify call instructions |
| `compiler/codegen/native/machinst/vcode.zig` | Added scanning for calls + prologue/epilogue emission |

**Prologue emitted when `function_calls != .None`:**
```asm
stp x29, x30, [sp, #-16]!   ; Save FP and LR
mov x29, sp                  ; Set up frame pointer
```

**Epilogue emitted before `ret` instructions:**
```asm
ldp x29, x30, [sp], #16     ; Restore FP and LR
```

**Test result:** `fn get_five() -> 5; fn main() -> get_five()` returns exit code 5 ✅

---

## Task 2: Fix Local Variables (SIGSEGV) ✅ FIXED

**Error observed:**
```
Exit: 139 (SIGSEGV)
```

**When:** Running native executable compiled from:
```cot
fn main() int {
    let x = 10;
    let y = 5;
    return x + y;
}
```

### Root Cause Analysis (February 4, 2026)

**The problem is NOT in Wasm→CLIF translation.** Locals are correctly translated to CLIF Variables using `builder.useVar()` and `builder.defVar()`.

**The problem is in Wasm codegen → native execution:**

1. Cot compiles to Wasm with **SP-based stack frames in linear memory**
   - `compiler/codegen/wasm/gen.zig` computes `frame_size`
   - Locals are stored at `SP + offset` in Wasm linear memory

2. The Wasm is then AOT compiled to native, but the native code still expects:
   - Global SP to exist at a known memory location
   - Linear memory to be allocated starting at some base address

3. **The stub in `lower.zig:2147`** uses hardcoded `0x10000` for vmctx_base:
   ```zig
   const vmctx_base: u64 = 0x10000;  // STUB - doesn't exist!
   ```

4. Generated code tries to load/store at addresses like `0x20000` → **SIGSEGV**

### Fix Approach (Following TROUBLESHOOTING.md)

**Option A: Add runtime memory initialization** (Wasmtime approach)
- Add BSS section with memory for Wasm linear memory
- Add startup code to initialize SP
- Update vmctx_base to point to actual memory

**Option B: Change codegen to avoid Wasm memory for locals**
- Would require major changes to Wasm codegen
- Not recommended - breaks Wasm semantics

**Reference:** Look at how Wasmtime initializes `VMContext` in `wasmtime/crates/runtime/src/vmcontext.rs`

### Our files to modify:
- `compiler/codegen/native/isa/aarch64/lower.zig` (vmctx_base)
- `compiler/codegen/native/object_module.zig` (add data section)
- `compiler/driver.zig` (coordinate memory setup)

### Architectural Challenge

The fix is complex because:
1. `lower.zig` generates hardcoded `mov x0, #0x10000` instructions
2. This needs to become a **relocation** to a symbol (e.g., `__wasm_memory`)
3. That symbol needs to be defined as a data section in the object file
4. The memory needs to be initialized (at least SP set to a valid offset)

This requires changes at multiple levels:
- CLIF IR generation (reference symbol instead of constant)
- Lowering (emit relocation instead of immediate)
- Object file (add BSS/data section)

**Complexity: HIGH** - Affects core memory model for native AOT

### Fix Applied (February 5, 2026)

**Solution:** Ported Cranelift vmctx pattern - generate _main wrapper that initializes static vmctx.

**Changes:**
| File | Change |
|------|--------|
| `compiler/driver.zig` | Generate _main wrapper with ADRP/ADD/BL, static vmctx buffer |
| `compiler/codegen/native/wasm_to_clif/func_translator.zig` | Add vmctx params to wasm function signatures |
| `compiler/codegen/native/wasm_to_clif/translator.zig` | Offset param indices by 2 for vmctx params |
| `compiler/codegen/native/isa/aarch64/lower.zig` | VMContext GlobalValue uses vmctx parameter |
| `compiler/codegen/native/macho.zig` | Fix extern bit for symbol-based relocations |

**Test result:** `let x = 10; return x` returns 10 ✅

---

## Task 3: Fix Function Calls with Parameters ✅ FIXED

**Status (Feb 5, 2026):** ALL parameter counts now work (0, 1, 2+ params).

### Test cases:
```cot
fn get_five() i64 { return 5 }
fn main() i64 { return get_five() }  // Returns 5 ✅

fn identity(n: i64) i64 { return n }
fn main() i64 { return identity(42) }  // Returns 42 ✅

fn add(a: i64, b: i64) i64 { return a + b }
fn main() i64 { return add(10, 5) }  // Returns 15 ✅
```

### Root Cause (Single-param crash)

The crash occurred in `ValueListPool.push()` when copying old values from the pool:

```zig
// BUG: getSlice() returns pointer to self.data.items
const old_values = self.getSlice(list);
// Then append() may reallocate, invalidating old_values!
try self.data.append(self.allocator, ...);
for (old_values) |v| {  // CRASH: old_values is stale pointer
    try self.data.append(self.allocator, v.index);
}
```

### Fix Applied (Following TROUBLESHOOTING.md methodology)

1. **Found reference:** `~/learning/wasmtime/cranelift/entity/src/list.rs` (EntityList implementation)
2. **Identified difference:** Cranelift modifies lists in-place and handles reallocation carefully
3. **Applied fix:** Use indices instead of pointers to safely copy old values:

```zig
// Get old list data using INDICES, not pointers
const old_len = if (list.isEmpty()) 0 else self.data.items[list.base];
const old_start = list.base + 1;
// Copy by re-reading from self.data.items each iteration (safe)
for (0..old_len) |i| {
    const old_value_index = self.data.items[old_start + i];
    try self.data.append(self.allocator, old_value_index);
}
```

**File changed:** `compiler/ir/clif/dfg.zig` (ValueListPool.push and remove)

---

## Task 4: Fix If/Else Control Flow (SIGSEGV)

**Error observed:**
```
Exit: 139 (SIGSEGV)
```

**When:** Running native executable compiled from:
```cot
fn main() int {
    let x = 10;
    if x > 5 {
        return 1;
    } else {
        return 0;
    }
}
```

**Pipeline stage:** Control flow translation or branch emission

**Our files:**
- `compiler/codegen/native/wasm_to_clif/translator.zig` (br_if, if, else, end)
- `compiler/codegen/native/isa/aarch64/lower.zig` (branch lowering)

**Reference files:**
- `~/learning/wasmtime/crates/cranelift/src/translate/code_translator.rs`
- `~/learning/wasmtime/cranelift/codegen/src/isa/aarch64/lower.isle`

### Investigation Steps (Follow TROUBLESHOOTING.md)

1. **Note:** This might be the same root cause as Task 2 (local variables)
   - If local variables are broken, `let x = 10` will fail
   - Fix Task 2 first, then re-test this

2. **If still broken after Task 2:**
   - Disassemble and find crash point
   - Check branch instruction encoding
   - Compare with Cranelift's branch emission

3. **Check control flow translation:**
   - How does Cranelift translate Wasm `if`?
   - How does Cranelift handle block parameters?
   - How does Cranelift handle `end`?

4. **DO NOT guess.** Find reference and copy.

---

## Task 5: Test and Fix While Loops

**Not yet tested** - likely broken if control flow is broken.

**Test code:**
```cot
fn main() int {
    let sum = 0;
    let i = 1;
    while i <= 10 {
        sum = sum + i;
        i = i + 1;
    }
    return sum;  // expect 55
}
```

**Wait until Tasks 2-4 are fixed before testing.**

---

## Task 6: Test and Fix Recursion

**Not yet tested** - depends on function calls working.

**Test code:**
```cot
fn factorial(n: int) int {
    if n <= 1 {
        return 1;
    }
    return n * factorial(n - 1);
}

fn main() int {
    return factorial(5);  // expect 120
}
```

**Wait until Tasks 1-4 are fixed before testing.**

---

## Task 7: Test and Fix Structs

**Not yet tested** - likely broken.

**Test code:**
```cot
struct Point {
    x: int,
    y: int,
}

fn main() int {
    let p = Point { x: 10, y: 20 };
    return p.x + p.y;  // expect 30
}
```

**Reference for struct handling:**
- `~/learning/wasmtime/crates/cranelift/src/translate/code_translator.rs` (memory operations)

---

## Task 8: Test and Fix Pointers

**Not yet tested** - likely broken.

**Test code:**
```cot
fn main() int {
    let x = 10;
    let p = &x;
    return *p;  // expect 10
}
```

---

## Order of Operations

1. **Task 0** - Create test infrastructure (required for all other tasks)
2. **Task 1** - Fix compiler panic (can't test anything if compiler crashes)
3. **Task 2** - Fix local variables (most basic feature after constants)
4. **Task 3** - Fix function calls (needed for interesting programs)
5. **Task 4** - Fix if/else (may be fixed by Task 2)
6. **Task 5** - Test loops (may be fixed by earlier tasks)
7. **Task 6** - Test recursion (depends on Tasks 3-4)
8. **Task 7** - Test structs (memory operations)
9. **Task 8** - Test pointers (memory operations)

---

## Success Criteria

Native AOT can only be called "done" when:

1. All tests in `native_e2e_test.zig` pass
2. Test coverage matches `wasm_e2e_test.zig` coverage
3. The same Cot programs produce the same results on both Wasm and native targets

---

## Reminder: The Process

Before making ANY change, verify:

- [ ] I identified which pipeline stage has the bug
- [ ] I found the exact reference file for this stage
- [ ] I found the exact function in the reference
- [ ] I did a line-by-line comparison
- [ ] I found a difference between our code and reference
- [ ] My change copies the reference pattern exactly
- [ ] I did NOT invent any new logic

**If you cannot check all boxes, STOP and find the reference.**

---

## Task 9: Fix vmctx Register Preservation (SIGSEGV) ✅ FIXED

**Status:** FIXED on February 5, 2026

**Error observed:**
```
Exit: 139 (SIGSEGV)
```

**When:** Running native executable compiled from functions with parameters AND early returns:
```cot
fn check(n: i64) i64 { if n > 1 { return 99 } return 0 }
fn main() i64 { return check(5) }  // Should return 99, was SIGSEGV
```

### Root Cause Analysis

The issue was that vmctx (which provides access to Wasm linear memory, including the stack pointer) was being clobbered when control flow diverged.

**What was happening:**
1. vmctx comes in x0 as the first function parameter
2. Code paths that accessed SP correctly used vmctx from x0
3. But when control flow split (if/else with early return), the return block needed vmctx
4. By that point, x0 had been overwritten with the return value (99)
5. Code tried to use some other register (x4) for vmctx, which was never set
6. Accessing SP via garbage address → SIGSEGV

**Disassembly showed:**
```asm
10000068c: mov x0, #99      ; return value in x0
100000690: mov x1, x4       ; trying to use x4 as vmctx - but x4 was never set!
100000694: add x17, x1, #0x10000  ; SP access fails
```

### Fix Applied (Following TROUBLESHOOTING.md methodology)

**Reference files found:**
1. `~/learning/wasmtime/cranelift/codegen/src/isa/aarch64/inst/regs.rs:19` - `PINNED_REG = 21`
2. `~/learning/wasmtime/cranelift/codegen/src/isa/aarch64/lower.rs:130-131` - `maybe_pinned_reg()`
3. `~/learning/wasmtime/cranelift/codegen/src/isa/aarch64/abi.rs:1538-1634` - `create_reg_env()`
4. `~/learning/wasmtime/cranelift/codegen/src/isa/aarch64/lower.isle:2788-2792` - `get_pinned_reg`, `set_pinned_reg`

**Cranelift's solution:**
1. Reserve x21 as the "pinned register" for vmctx
2. At function entry, move vmctx from x0 to x21
3. Exclude x21 from register allocation (can't be clobbered)
4. When code needs vmctx, read from x21 (always available)

**Changes made:**

| File | Change |
|------|--------|
| `compiler/codegen/native/regalloc/env.zig` | Exclude x21 from allocatable registers (add `PINNED_REG = 21`, skip it in loop) |
| `compiler/codegen/native/isa/aarch64/lower.zig:maybePinnedReg()` | Return x21 instead of null |
| `compiler/codegen/native/isa/aarch64/lower.zig:genArgSetup()` | Emit `mov x21, x0` at function entry when vmctx exists |
| `compiler/codegen/native/isa/aarch64/lower.zig:lowerGlobalValue()` | For VMContext, return x21 directly instead of reading vmctx param |

**Disassembly after fix:**
```asm
100000578: mov x21, x0      ; Save vmctx to pinned register at function entry!
...
1000006a0: mov x0, #99      ; return value in x0
1000006a4: mov x1, x21      ; vmctx from pinned register (always valid!)
1000006a8: add x17, x1, #0x10000  ; SP access succeeds
```

**Test result:** `fn check(n) { if n > 1 { return 99 } return 0 }; check(5)` returns 99 ✅

---

## Task 10: Fix If Without Else and Nested Calls ✅ FIXED

**Status:** FIXED on February 5, 2026

**Error observed:**
```
Exit: 0 (should be 42)
```

**When:** Running native executable compiled from:
```cot
fn main() i64 {
    let n = 2
    if n <= 1 { return 1 }
    return 42
}
```

### Root Cause Analysis (Following TROUBLESHOOTING.md)

**Reference comparison revealed TWO issues:**

**Issue 1: translateEnd had incorrect two-path logic**

Cranelift has TWO separate End handlers:
1. **Reachable case (code_translator.rs:412-444)**: UNCONDITIONALLY emit jump, switch to next_block, seal
2. **Unreachable case (code_translator.rs:3389-3437)**: CONDITIONALLY switch based on `reachable_anyway`

Our code incorrectly used conditional logic even when entering with `self.state.reachable == true`.

**Issue 2: call_ind register allocation not applied**

In `get_operands.zig`, the `call_ind` handling created a local copy of `info.dest`:
```zig
// BUG: creates local copy, allocation written to copy not original
var dest_reg = info.dest;
visitor.regUse(&dest_reg);
```

The allocation callback would mutate `dest_reg`, but `info.dest` remained unchanged (virtual register).

### Fix Applied

**File 1: `compiler/codegen/native/wasm_to_clif/translator.zig`**

Rewrote `translateEnd` to have TWO completely separate paths:

1. When `self.state.reachable == true`: UNCONDITIONALLY emit jump, switch, seal, push params
2. When `self.state.reachable == false`: Calculate `reachable_anyway`, CONDITIONALLY switch/seal/push

This exactly matches Cranelift's two handler functions.

**File 2: `compiler/codegen/native/isa/aarch64/inst/get_operands.zig`**

Changed `call_ind` to pass reference to actual field:
```zig
// Pass reference to actual field, not a copy
visitor.regUse(&info.dest);
```

**File 3: `compiler/codegen/native/isa/aarch64/inst/mod.zig`**

Changed `call_ind.info` type from `*const CallIndInfo` to `*CallIndInfo` to allow mutation during allocation application.

**Test result:** `let n = 2; if n <= 1 { return 1 } return 42` returns 42 ✅

---

## Task 11: Fix Recursion (Callee-Saved Register Preservation) ✅ FIXED

**Status:** FIXED on February 5, 2026

**Error observed:**
```
factorial(5) returns 16 instead of 120
factorial(3) returns 4 instead of 6
```

**When:** Running recursive functions that use a value across a recursive call.

### Root Cause Analysis (Following TROUBLESHOOTING.md)

**Reference files:**
1. `~/learning/wasmtime/cranelift/codegen/src/machinst/vcode.rs:687-745` - `compute_clobbers_and_function_calls()`
2. `~/learning/wasmtime/cranelift/codegen/src/isa/aarch64/abi.rs:717-944` - `gen_clobber_save()`
3. `~/learning/wasmtime/cranelift/codegen/src/isa/aarch64/abi.rs:946-1032` - `gen_clobber_restore()`
4. `~/learning/wasmtime/cranelift/codegen/src/isa/aarch64/abi.rs:1277-1322` - `is_reg_saved_in_prologue()`

**The problem:**

Register allocator assigned `n` to x19 (callee-saved register) to preserve it across the recursive call. But our prologue/epilogue only saved FP (x29) and LR (x30), NOT x19.

**Disassembly showed:**
```asm
; Before call
ldr  x19, [sp+offset]      ; Load n into x19
...
bl   _factorial            ; Recursive call - CLOBBERS x19!
mul  x0, x19, x0           ; x19 is wrong value now!
```

When factorial called itself recursively, the inner call would load ITS `n` into x19, clobbering the outer call's value.

### Fix Applied

**File:** `compiler/codegen/native/machinst/vcode.zig`

Added callee-saved register computation and save/restore:

1. **Compute clobbered callee-saves** by scanning all regalloc allocations and edits, filtering to x19-x28
2. **Prologue**: Save clobbered callee-saves using `stp rt, rt2, [sp, #-16]!` (pairs) or `str rt, [sp, #-16]!` (odd)
3. **Epilogue**: Restore them using `ldp rt, rt2, [sp], #16` (pairs) or `ldr rt, [sp], #16` (odd)

**Generated prologue now:**
```asm
stp  x29, x30, [sp, #-16]!   ; Save FP and LR
mov  x29, sp                  ; Set FP
str  x19, [sp, #-16]!         ; Save callee-saved x19
```

**Generated epilogue now:**
```asm
ldr  x19, [sp], #16          ; Restore x19
ldp  x29, x30, [sp], #16     ; Restore FP and LR
ret
```

**Test result:** `factorial(5)` returns 120 ✅

---

## History

- **Feb 4, 2026 (AM)**: Fixed value aliases, jump table relocs, operand order - `return 42` works
- **Feb 4, 2026 (PM)**: E2E testing revealed most features still broken
- **Feb 5, 2026 (AM)**: Fixed vmctx wrapper - local variables, if/else, while loops now work
- **Feb 5, 2026 (PM)**: Fixed pinned register for vmctx - params + early return pattern works
  - Root cause: vmctx in x0 was clobbered by return value
  - Fix: Copy vmctx to x21 at function entry, exclude x21 from allocation
- **Feb 5, 2026 (late PM)**: Fixed if without else + nested call_indirect + recursion
  - Root cause 1: translateEnd used conditional logic when reachable (should be unconditional)
  - Root cause 2: call_ind register allocation written to local copy, not original
  - Root cause 3: Callee-saved registers (x19-x28) not saved/restored in prologue/epilogue
  - Fix: Match Cranelift's two-path End handler, pass mutable reference to info.dest
  - Fix: Add callee-save computation from regalloc output, emit stp/ldp for clobbered regs
- **Feb 5, 2026 (night)**: Fixed sequential/nested function calls SIGSEGV
  - Root cause: RedundantMoveEliminator incorrectly elided second call's vmctx move
  - The same vreg (vmctx) needed fixed_reg constraints for both x0 and x1
  - First call's move (x0 ← x1) was emitted correctly
  - Second call's move was ELIDED because eliminator tracked x0=x1 without accounting for call clobbers
  - Fix (v1): Conservative - clears ALL state when instructions exist between moves
  - Fix (v2): Proper Cranelift port from `src/ion/moves.rs:789-835` `redundant_move_process_side_effects`
    - MoveContext now generic over Function type, takes func and MachineEnv params
    - processRedundantMoveSideEffects iterates through instructions, clearing allocations for:
      - Def operands (registers being defined)
      - Clobbered registers (from instClobbers)
      - Scratch registers (from MachineEnv.scratch_by_class)
    - Matches Cranelift's granular approach instead of conservative full-clear
  - All 52 E2E tests now pass on both wasm and native targets
