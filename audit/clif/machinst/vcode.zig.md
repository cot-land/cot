# vcode.zig - Virtual-Register Code Container

**Source:** `cranelift/codegen/src/machinst/vcode.rs` (2,065 lines)

## Types Ported

| Cranelift Type | Zig Type | Status | Notes |
|----------------|----------|--------|-------|
| `InsnIndex` | `InsnIndex` | ✅ Complete | Instruction indices |
| `BackwardsInsnIndex` | `BackwardsInsnIndex` | ✅ Complete | Reversed indices for backward building |
| `BlockIndex` | `BlockIndex` | ✅ Complete | Basic block indices |
| `Operand` | `Operand` | ✅ Complete | Register allocation operands |
| `OperandConstraint` | `OperandConstraint` | ✅ Complete | Operand placement constraints |
| `OperandKind` | `OperandKind` | ✅ Complete | Use/Def classification |
| `Ranges` | `Ranges` | ✅ Complete | Efficient range storage |
| `VCode<I>` | `VCode(I)` | ✅ Complete | Main VCode container |
| `VCodeBuilder<I>` | `VCodeBuilder(I)` | ✅ Complete | Builder for VCode |
| `VRegAllocator<I>` | `VRegAllocator(I)` | ✅ Complete | VReg allocation during lowering |
| `VCodeConstants` | `VCodeConstants` | ✅ Complete | Constant pool management |
| `VCodeConstant` | `VCodeConstant` | ✅ Complete | Constant reference |
| `VCodeConstantData` | `VCodeConstantData` | ✅ Complete | Constant data storage |

## Logic Comparison

### VCode Structure (vcode.rs:92-211 → vcode.zig:481-660)

The VCode struct stores the lowered machine code in a CFG representation:

**Cranelift:**
```rust
pub struct VCode<I: VCodeInst> {
    vreg_types: Vec<Type>,
    insts: Vec<I>,
    operands: Vec<Operand>,
    operand_ranges: Ranges,
    clobbers: FxHashMap<InsnIndex, PRegSet>,
    srclocs: Vec<RelSourceLoc>,
    entry: BlockIndex,
    block_ranges: Ranges,
    block_succ_range: Ranges,
    block_succs: Vec<BlockIndex>,
    // ... more fields
}
```

**Cot:**
```zig
pub fn VCode(comptime I: type) type {
    return struct {
        vreg_types: std.ArrayListUnmanaged(Type),
        insts: std.ArrayListUnmanaged(I),
        operands: std.ArrayListUnmanaged(Operand),
        operand_ranges: Ranges,
        clobbers: std.AutoHashMapUnmanaged(InsnIndex, PRegSet),
        srclocs: std.ArrayListUnmanaged(RelSourceLoc),
        entry: BlockIndex,
        block_ranges: Ranges,
        block_succ_range: Ranges,
        block_succs: std.ArrayListUnmanaged(BlockIndex),
        // ... more fields
    };
}
```

✅ **Match:** Same data layout with Zig collection types.

### Backward Building (vcode.rs:459-515 → vcode.zig:997-1060)

VCode is built in reverse order (for use-before-def lowering), then reversed:

**Cranelift:**
```rust
fn reverse_and_finalize(&mut self, vregs: &VRegAllocator<I>) {
    let n_insts = self.vcode.insts.len();
    self.vcode.block_ranges.reverse_index();
    self.vcode.block_ranges.reverse_target(n_insts);
    self.vcode.insts.reverse();
    self.vcode.srclocs.reverse();
    // ...
}
```

**Cot:**
```zig
fn reverseAndFinalize(self: *Self, vregs: *VRegAllocator(I)) !void {
    const n_insts = self.vcode.insts.items.len;
    self.vcode.block_ranges.reverseIndex();
    self.vcode.block_ranges.reverseTarget(n_insts);
    std.mem.reverse(I, self.vcode.insts.items);
    std.mem.reverse(RelSourceLoc, self.vcode.srclocs.items);
    // ...
}
```

✅ **Match:** Same reversal algorithm.

### VReg Aliasing (vcode.rs:1838-1869 → vcode.zig:1320-1355)

VReg aliasing handles SSA renaming during lowering:

**Cranelift:**
```rust
pub fn set_vreg_alias(&mut self, from: Reg, to: Reg) {
    let from = from.into();
    let resolved_to = self.resolve_vreg_alias(to.into());
    assert_ne!(resolved_to, from);  // No cycles
    // Transfer facts
    if let Some(fact) = self.facts[from.vreg()].take() {
        self.set_fact(resolved_to, fact);
    }
    self.vreg_aliases.insert(from, resolved_to);
}

fn resolve_vreg_alias(&self, mut vreg: VReg) -> VReg {
    while let Some(to) = self.vreg_aliases.get(&vreg) {
        vreg = *to;
    }
    vreg
}
```

**Cot:**
```zig
pub fn setVregAlias(self: *Self, from: Reg, to: Reg) !void {
    const from_vreg = from.toVirtualReg().?.toVReg();
    const to_vreg = to.toVirtualReg().?.toVReg();
    const resolved_to = self.resolveVregAlias(to_vreg);
    std.debug.assert(resolved_to.bits != from_vreg.bits);  // No cycles
    // Transfer facts
    if (self.facts.items[from_vreg.vreg()]) |fact| {
        self.facts.items[from_vreg.vreg()] = null;
        try self.setFact(resolved_to, fact);
    }
    try self.vreg_aliases.put(self.allocator, from_vreg, resolved_to);
}

pub fn resolveVregAlias(self: *const Self, vreg: VReg) VReg {
    var current = vreg;
    while (self.vreg_aliases.get(current)) |to| {
        current = to;
    }
    return current;
}
```

✅ **Match:** Same alias resolution with cycle prevention.

### Constant Deduplication (vcode.rs:1946-1976 → vcode.zig:1465-1520)

Constants are deduplicated by type:

**Cranelift:**
```rust
pub fn insert(&mut self, data: VCodeConstantData) -> VCodeConstant {
    match data {
        VCodeConstantData::Generated(_) => self.constants.push(data),
        VCodeConstantData::Pool(constant, _) => {
            match self.pool_uses.get(&constant) {
                None => { /* insert new */ }
                Some(&existing) => existing,
            }
        }
        VCodeConstantData::U64(value) => {
            match self.u64s.entry(value) {
                Entry::Vacant(v) => { /* insert new */ }
                Entry::Occupied(o) => *o.get(),
            }
        }
        // ...
    }
}
```

**Cot:**
```zig
pub fn insert(self: *Self, data: VCodeConstantData) !VCodeConstant {
    switch (data.kind) {
        .generated => {
            const idx = self.constants.items.len;
            try self.constants.append(self.allocator, data);
            return VCodeConstant{ .index = @intCast(idx) };
        },
        .pool => |constant| {
            if (self.pool_uses.get(constant)) |existing| {
                return existing;
            }
            // insert new...
        },
        .u64 => |value| {
            if (self.u64s.get(value)) |existing| {
                return existing;
            }
            // insert new...
        },
        // ...
    }
}
```

✅ **Match:** Same deduplication strategy per constant type.

## What's Missing

The `emit()` method (~200 lines) - not critical until emission phase.

## Test Coverage

10 tests covering:
- InsnIndex creation and operations
- BlockIndex validity
- Ranges storage and reversal
- VRegAllocator allocation
- VCodeConstants deduplication
