# Liveness Analysis Audit: Cranelift/Regalloc2 Parity

**Date:** February 4, 2026
**Status:** FIXED
**Previously Failing Test:** "V2: compile function with control flow produces non-zero output"
**Previous Error:** `EntryLivein` - vregs 193 and 194 were live-in at entry block
**Resolution:** Implemented `InstValuesIterator` to match Cranelift's `inst_values()` behavior

## Executive Summary

The root cause is **NOT in liveness analysis itself** - it's in the lowering pass's `computeUseStates()` function. Our `instValues()` implementation diverges from Cranelift's by not including branch arguments, causing instructions whose results are only used as branch arguments to be skipped during lowering.

## Gap #1: DFG.instValues() Missing Branch Arguments (CRITICAL)

### Cranelift Implementation (Reference)
**File:** `/Users/johnc/learning/wasmtime/cranelift/codegen/src/ir/dfg.rs:897-920`

```rust
pub fn inst_values<'dfg>(
    &'dfg self,
    inst: Inst,
) -> impl DoubleEndedIterator<Item = Value> + 'dfg {
    self.inst_args(inst)                    // 1. Regular instruction args
        .iter()
        .copied()
        .chain(
            self.insts[inst]
                .branch_destination(&self.jump_tables, &self.exception_tables)
                .into_iter()
                .flat_map(|branch| {
                    branch
                        .args(&self.value_lists)   // 2. Branch destination args
                        .filter_map(|arg| arg.as_value())
                }),
        )
        .chain(
            self.insts[inst]
                .exception_table()
                .into_iter()
                .flat_map(|et| self.exception_tables[et].contexts()),  // 3. Exception contexts
        )
}
```

Cranelift's `inst_values()` returns **THREE** things chained:
1. Regular instruction arguments from `inst_args()`
2. **Branch destination arguments** - values passed to branch targets
3. Exception table contexts

### Our Implementation (Incorrect)
**File:** `compiler/ir/clif/dfg.zig:745-747`

```zig
/// Get the instruction input values (alias for instArgs).
pub fn instValues(self: *const Self, inst: Inst) []const Value {
    return self.instArgs(inst);  // ONLY returns regular args!
}
```

Our `instValues()` is just an alias for `instArgs()` - it does NOT include branch arguments.

### Impact

This causes `computeUseStates()` (in `lower.zig:1442-1520`) to not count uses that appear as branch arguments:

```zig
for (f.dfg.instValues(inst)) |arg| {  // Line 1483 - misses branch args!
    // ... count uses ...
}
```

Instructions like `iconst` whose results are ONLY used as branch arguments:
1. Never get their use counted (`ValueUseState.unused`)
2. `isAnyInstResultNeeded()` returns false
3. Instruction is not lowered
4. VReg is never defined
5. Liveness sees the vreg used as a branch argument but never defined
6. VReg appears live-in at some block
7. Eventually `EntryLivein` error

## Gap #2: instArgs() Handling of Branch Instructions

### Cranelift Implementation
**File:** (based on InstructionData pattern matching)

Branch instructions in Cranelift extract their condition argument AND their block call arguments separately. The `inst_args()` only returns the condition (for `brif`), while block call args are accessed via `branch_destination()`.

### Our Implementation
**File:** `compiler/ir/clif/dfg.zig:715-742`

```zig
pub fn instArgs(self: *const Self, inst: Inst) []const Value {
    return switch (data.*) {
        // ...
        .brif => |*d| @as(*const [1]Value, &d.arg)[0..1],  // Only condition
        .jump => &[_]Value{},  // No args (correct for jump)
        // ...
    };
}
```

This is actually correct - `instArgs` should only return the condition for `brif`. The issue is that `instValues` should ALSO include the branch destination arguments, which it doesn't.

## Gap #3: Liveness Analysis - Actually Correct

Our liveness analysis in `compiler/codegen/native/regalloc/liveness.zig` DOES correctly handle branch blockparams:

**Lines 459-466:**
```zig
// Include outgoing blockparams (branch arguments)
if (!insns.isEmpty() and func.isBranch(insns.last())) {
    const succs = func.blockSuccs(block);
    for (succs, 0..) |_, succ_idx| {
        for (func.branchBlockparams(block, insns.last(), succ_idx)) |param| {
            try live.set(param.vreg(), true);  // Correctly marks as live
        }
    }
}
```

This matches regalloc2's `compute_liveness` at lines 305-313:
```rust
if self.func.is_branch(insns.last()) {
    for i in 0..self.func.block_succs(block).len() {
        for &param in self.func.branch_blockparams(block, insns.last(), i) {
            live.set(param.vreg(), true);
        }
    }
}
```

