# lower.zig - CLIF to MachInst Lowering Framework

**Source:** `cranelift/codegen/src/machinst/lower.rs` (1,799 lines)

## Overview

This module implements lowering (instruction selection) from CLIF IR to machine instructions with virtual registers. This is the penultimate step before register allocation produces final machine code.

## Types Ported

| Cranelift Type | Zig Type | Status | Notes |
|----------------|----------|--------|-------|
| `InstColor` | `InstColor` | ✅ Complete | Side-effect coloring |
| `NonRegInput` | `NonRegInput` | ✅ Complete | Non-register input representation |
| `InputSourceInst` | `InputSourceInst` | ✅ Complete | Source instruction tracking |
| `ValueUseState` | `ValueUseState` | ✅ Complete | Unused/Once/Multiple |
| `RelocDistance` | `RelocDistance` | ✅ Complete | Near/Far relocation |
| `LowerBackend` trait | Comptime interface | ✅ Complete | Backend interface |
| `Lower<I>` | `Lower(I)` | ✅ Complete | Main lowering context |
| `InstOutput` | `InstOutput` | ✅ Complete | Instruction outputs |
| `ValueRegs<R>` | `ValueRegs(R)` | ✅ Complete | Multi-register values |

## Logic Comparison

### InstColor (lower.rs:48-61 → lower.zig:494-520)

**Cranelift:**
```rust
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
struct InstColor(u32);
impl InstColor {
    fn new(n: u32) -> InstColor {
        InstColor(n)
    }
    pub fn get(self) -> u32 {
        self.0
    }
}
```

**Cot:**
```zig
pub const InstColor = struct {
    value: u32,

    pub fn new(n: u32) Self {
        return .{ .value = n };
    }

    pub fn get(self: Self) u32 {
        return self.value;
    }

    pub fn eql(self: Self, other: Self) bool {
        return self.value == other.value;
    }
};
```

✅ **Match:** Same coloring semantics for side-effect partitioning.

### ValueUseState (lower.rs:343-361 → lower.zig:569-588)

**Cranelift:**
```rust
enum ValueUseState {
    Unused,
    Once,
    Multiple,
}

impl ValueUseState {
    fn inc(&mut self) {
        let new = match self {
            Self::Unused => Self::Once,
            Self::Once | Self::Multiple => Self::Multiple,
        };
        *self = new;
    }
}
```

**Cot:**
```zig
pub const ValueUseState = enum {
    unused,
    once,
    multiple,

    pub fn inc(self: *Self) void {
        self.* = switch (self.*) {
            .unused => .once,
            .once, .multiple => .multiple,
        };
    }
};
```

✅ **Match:** Same coarsening semantics for use-count analysis.

### InputSourceInst (lower.rs:90-117 → lower.zig:537-567)

**Cranelift:**
```rust
pub enum InputSourceInst {
    UniqueUse(Inst, usize),
    Use(Inst, usize),
    None,
}

impl InputSourceInst {
    pub fn as_inst(&self) -> Option<(Inst, usize)> {
        match self {
            &InputSourceInst::UniqueUse(inst, output_idx)
            | &InputSourceInst::Use(inst, output_idx) => Some((inst, output_idx)),
            &InputSourceInst::None => None,
        }
    }
}
```

**Cot:**
```zig
pub const InputSourceInst = union(enum) {
    unique_use: struct { inst: Inst, output_idx: usize },
    use: struct { inst: Inst, output_idx: usize },
    none,

    pub fn asInst(self: Self) ?struct { inst: Inst, output_idx: usize } {
        return switch (self) {
            .unique_use => |u| .{ .inst = u.inst, .output_idx = u.output_idx },
            .use => |u| .{ .inst = u.inst, .output_idx = u.output_idx },
            .none => null,
        };
    }
};
```

✅ **Match:** Same source instruction tracking with unique vs shared use.

### Lower struct (lower.rs:172-240 → lower.zig:816-916)

**Cranelift:**
```rust
pub struct Lower<'func, I: VCodeInst> {
    f: &'func Function,
    vcode: VCodeBuilder<I>,
    vregs: VRegAllocator<I>,
    value_regs: SecondaryMap<Value, ValueRegs<Reg>>,
    sret_reg: Option<ValueRegs<Reg>>,
    block_end_colors: SecondaryMap<Block, InstColor>,
    side_effect_inst_entry_colors: FxHashMap<Inst, InstColor>,
    cur_scan_entry_color: Option<InstColor>,
    cur_inst: Option<Inst>,
    inst_constants: FxHashMap<Inst, u64>,
    value_ir_uses: SecondaryMap<Value, ValueUseState>,
    value_lowered_uses: SecondaryMap<Value, u32>,
    inst_sunk: FxHashSet<Inst>,
    ir_insts: Vec<I>,
    // ... more fields
}
```

