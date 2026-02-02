# Cranelift Port Status Report

**Date:** February 3, 2026
**Branch:** main
**Latest Commit:** 161b37e

This document provides a comprehensive status report on the Cranelift-to-Zig port for Cot's native codegen backend.

---

## Executive Summary

The native codegen pipeline now **compiles to completion** for simple Cot programs. The executable is generated but crashes at runtime due to missing prologue/epilogue generation.

**Key Achievements:**
- Trivial register allocator implemented and working
- br_table lowering fixed for ARM64 (jt_sequence instruction)
- Operand collection via visitor pattern operational
- Mach-O object file generation working

**Remaining Work:**
- Prologue/epilogue generation (critical for runtime)
- x64 br_table lowering
- Full ABI compliance

---

## 1. Tasks Achieved

### 1.1 Trivial Register Allocator (regalloc.zig)

**Status:** ✅ Complete
**Cranelift Reference:** `cranelift/codegen/src/regalloc/mod.rs`

The trivial register allocator assigns each virtual register to a unique physical register without sophisticated liveness analysis. This is sufficient for simple programs and validates the register allocation interface.

**Implementation Details:**
```zig
// regalloc.zig - Trivial allocation strategy
// 1. Collect preferred registers by class (int, float, vector)
// 2. Iterate all instructions, collect operands
// 3. Assign physical register to each virtual register (first-seen basis)
// 4. Store allocations in output buffer
```

**Key Functions:**
- `run()` - Main entry point, iterates blocks and instructions
- `processOperand()` - Maps virtual to physical register
- Respects fixed register constraints from backend

### 1.2 Jump Table Support (jt_sequence)

**Status:** ✅ Complete (ARM64)
**Cranelift Reference:** `cranelift/codegen/src/isa/aarch64/inst.isle` lines 650-656

The `jt_sequence` pseudo-instruction implements br_table via:
1. Bounds check (index < table_size)
2. Branch to default if out of bounds
3. Table lookup and indirect branch

**Implementation Changes:**

1. **Changed from slice to bounded array** - Fixes dangling pointer issue:
```zig
// Before: targets: []const MachLabel (borrowed, becomes invalid)
// After:  targets_buf: [128]MachLabel (owned, stable)
//         targets_len: u8
```

2. **Fixed applyAllocs ordering** - Must match get_operands.zig collection order:
```zig
// Collection order: ridx (use), rtmp1 (def), rtmp2 (def)
// applyAllocs now applies in same order
```

3. **Fixed emit label patching** - Write data before requesting patch:
```zig
// 1. Write 32-bit offset placeholder
try sink.put4(off_into_table);
// 2. Request label resolution at that offset
try sink.useLabelAtOffset(word_off, target, .pcRel32);
```

### 1.3 Operand Collection via Visitor Pattern (get_operands.zig)

**Status:** ✅ Complete
**Cranelift Reference:** `cranelift/codegen/src/machinst/mod.rs` `get_operands()` method

The visitor pattern collects register operands from instructions for the register allocator.

**Implementation:**
```zig
pub fn getOperands(self: *const Inst) []const Operand {
    var visitor = OperandVisitor.init(allocator);
    defer visitor.deinit();

    get_operands.getOperands(self, &visitor);

    // Combine defs first, then uses
    for (visitor.defs.items) |def| {
        buffer[len] = Operand.init(vreg, .reg, .def, .late);
        len += 1;
    }
    for (visitor.uses.items) |use| {
        buffer[len] = Operand.init(vreg, .reg, .use, .early);
        len += 1;
    }
    return buffer[0..len];
}
```

### 1.4 Frontend/FuncInstBuilder (frontend.zig)

**Status:** ✅ Complete
**Cranelift Reference:** `cranelift/frontend/src/frontend.rs`