**The liveness analysis is correct.** The problem is that the vregs (v193, v194) being used as branch arguments were never defined because the iconst instructions that define them were skipped during lowering.

## Execution Plan

### Phase 1: Fix instValues() to Include Branch Arguments

**File:** `compiler/ir/clif/dfg.zig`

1. Modify `instValues()` to iterate over both `instArgs()` AND branch destination arguments
2. Need to add a method similar to Cranelift's `branch_destination()` that returns the BlockCall values
3. Extract values from BlockCall args via `value_lists.getSlice()`

**Required changes:**

```zig
// NEW: Helper iterator or method to get all instruction values including branch args
pub fn instValues(self: *const Self, inst: Inst) InstValuesIterator {
    return InstValuesIterator.init(self, inst);
}

// InstValuesIterator that yields:
// 1. All values from instArgs(inst)
// 2. All values from branchDestination(inst) block call args
```

**Or simpler approach - modify computeUseStates() directly:**

In `lower.zig:1478-1515`, after iterating `f.dfg.instValues(inst)`, also iterate branch destination arguments for branch instructions.

### Phase 2: Verify branchDestination() Works Correctly

**File:** `compiler/ir/clif/inst.zig` (InstructionData)

Verify `branchDestination()` correctly returns BlockCall slices for all branch types:
- `.jump` - single BlockCall
- `.brif` - two BlockCalls (then/else)
- `.branch_table` - multiple BlockCalls

### Phase 3: Test the Fix

1. Run the failing test: "V2: compile function with control flow produces non-zero output"
2. Verify iconst instructions are now lowered
3. Verify no EntryLivein error
4. Run full test suite

### Phase 4: Remove Debug Code

Remove the extensive debug output added at lines 508-569 in `liveness.zig` once the bug is fixed.

## Files to Modify

| File | Change |
|------|--------|
| `compiler/ir/clif/dfg.zig` | Fix `instValues()` to include branch args OR add helper method |
| `compiler/codegen/native/machinst/lower.zig` | Alternative: Fix `computeUseStates()` to explicitly iterate branch args |
| `compiler/codegen/native/regalloc/liveness.zig` | Remove debug code after fix |

## Detailed Implementation Plan

### Option A: Fix `instValues()` in DFG (RECOMMENDED)

**File:** `compiler/ir/clif/dfg.zig`

The challenge is that Cranelift's `inst_values()` returns an iterator that chains multiple slices. In Zig, returning a slice requires contiguous memory. Two sub-options:

#### A1: Create an InstValuesIterator struct

```zig
/// Iterator over all values used by an instruction, including branch arguments.
/// Port of cranelift/codegen/src/ir/dfg.rs:897-920
pub const InstValuesIterator = struct {
    dfg: *const DataFlowGraph,
    inst: Inst,
    phase: enum { args, branch_args, done },
    arg_index: usize,
    branch_dest_index: usize,
    branch_arg_index: usize,

    pub fn init(dfg: *const DataFlowGraph, inst: Inst) InstValuesIterator {
        return .{
            .dfg = dfg,
            .inst = inst,
            .phase = .args,
            .arg_index = 0,
            .branch_dest_index = 0,
            .branch_arg_index = 0,
        };
    }

    pub fn next(self: *InstValuesIterator) ?Value {
        switch (self.phase) {
            .args => {
                const args = self.dfg.instArgs(self.inst);
                if (self.arg_index < args.len) {
                    const v = args[self.arg_index];
                    self.arg_index += 1;
                    return v;
                }
                self.phase = .branch_args;
                return self.next();
            },
            .branch_args => {
                const data = self.dfg.getInst(self.inst);
                const destinations = data.branchDestination(&self.dfg.jump_tables);
                while (self.branch_dest_index < destinations.len) {
                    const bc = destinations[self.branch_dest_index];
                    const args = self.dfg.value_lists.getSlice(bc.args);
                    if (self.branch_arg_index < args.len) {
                        const v = args[self.branch_arg_index];
                        self.branch_arg_index += 1;
                        return v;
                    }
                    self.branch_dest_index += 1;
                    self.branch_arg_index = 0;
                }
                self.phase = .done;
                return null;
            },
            .done => return null,
        }
    }
};

pub fn instValues(self: *const Self, inst: Inst) InstValuesIterator {
    return InstValuesIterator.init(self, inst);
}
```

**Impact:** Requires updating all call sites from slice iteration to iterator `.next()` pattern.

#### A2: Modify computeUseStates() to call new helper (SIMPLER)

Add a new function that explicitly handles branch args, keeping `instValues()` as-is:

**File:** `compiler/codegen/native/machinst/lower.zig`