**Cot:**
```zig
pub fn Lower(comptime I: type) type {
    return struct {
        allocator: Allocator,
        f: *const Function,
        vcode: VCodeBuilder(I),
        vregs: VRegAllocator(I),
        value_regs: SecondaryMap(Value, ValueRegs(Reg)),
        sret_reg: ?ValueRegs(Reg),
        block_end_colors: SecondaryMap(Block, InstColor),
        side_effect_inst_entry_colors: std.AutoHashMapUnmanaged(Inst, InstColor),
        cur_scan_entry_color: ?InstColor,
        cur_inst: ?Inst,
        inst_constants: std.AutoHashMapUnmanaged(Inst, u64),
        value_ir_uses: SecondaryMap(Value, ValueUseState),
        value_lowered_uses: SecondaryMap(Value, u32),
        inst_sunk: std.AutoHashMapUnmanaged(Inst, void),
        ir_insts: std.ArrayListUnmanaged(I),
        // ... more fields
    };
}
```

✅ **Match:** Same state tracking with Zig collection types.

### compute_use_states (lower.rs:1242-1351 → lower.zig:1596-1663)

**Cranelift:**
```rust
fn compute_use_states(
    f: &Function,
    sret_param: Option<Value>,
) -> SecondaryMap<Value, ValueUseState> {
    let mut value_ir_uses = SecondaryMap::with_default(ValueUseState::Unused);
    // ... DFS to propagate Multiple state
}
```

**Cot:**
```zig
pub fn computeUseStates(
    allocator: Allocator,
    f: *const Function,
    sret_param: ?Value,
) !SecondaryMap(Value, ValueUseState) {
    var value_ir_uses = SecondaryMap(Value, ValueUseState).withDefault(allocator, .unused);
    // ... DFS to propagate Multiple state
}
```

✅ **Match:** Same algorithm with hybrid shallow use-count + DFS propagation.

### LowerBackend trait (lower.rs:119-168 → lower.zig:601-613)

**Cranelift:**
```rust
pub trait LowerBackend {
    type MInst: VCodeInst;

    fn lower(&self, ctx: &mut Lower<Self::MInst>, inst: Inst) -> Option<InstOutput>;
    fn lower_branch(
        &self,
        ctx: &mut Lower<Self::MInst>,
        inst: Inst,
        targets: &[MachLabel],
    ) -> Option<()>;
    fn maybe_pinned_reg(&self) -> Option<Reg> { None }
}
```

**Cot:**
```zig
pub fn isLowerBackend(comptime T: type) bool {
    return @hasDecl(T, "MInst") and
        @hasDecl(T, "lower") and
        @hasDecl(T, "lowerBranch");
}
```

✅ **Match:** Comptime interface check for backend requirements.

## Key Methods Ported

| Cranelift Method | Zig Method | Status |
|------------------|------------|--------|
| `Lower::new()` | `Lower.init()` | ✅ |
| `Lower::lower()` | `Lower.lower()` | ✅ |
| `Lower::emit()` | `Lower.emit()` | ✅ |
| `Lower::sink_inst()` | `Lower.sinkInst()` | ✅ |
| `Lower::put_input_in_regs()` | `Lower.putInputInRegs()` | ✅ |
| `Lower::put_value_in_regs()` | `Lower.putValueInRegs()` | ✅ |
| `Lower::get_value_as_source_or_const()` | `Lower.getValueAsSourceOrConst()` | ✅ |
| `Lower::alloc_tmp()` | `Lower.allocTmp()` | ✅ |
| `Lower::cur_inst()` | `Lower.curInst()` | ✅ |
| `lower_clif_block()` | `lowerClifBlock()` | ✅ |
| `lower_clif_branch()` | `lowerClifBranch()` | ✅ |
| `compute_use_states()` | `computeUseStates()` | ✅ |
| `has_lowering_side_effect()` | `hasLoweringSideEffect()` | ✅ |
| `is_value_use_root()` | `isValueUseRoot()` | ✅ |

## What's Included

1. **Instruction coloring** - Partitions instructions by side-effects for code motion
2. **Value use state tracking** - Unused/Once/Multiple for pattern matching
3. **Input source tracking** - Unique vs shared use for instruction combining
4. **SecondaryMap** - Entity map with default values
5. **ValueRegs** - Multi-register value representation
6. **LowerBackend interface** - Backend trait for ISA-specific lowering
7. **Full Lower struct** - Main lowering context with all state

## CLIF IR Stubs

The file includes stub types for CLIF IR to keep machinst self-contained:
- Block, Value, Inst, Function, DataFlowGraph, Layout
- InstructionData, Opcode, ValueDef
- MemFlags, ExternalName, GlobalValueData

In production, these would be imported from `compiler/ir/clif/`.

## Test Coverage

8 tests covering:
- InstColor creation and equality
- ValueUseState increment
- InputSourceInst asInst extraction
- ValueRegs creation (single, double, invalid)
- SecondaryMap with default values
- RelocDistance enum
- NonRegInput struct
- Opcode.isBranch classification

## What's Deferred

1. **gen_arg_setup()** - Argument setup (needs ABI integration)
2. **gen_return()** - Return sequence generation
3. **Value label tracking** - Debug info (deferred)
4. **User stack maps** - Stack map forwarding (deferred)
5. **PCC fact checking** - Proof-carrying code (deferred)

These will be completed when integrating with specific ISA backends.
