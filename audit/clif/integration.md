# CLIF IR Integration Audit

**Task**: 4.10 Integration with machinst framework (stub types → real types)
**Status**: Complete
**Date**: 2026-02-02

## Overview

This document describes the integration of the real CLIF IR types from `compiler/ir/clif/` into the machinst lowering framework, replacing the stub types that were previously defined in each module.

## Files Modified

### 1. `compiler/ir/clif/mod.zig` (NEW)
Module index file that exports all CLIF IR types:
- Type system: `Type`, vector types
- Condition codes: `IntCC`, `FloatCC`
- Trap codes: `TrapCode`
- Opcodes: `Opcode`
- Entity references: `Block`, `Value`, `Inst`, `StackSlot`, `FuncRef`, `SigRef`, `JumpTable`
- DFG types: `DataFlowGraph`, `ValueDef`, `ValueData`, `BlockData`, `InstData`
- Layout: `Layout`, `BlockIterator`, `InstIterator`
- Function: `Function`, `Signature`, `CallConv`, `AbiParam`
- Builder: `InstructionData`, `MemFlags`, `FuncBuilder`
- Jump tables: `JumpTableData`, `BlockCall`, `JumpTables`

### 2. `compiler/ir/clif/dfg.zig` (ENHANCED)
Added instruction data storage and machinst-compatible methods:

```zig
// New InstData type for instruction storage
pub const InstData = struct {
    opcode: Opcode,
    args: ValueList,
    ctrl_type: Type,
};

// Added to DataFlowGraph:
- insts: std.ArrayListUnmanaged(InstData)
- makeInstWithData(data: InstData) !Inst
- setInstData(inst: Inst, data: InstData) !void
- getInstData(inst: Inst) InstData
- instOpcode(inst: Inst) Opcode
- instArgs(inst: Inst) []const Value
- instValues(inst: Inst) []const Value
- ctrlType(inst: Inst) Type
- numValues() usize
- valueIsReal(v: Value) bool
- displayInst(inst: Inst) []const u8
```

### 3. `compiler/codegen/native/machinst/lower.zig` (UPDATED)
Replaced stub types with imports from CLIF:

```zig
const clif = @import("../../../ir/clif/mod.zig");

// Replaced stubs with:
pub const Block = clif.Block;
pub const Value = clif.Value;
pub const Inst = clif.Inst;
pub const StackSlot = clif.StackSlot;
pub const FuncRef = clif.FuncRef;
pub const SigRef = clif.SigRef;
pub const JumpTable = clif.JumpTable;
pub const Opcode = clif.Opcode;
pub const IntCC = clif.IntCC;
pub const FloatCC = clif.FloatCC;
pub const TrapCode = clif.TrapCode;
```

### 4. `compiler/codegen/native/machinst/mod.zig` (UPDATED)
Added exports for CLIF types:

```zig
// CLIF IR types re-exported from lower.zig
pub const Block = lower.Block;
pub const Value = lower.Value;
pub const Inst = lower.Inst;
pub const Opcode = lower.Opcode;
pub const IntCC = lower.IntCC;
pub const FloatCC = lower.FloatCC;
pub const TrapCode = lower.TrapCode;
pub const InstructionData = lower.InstructionData;
pub const ClifType = lower.Type;
```

### 5. `compiler/codegen/native/isa/aarch64/lower.zig` (UPDATED)
Updated to import types from machinst instead of defining its own stubs:

```zig
const machinst = @import("../../machinst/mod.zig");
const lower_mod = machinst.lower;

// Imported types:
pub const Opcode = lower_mod.Opcode;
pub const IntCC = lower_mod.IntCC;
pub const FloatCC = lower_mod.FloatCC;
pub const ClifInst = lower_mod.Inst;
pub const Value = lower_mod.Value;
pub const BlockIndex = lower_mod.BlockIndex;
pub const ValueRegs = lower_mod.ValueRegs;
pub const InstOutput = lower_mod.InstOutput;
pub const NonRegInput = lower_mod.NonRegInput;
pub const ClifType = lower_mod.Type;
pub const InstructionData = lower_mod.InstructionData;
```

Also updated ClifType usage from method syntax to constant syntax:
- `ClifType.int8()` → `ClifType.I8`
- `ClifType.int16()` → `ClifType.I16`
- `ClifType.int32()` → `ClifType.I32`
- `ClifType.int64()` → `ClifType.I64`
- `ClifType.float32()` → `ClifType.F32`
- `ClifType.float64()` → `ClifType.F64`

## Integration Architecture

```
compiler/ir/clif/
    mod.zig (module index)
    types.zig (Type)
    instructions.zig (IntCC, FloatCC, TrapCode, Opcode)
    dfg.zig (Block, Value, Inst, DataFlowGraph)
    layout.zig (Layout, iterators)
    function.zig (Function, Signature, CallConv)
    builder.zig (InstructionData, FuncBuilder)
    jumptable.zig (JumpTableData)
        ↓ imports
compiler/codegen/native/machinst/
    lower.zig (imports clif types, keeps machinst-specific stubs)
    mod.zig (re-exports for backends)
        ↓ imports
compiler/codegen/native/isa/aarch64/
    lower.zig (uses machinst types)
```

## Testing

All existing tests pass:
- 35 CLIF module tests pass
- Full project build succeeds
- Full test suite passes

## Remaining Stubs

The following types are still stubs in `machinst/lower.zig` because they have machinst-specific requirements not yet in the CLIF IR:

1. `Function` - Has additional fields for lowering state (debug_tags, rel_srclocs)
2. `DataFlowGraph` stub - Has additional methods (constants, signatures, immediates, facts)
3. `Layout` stub - Has different iterator patterns for lowering
4. `GlobalValue`, `GlobalValueData` - For symbol references
5. `ConstantData`, `ConstantPool` - For constant data
6. `Signature` stub - Has simplified structure
7. `ValueLabelAssignments` - For debug info

These will be addressed when wiring up the full Wasm→Native AOT pipeline.

## Next Steps

1. **Task 4.11**: Test simple programs on ARM64
2. **Task 4.12**: Test control flow on ARM64
3. **Task 4.13**: Test function calls on ARM64
4. Wire `wasm_to_ssa.zig` to build real CLIF Functions using the new types
5. Connect the Lower(I) driver to the AArch64LowerBackend