```zig
/// Iterate all values used by an instruction, INCLUDING branch arguments.
/// This matches Cranelift's inst_values() behavior.
fn iterInstAllValues(f: *const Function, inst: clif.Inst, callback: anytype) void {
    // 1. Regular instruction args
    for (f.dfg.instArgs(inst)) |arg| {
        callback(arg);
    }

    // 2. Branch destination args (matches Cranelift inst_values)
    const data = f.dfg.getInst(inst);
    const destinations = data.branchDestination(&f.dfg.jump_tables);
    for (destinations) |bc| {
        const args = f.dfg.value_lists.getSlice(bc.args);
        for (args) |arg| {
            callback(arg);
        }
    }
}
```

Then in `computeUseStates()`, replace:
```zig
for (f.dfg.instValues(inst)) |arg| {
```
with:
```zig
iterInstAllValues(f, inst, struct {
    fn callback(arg: clif.Value) void {
        // ... counting logic ...
    }
}.callback);
```

### Option B: Targeted Fix in computeUseStates() Only

**File:** `compiler/codegen/native/machinst/lower.zig:1478-1515`

After the existing `for (f.dfg.instValues(inst))` loop, add explicit branch args handling:

```zig
// Existing code:
for (f.dfg.instValues(inst)) |arg| {
    // ... existing counting logic ...
}

// ADD THIS: Also count branch destination arguments
// Port of Cranelift inst_values() behavior - includes branch args
const inst_data = f.dfg.getInst(inst);
const destinations = inst_data.branchDestination(&f.dfg.jump_tables);
for (destinations) |bc| {
    const branch_args = f.dfg.value_lists.getSlice(bc.args);
    for (branch_args) |arg| {
        std.debug.assert(f.dfg.valueIsReal(arg));
        const old = value_ir_uses.get(arg);
        const ptr = value_ir_uses.getPtr(arg);
        ptr.inc();
        const new = value_ir_uses.get(arg);

        // On transition to Multiple, do DFS (same as existing logic)
        if (old == .multiple or new != .multiple) {
            continue;
        }
        if (getUses(f, arg)) |uses| {
            try stack.append(allocator, uses);
        }
        // ... rest of DFS propagation ...
    }
}
```

## Recommendation

**Option B is recommended** because:
1. Minimal code change - surgical fix in one function
2. No API changes needed
3. Matches how regalloc2's liveness already handles branch args (separately)
4. Can be verified quickly against the failing test

**Option A** (fixing `instValues()`) is cleaner architecturally but requires:
- Iterator pattern changes throughout codebase
- More testing to ensure no regressions
- Can be done as a follow-up refactoring

## Fix Applied

### Changes Made

1. **Created `InstValuesIterator` struct** (`compiler/ir/clif/dfg.zig:830-921`)
   - Iterates over regular instruction args first
   - Then iterates over branch destination arguments
   - Matches Cranelift's `inst_values()` behavior exactly

2. **Updated `instValues()` method** (`compiler/ir/clif/dfg.zig:758-769`)
   - Now returns `InstValuesIterator` instead of `[]const Value`
   - Added `instArgsOnly()` for code that only needs regular args

3. **Updated `computeUseStates()`** (`compiler/codegen/native/machinst/lower.zig:1442-1539`)
   - Changed stack type from `[]const Value` to `InstValuesIterator`
   - Changed `getUses()` helper to return optional iterator
   - DFS traversal now uses iterator's `.next()` method
   - Matches Cranelift's implementation exactly

4. **Added exports** (`compiler/ir/clif/mod.zig`, `lower.zig`)
   - Exported `InstValuesIterator` from CLIF module

5. **Added tests** (`compiler/ir/clif/dfg.zig:1033-1115`)
   - "InstValuesIterator includes branch arguments" - verifies brif args are included
   - "InstValuesIterator for non-branch instruction" - verifies non-branch works

6. **Removed debug code** (`compiler/codegen/native/regalloc/liveness.zig`)
   - Cleaned up investigation debug output

### Test Results
- **Before fix:** 778/781 tests passed, 1 failed (EntryLivein)
- **After fix:** 781/783 tests passed, 2 skipped, 0 failed

## Test Case for Verification

The previously failing test creates this structure:
```
entry_block:
  v0 = param
  brif v0, then_block(v1), else_block(v2)  // v1, v2 are branch args

then_block:
  v1 = iconst 10  // ONLY used as branch arg to merge_block
  jump merge_block(v1)

else_block:
  v2 = iconst 20  // ONLY used as branch arg to merge_block
  jump merge_block(v2)

merge_block(v3):
  return v3
```

After the fix:
- iconst instructions should be lowered (they define v1, v2)
- v193, v194 (machine vregs for v1, v2) should be defined in then_block and else_block
- No vregs should be live-in at entry block
- Test should pass
