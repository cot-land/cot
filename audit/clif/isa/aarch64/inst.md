# AArch64 Instruction Module Audit

**Source:** `cranelift/codegen/src/isa/aarch64/inst/`

## Overview

This module implements AArch64 (ARM64) machine instruction types, immediate encodings, register utilities, and argument types. This is Phase 4 Task 4.2 of the Cranelift port.

## Files Ported

| Cranelift File | Zig File | Rust Lines | Zig Lines | Coverage |
|----------------|----------|------------|-----------|----------|
| args.rs | args.zig | 726 | 790 | 109% |
| imms.rs | imms.zig | 1,242 | 806 | 65% |
| regs.rs | regs.zig | 281 | 297 | 106% |
| mod.rs | mod.zig | 3,114 | 1,044 | 34% |
| **Total** | | **5,363** | **3,027** | **56%** |

**Note:** mod.rs is only partially ported - the instruction enum variants and basic operations are ported, but the full `aarch64_get_operands` function (800+ lines) and `print_with_state` method (1500+ lines) are deferred until emission phase.

## Types Ported

### From args.rs (args.zig)

| Cranelift Type | Zig Type | Status |
|----------------|----------|--------|
| `ShiftOp` | `ShiftOp` | ✅ Complete |
| `ShiftOpShiftImm` | `ShiftOpShiftImm` | ✅ Complete |
| `ShiftOpAndAmt` | `ShiftOpAndAmt` | ✅ Complete |
| `ExtendOp` | `ExtendOp` | ✅ Complete |
| `MemLabel` | `MemLabel` | ✅ Complete |
| `Cond` | `Cond` | ✅ Complete |
| `CondBrKind` | `CondBrKind` | ✅ Complete |
| `BranchTarget` | `BranchTarget` | ✅ Complete |
| `OperandSize` | `OperandSize` | ✅ Complete |
| `ScalarSize` | `ScalarSize` | ✅ Complete |
| `VectorSize` | `VectorSize` | ✅ Complete |
| `APIKey` | `APIKey` | ✅ Complete |
| `TestBitAndBranchKind` | `TestBitAndBranchKind` | ✅ Complete |
| `BranchTargetType` | `BranchTargetType` | ✅ Complete |

### From imms.rs (imms.zig)

| Cranelift Type | Zig Type | Status |
|----------------|----------|--------|
| `NZCV` | `NZCV` | ✅ Complete |
| `UImm5` | `UImm5` | ✅ Complete |
| `SImm7Scaled` | `SImm7Scaled` | ✅ Complete |
| `FPULeftShiftImm` | `FPULeftShiftImm` | ✅ Complete |
| `FPURightShiftImm` | `FPURightShiftImm` | ✅ Complete |
| `SImm9` | `SImm9` | ✅ Complete |
| `UImm12Scaled` | `UImm12Scaled` | ✅ Complete |
| `Imm12` | `Imm12` | ✅ Complete |
| `ImmLogic` | `ImmLogic` | ✅ Complete |
| `ImmShift` | `ImmShift` | ✅ Complete |
| `MoveWideConst` | `MoveWideConst` | ✅ Complete |
| `ASIMDMovModImm` | `ASIMDMovModImm` | ✅ Complete |
| `ASIMDFPModImm` | `ASIMDFPModImm` | ✅ Complete |

### From regs.rs (regs.zig)

| Cranelift Function | Zig Function | Status |
|--------------------|--------------|--------|
| `xreg()` | `xreg()` | ✅ Complete |
| `vreg()` | `vreg()` | ✅ Complete |
| `zero_reg()` | `zeroReg()` | ✅ Complete |
| `stack_reg()` | `stackReg()` | ✅ Complete |
| `link_reg()` | `linkReg()` | ✅ Complete |
| `fp_reg()` | `fpReg()` | ✅ Complete |
| `spilltmp_reg()` | `spilltmpReg()` | ✅ Complete |
| `tmp2_reg()` | `tmp2Reg()` | ✅ Complete |
| `pinned_reg()` | `pinnedReg()` | ✅ Complete |
| Pretty-print functions | Various | ✅ Stub (TODO: full impl) |

### From mod.rs (mod.zig)

| Cranelift Type | Zig Type | Status |
|----------------|----------|--------|
| `ALUOp` | `ALUOp` | ✅ Complete |
| `ALUOp3` | `ALUOp3` | ✅ Complete |
| `BitOp` | `BitOp` | ✅ Complete |
| `FPUOp1` | `FPUOp1` | ✅ Complete |
| `FPUOp2` | `FPUOp2` | ✅ Complete |
| `FPUOp3` | `FPUOp3` | ✅ Complete |
| `FpuRoundMode` | `FpuRoundMode` | ✅ Complete |
| `FpuToIntOp` | `FpuToIntOp` | ✅ Complete |
| `IntToFpuOp` | `IntToFpuOp` | ✅ Complete |
| `MoveWideOp` | `MoveWideOp` | ✅ Complete |
| `AtomicRMWOp` | `AtomicRMWOp` | ✅ Complete |
| `AtomicRMWLoopOp` | `AtomicRMWLoopOp` | ✅ Complete |
| `VecALUOp` | `VecALUOp` | ✅ Complete |
| `VecMisc2` | `VecMisc2` | ✅ Complete |
| `AMode` | `AMode` | ✅ Complete |
| `PairAMode` | `PairAMode` | ✅ Complete |
| `Inst` | `Inst` | ✅ Partial (core variants) |

## Test Coverage

| File | Tests |
|------|-------|
| args.zig | 9 |
| imms.zig | 7 |
| regs.zig | 4 |
| mod.zig | 4 |
| aarch64/mod.zig | 1 |
| **Total** | **25** |

## What's Deferred

1. **emit.rs** (3,687 lines) - Instruction emission/encoding
2. **emit_tests.rs** (7,972 lines) - Emission tests
3. **Full `aarch64_get_operands()`** - Register operand collection for all instruction variants
4. **Full `print_with_state()`** - Pretty printing for all instruction variants
5. **Full instruction variants** - FPU load/store pairs, atomic operations, vector operations

These will be completed when integrating with the emission phase (Phase 4.6).

## Key Algorithms

### ImmLogic Encoding (VIXL port)

The `ImmLogic.maybeFromU64()` function implements the complex algorithm for encoding AArch64 logical immediates. This is a direct port of VIXL's `Assembler::IsImmLogical`.

Key insight: AArch64 logical immediates are repeating bit patterns that can be encoded with just 13 bits (N, R, S).

### MoveWideConst

`MoveWideConst.maybeFromU64()` determines if a 64-bit constant can be loaded with a single MOVZ/MOVN instruction by checking if only one 16-bit chunk is non-zero.

## Dependencies

Currently uses stub types for:
- `Reg`, `PReg`, `VReg`, `RegClass` - Will integrate with machinst when wired in
- `Type` - Will integrate with CLIF IR types
- `MachLabel` - Will integrate with MachBuffer

These stubs are in `args.zig` and will be replaced with proper imports when the backend is wired into the compiler.
