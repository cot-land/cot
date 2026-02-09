# br_table Jump Table Bug: Labels Resolve to Body Blocks Instead of Intermediate Blocks

## Current Impact (Feb 2026)

**1 test failure: the batch test (all-in-one binary) crashes with SIGSEGV.**

All 862 individual tests pass. The batch test compiles all test files into a single binary; the first function that triggers a br_table dispatch with edge moves (9-param `sum9` in `test/e2e/functions.cot`) crashes the process.

The original 13 control_flow test failures were fixed by commit `61be134` (critical-edge-aware successor labels). The underlying label resolution bug remains but only manifests when the jump table is actually executed at runtime with wrong offsets.

## Summary

When a function contains a `br_table` dispatch loop (triggered by modulo/division, resume points, or functions with enough complexity), the x64 jump table entries point directly to **body blocks** instead of **intermediate blocks**. The intermediate blocks contain regalloc edge moves that copy function arguments to the correct registers. Since the jump table bypasses these intermediate blocks, register values are wrong and functions SIGSEGV or return garbage.

## Reproduction

Simplest crash — a 9-parameter function:
```cot
fn sum9(a: i64, b: i64, c: i64, d: i64, e: i64, f: i64, g: i64, h: i64, i: i64) i64 {
    return a + b + c + d + e + f + g + h + i
}
fn main() i64 { return sum9(1, 2, 3, 4, 5, 6, 7, 8, 9) }
```
Expected: 45. Actual: SIGSEGV (signal 11).

GDB shows the crash at `sum9+53`: `movslq 0x41dd0149(,%rbx,4),%rbx` — the jump table address is garbage because labels resolved to wrong offsets.

Original reproduction (returns wrong value instead of crashing):
```cot
fn test_it(n: i64) i64 {
    var i: i64 = 0;
    while i < 0 {
        var r: i64 = i % 2;
        i = i + 1;
    }
    return n;
}
fn main() i64 { return test_it(5) }
```
Expected: 5. Actual: 72 (0x48 = jump table offset leaking into return value).

## Root Cause

The correct flow through br_table dispatch:
```
dispatch block → br_table → intermediate block → (edge moves) → body block
```

What actually happens on x64:
```
dispatch block → br_table → (SKIPS intermediate) → body block (wrong registers)
```

The issue is in how `blockLabel()` resolves for intermediate blocks:

1. `translateBrTable()` in `translator.zig` creates intermediate CLIF blocks and puts them in the jump table
2. x64 `lowerBranch` for `br_table` calls `ctx.blockLabel(target_block)` for each jump table entry
3. `blockLabel()` calls `loweredIndexForBlock(block)` which looks up `blockindex_by_block`
4. The labels resolve to body block addresses instead of intermediate block code addresses
5. The intermediate blocks' edge moves are emitted as regalloc edits of the DISPATCH block, not as their own blocks

From debug tracing:
```
BLOCK 0: offset=0x0, insns=18   ← dispatch block (includes jump table DATA)
BLOCK 1: offset=0x54, insns=1   ← starts AFTER intermediate blocks' code
```

The intermediate block code (`mov rcx, rdx; jmp`) at offset 0x44 falls within block 0's range — it was absorbed into the dispatch block.

## ARM64 Comparison Needed

**ARM64 works correctly.** The fix likely requires understanding why ARM64's block ordering or label resolution handles intermediate blocks differently. Investigate on ARM64:

1. Compile the reproduction case to native on ARM64
2. Disassemble and check: do jump table entries point to intermediate blocks or body blocks?
3. Compare the lowered block order between ARM64 and x64

## Files to Investigate

| File | Purpose |
|------|---------|
| `compiler/codegen/native/wasm_to_clif/translator.zig` | `translateBrTable` - creates intermediate blocks |
| `compiler/codegen/native/machinst/blockorder.zig` | Block ordering - RPO walk, critical edge splitting |
| `compiler/codegen/native/machinst/lower.zig` | `blockLabel()` - maps CLIF block to MachLabel |
| `compiler/codegen/native/machinst/vcode.zig` | Emission loop - binds labels and emits code |
| `compiler/codegen/native/isa/x64/lower.zig` | x64 br_table lowering |
| `compiler/codegen/native/isa/aarch64/lower.zig` | ARM64 br_table lowering (reference) |
| `compiler/codegen/native/isa/x64/inst/emit.zig` | `jmp_table_seq` emission |
