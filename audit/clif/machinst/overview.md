# Machinst Module Audit - Overview

This folder contains audits of the Zig port of Cranelift's `machinst` module, comparing implementations against the original Rust source in `~/learning/wasmtime/cranelift/codegen/src/machinst/`.

## Files

| File | Cranelift Source | Zig Lines | Rust Lines | Coverage | Tests |
|------|------------------|-----------|------------|----------|-------|
| [reg.zig](reg.zig.md) | reg.rs | 1,057 | 565 | 187% | 11 |
| [inst.zig](inst.zig.md) | mod.rs | 1,219 | 629 | 194% | 8 |
| [vcode.zig](vcode.zig.md) | vcode.rs | 1,722 | 2,065 | 83% | 10 |
| [abi.zig](abi.zig.md) | abi.rs | 1,103 | 2,617 | 42% | 11 |
| [buffer.zig](buffer.zig.md) | buffer.rs | 1,449 | 2,912 | 50% | 13 |
| [blockorder.zig](blockorder.zig.md) | blockorder.rs + deps | 1,309 | 486 | 269% | 11 |
| [lower.zig](lower.zig.md) | lower.rs | 1,750 | 1,799 | 97% | 8 |

**Notes:**
- abi.zig is intentionally smaller because it defines interfaces that backends implement. The machine-specific implementations (ARM64, AMD64) will be in separate files.
- buffer.zig is smaller because branch optimization and veneer emission are architecture-specific and will be completed when backends are wired in.
- blockorder.zig is larger because it includes stub types for CLIF IR (Block, Inst, etc.) plus SecondaryMap, ControlFlowGraph, and DominatorTree which are separate modules in Cranelift. The core BlockLoweringOrder logic is faithful to the original.

## Completeness

| Component | Core Types | Logic | Tests | Backend Support |
|-----------|------------|-------|-------|-----------------|
| reg.zig | 100% | 100% | 11 | N/A |
| inst.zig | 100% | 100% | 8 | N/A |
| vcode.zig | 95% | 90% | 10 | N/A |
| abi.zig | 100% | 80% | 11 | Needs backends |
| buffer.zig | 100% | 80% | 13 | Needs backends |
| blockorder.zig | 100% | 100% | 11 | N/A |
| lower.zig | 100% | 95% | 8 | Needs backends |

## What's Missing

1. **vcode.zig:** The `emit()` method (200 lines) - not critical until emission phase
2. **abi.zig:** Machine-specific implementations - these go in backend files:
   - `arm64/abi.zig` - ARM64 ABIMachineSpec
   - `amd64/abi.zig` - AMD64 ABIMachineSpec
3. **buffer.zig:** Branch optimization and veneer generation - architecture-specific
4. **lower.zig:** Arg setup and return generation - needs ABI integration

## Test Coverage

All 72 tests pass:
- reg.zig: 11 tests (PReg, VReg, Reg, PRegSet, OperandCollector)
- inst.zig: 8 tests (Type, MachLabel, CallType, FunctionCalls)
- vcode.zig: 10 tests (InsnIndex, BlockIndex, Ranges, VRegAllocator, VCodeConstants)
- abi.zig: 11 tests (ABIArg, StackAMode, Sig, SigSet, FrameLayout)
- buffer.zig: 13 tests (MachLabel, MachBuffer, MachBufferFinalized, MachTextSectionBuilder)
- blockorder.zig: 11 tests (SecondaryMap, LoweredBlock, CFG, DomTree, BlockLoweringOrder)
- lower.zig: 8 tests (InstColor, ValueUseState, InputSourceInst, ValueRegs, SecondaryMap)