Builds CLIF IR from Wasm bytecode:
- `iconst`, `iadd`, `isub`, `imul`, `udiv`, `sdiv`
- `band`, `bor`, `bxor`, `ishl`, `ushr`, `sshr`
- `icmp`, `fcmp`
- `load`, `store`
- `jump`, `brif`, `br_table`, `return`
- `call`, `stack_load`, `stack_store`

### 1.5 Mach-O Object Generation (macho.zig)

**Status:** ✅ Complete
**Reference:** Apple Mach-O specification

Generates valid Mach-O object files:
- `__text` section with machine code
- `__data` section
- Symbol table with `_main` export
- Proper header and load commands

---

## 2. Proof of Correct Cranelift Porting

### 2.1 Architecture Matches Cranelift

```
Cranelift Pipeline:
  CLIF IR → Lower → VCode → RegAlloc → Emit → MachBuffer → Object File

Cot Pipeline:
  CLIF IR → lower.zig → vcode.zig → regalloc.zig → emit.zig → buffer.zig → macho.zig
```

### 2.2 Key Data Structures Match

| Cranelift | Cot | Notes |
|-----------|-----|-------|
| `MachInst` trait | `Inst` union | Instruction representation |
| `LowerCtx<I>` | `LowerCtx(Inst)` | Lowering context |
| `VCode<I>` | `VCode(Inst)` | Virtual code container |
| `MachBuffer` | `MachBuffer` | Code emission buffer |
| `MachLabel` | `MachLabel` | Forward-referenced labels |
| `Operand` | `Operand` | Register operand for regalloc |
| `VReg`/`PReg` | `VReg`/`PReg` | Virtual/Physical registers |
| `InstRange` | `InstRange` | Block instruction range |
| `Block` | `Block` | Basic block reference |

### 2.3 Instruction Selection Patterns Match

**Cranelift ISLE (aarch64):**
```lisp
(rule (lower (iadd ty x y))
      (add (put_in_reg x) (put_in_reg y)))

(rule (lower (iadd ty x (iconst k)))
      (add_imm (put_in_reg x) (simm12_from_imm64 k)))
```

**Cot Zig (aarch64):**
```zig
.iadd => {
    // Try immediate optimization first
    if (ctx.getInputAsImm(1)) |imm_val| {
        if (Imm12.fromU64(imm_val)) |imm12| {
            return ctx.emit(.add_imm, rd, rn, imm12);
        }
    }
    // Fall back to register-register
    return ctx.emit(.add, rd, rn, rm);
}
```

### 2.4 JumpTable Implementation Matches

**Cranelift (aarch64/inst.isle):**
```lisp
(JTSequence
  (default MachLabel)
  (targets BoxVecMachLabel)
  (ridx Reg)
  (rtmp1 WritableReg)
  (rtmp2 WritableReg))
```

**Cot (aarch64/inst/mod.zig):**
```zig
jt_sequence: struct {
    ridx: Reg,
    rtmp1: Writable(Reg),
    rtmp2: Writable(Reg),
    default: MachLabel,
    targets_buf: [128]MachLabel,
    targets_len: u8,
}
```

### 2.5 Test Results

```
Total: 735 tests
Passed: 716
Skipped: 19 (native tests pending prologue/epilogue)
Failed: 0
```

The 19 skipped tests are native codegen tests that require runtime execution, which needs prologue/epilogue generation.

---

## 3. Remaining Tasks

### 3.1 CRITICAL: Prologue/Epilogue Generation (Task #105)

**Priority:** P0
**Cranelift Reference:** `cranelift/codegen/src/machinst/abi.rs` lines 500-600

Without prologue/epilogue, the generated executable crashes immediately (SIGSEGV).

**Required Implementation:**

```zig
// Prologue (function entry):
// 1. Save frame pointer: stp x29, x30, [sp, #-16]!
// 2. Set frame pointer: mov x29, sp
// 3. Allocate stack space: sub sp, sp, #frame_size

// Epilogue (function exit):
// 1. Restore stack: add sp, sp, #frame_size
// 2. Restore frame: ldp x29, x30, [sp], #16
// 3. Return: ret
```

**Files to Modify:**
- `compiler/codegen/native/isa/aarch64/abi.zig` - genPrologue, genEpilogue
- `compiler/codegen/native/isa/x64/abi.zig` - Same for x64

### 3.2 HIGH: Fix x64 br_table Lowering (Task #101)

**Priority:** P1
**Cranelift Reference:** `cranelift/codegen/src/isa/x64/lower.isle`

The x64 backend needs the same jt_sequence fix applied for ARM64.

**Files to Modify:**
- `compiler/codegen/native/isa/x64/inst/mod.zig`
- `compiler/codegen/native/isa/x64/lower.zig`
- `compiler/codegen/native/isa/x64/inst/emit.zig`

### 3.3 HIGH: Fix icmp Condition Code Extraction (Task #102)

**Priority:** P1
**Cranelift Reference:** `cranelift/codegen/src/isa/aarch64/lower.isle` line 1247

Currently hardcoded to `.eq`. Need to extract from InstData.imm field.

```zig
// Current (wrong):
const cond = Cond.eq;

// Correct:
const cc = @intToEnum(IntCC, inst_data.imm);
const cond = condFromIntCC(cc);
```

### 3.4 MEDIUM: Implement Call Lowering (Task #103)

**Priority:** P2
**Cranelift Reference:** `cranelift/codegen/src/isa/aarch64/abi.rs`

Required for function calls:
1. Compute argument locations per ABI
2. Move arguments to registers/stack
3. Emit call instruction
4. Handle return value

### 3.5 MEDIUM: Fix Stack Slot Offset Handling (Task #104)

**Priority:** P2
**Cranelift Reference:** `cranelift/codegen/src/machinst/abi.rs` `stackslot_addr()`

Currently hardcoded to offset=0. Need to:
1. Extract slot index from InstData
2. Look up slot in StackSlots
3. Compute byte offset from frame base

### 3.6 LOW: Spill/Reload Implementation

**Priority:** P3

Required for complex programs that exhaust registers.

---

## 4. File Reference

| File | Purpose | Status |
|------|---------|--------|
| `regalloc/regalloc.zig` | Register allocation | ✅ Trivial allocator working |
| `machinst/lower.zig` | Generic lowering context | ✅ Working |
| `machinst/vcode.zig` | Virtual code container | ✅ Working |
| `machinst/buffer.zig` | Code emission buffer | ✅ Working |
| `machinst/blockorder.zig` | Block layout | ✅ Working |
| `isa/aarch64/lower.zig` | ARM64 instruction selection | ⚠️ Needs icmp fix |
| `isa/aarch64/abi.zig` | ARM64 ABI | ❌ Prologue/epilogue stub |
| `isa/aarch64/inst/emit.zig` | ARM64 encoding | ✅ Working |
| `isa/x64/lower.zig` | x64 instruction selection | ❌ br_table broken |
| `isa/x64/abi.zig` | x64 ABI | ❌ Prologue/epilogue stub |
| `macho.zig` | Mach-O generation | ✅ Working |
| `frontend/frontend.zig` | CLIF builder | ✅ Working |

---

## 5. Success Criteria

The Cranelift port is complete when:

1. **Basic Test:** `return 42` compiles and runs natively, returning 42
2. **Function Calls:** Programs with function calls work correctly
3. **Both Architectures:** ARM64 and x64 produce correct output
4. **All Tests Pass:** 19 skipped native tests pass

---

## 6. Appendix: Commits

| Commit | Description |
|--------|-------------|
| 161b37e | Implement trivial register allocator and fix br_table for ARM64 |
| cce1dfc | Implement return lowering for ARM64 |
| f8c6f73 | Fix constant extraction in native codegen pipeline |
| 5d2044c | Fix ARM64 emit tests and add detailed Phase 7 execution plan |
| b20ff3b | Phase 7: Complete JumpTable port for br_table support |
