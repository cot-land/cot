# Emit With Allocations Port Plan

## Problem Statement

The current `emitWithAllocs` implementation manually handles register allocation application per-instruction-type, which is error-prone and doesn't match Cranelift's architecture.

## Cranelift's Architecture

### Key Pattern: Single `get_operands` function called twice

1. **During regalloc input**: `OperandCollector` implements `OperandVisitor`, collects operands into a flat list for regalloc2
2. **During emit**: A closure implements `OperandVisitor`, applies allocations by mutating registers in-place

### Reference Code (cranelift/codegen/src/machinst/vcode.rs:1017-1035)

```rust
// Emit-time: apply allocations via get_operands
let mut allocs = regalloc.inst_allocs(iix).iter();
self.insts[iix.index()].get_operands(
    &mut |reg: &mut Reg, constraint, _kind, _pos| {
        let alloc = allocs.next().expect("enough allocations for all operands");
        if let Some(alloc) = alloc.as_reg() {
            *reg = alloc.into();
        } else if let Some(alloc) = alloc.as_stack() {
            *reg = alloc.into();
        }
    },
);
debug_assert!(allocs.next().is_none());
```

### Why This Works

- `get_operands` visits registers in a deterministic order (defs first, then uses)
- Regalloc2 produces allocations in the same order operands were collected
- The same function can mutate registers during emit (via mutable visitor)

---

## Current Port State

### What Exists
- `get_operands.zig`: Has `OperandVisitor` and `getOperands()` that collects operands
- `mod.zig`: Has `emitWithAllocs()` that manually handles each instruction type
- Problem: `emitWithAllocs` doesn't use `getOperands`, manually manages allocation indices

### What's Missing
- Unified visitor pattern where same `getOperands` is used for both collection and emit
- Ability to mutate registers in-place during emit via visitor

---

## Execution Plan

### Task 1: Refactor OperandVisitor to support mutable register access

**File**: `compiler/codegen/native/isa/aarch64/inst/get_operands.zig`

**Current**:
```zig
pub fn regUse(self: *OperandVisitor, reg: Reg) void {
    self.uses.append(self.allocator, reg) catch unreachable;
}
```

**Change to Cranelift pattern**: Add callback-based visitor that receives `*Reg`

```zig
/// Callback visitor for applying allocations during emit.
/// Reference: cranelift/codegen/src/machinst/reg.rs:542
pub const OperandCallback = *const fn (
    reg: *Reg,
    constraint: OperandConstraint,
    kind: OperandKind,
    pos: OperandPos,
) void;

/// Unified visitor that can either collect operands or apply allocations.
pub const OperandVisitor = union(enum) {
    collector: *OperandCollectorState,
    callback: OperandCallback,

    pub fn regUse(self: *OperandVisitor, reg: *Reg) void {
        switch (self.*) {
            .collector => |c| c.uses.append(c.allocator, reg.*) catch unreachable,
            .callback => |cb| cb(reg, .any, .use, .early),
        }
    }

    pub fn regDef(self: *OperandVisitor, reg: *Writable(Reg)) void {
        switch (self.*) {
            .collector => |c| c.defs.append(c.allocator, reg.*) catch unreachable,
            .callback => |cb| cb(reg.regPtr(), .any, .def, .late),
        }
    }
};
```

### Task 2: Update getOperands to take mutable instruction reference

**File**: `compiler/codegen/native/isa/aarch64/inst/get_operands.zig`

**Current**:
```zig
pub fn getOperands(inst: *const Inst, collector: *OperandVisitor) void {
    switch (inst.*) {
        .alu_rrr => |p| {
            collector.regDef(p.rd);  // p.rd is a copy
```

**Change**: Take `*Inst` and pass pointers to fields:

```zig
pub fn getOperands(inst: *Inst, visitor: *OperandVisitor) void {
    switch (inst.*) {
        .alu_rrr => |*p| {  // Note: |*p| gives mutable pointer
            visitor.regDef(&p.rd);
            visitor.regUse(&p.rn);
            visitor.regUse(&p.rm);
        },
```

### Task 3: Replace emitWithAllocs with Cranelift pattern

**File**: `compiler/codegen/native/isa/aarch64/inst/mod.zig`

**Current** (800+ lines of manual handling):
```zig
pub fn emitWithAllocs(...) !void {
    var inst_copy = self.*;
    var alloc_idx: usize = 0;
    switch (inst_copy) {
        .alu_rrr => |*p| {
            if (alloc_idx < allocs.len) {
                p.rd = applyAllocWritable(p.rd, allocs[alloc_idx]);
                alloc_idx += 1;
            }
            // ... repeat for each field
        },
        // ... hundreds more cases
    }
}
```

**Change to Cranelift pattern**:
```zig
pub fn emitWithAllocs(
    self: *const Inst,
    sink: *MachBuffer,
    allocs: []const Allocation,
    emit_info: *const EmitInfo,
) !void {
    var inst_copy = self.*;
    var alloc_iter = AllocationIterator.init(allocs);

    // Apply allocations via visitor pattern
    // Reference: wasmtime/cranelift/codegen/src/machinst/vcode.rs:1017-1035
    get_operands.getOperands(&inst_copy, &.{
        .callback = struct {
            fn apply(reg: *Reg, _: OperandConstraint, _: OperandKind, _: OperandPos) void {
                const alloc = alloc_iter.next() orelse unreachable;
                if (alloc.asReg()) |preg| {
                    reg.* = Reg.fromPReg(preg);
                } else if (alloc.asStack()) |slot| {
                    reg.* = Reg.fromSpillSlot(slot);
                }
            }
        }.apply,
    });

    // Assert all allocations consumed
    std.debug.assert(alloc_iter.next() == null);

    // Emit with physical registers
    try emit.emit(&inst_copy, sink, emit_info, &state);
}
```

### Task 4: Handle special cases (args, rets, fixed registers)

**Cranelift Reference**: `cranelift/codegen/src/isa/aarch64/inst/mod.rs:780-830`

Instructions like `args` and `rets` have fixed register constraints. These need special handling:

```zig
.args => |*p| {
    for (p.arg_pairs) |*pair| {
        // Fixed def: the vreg must be placed in the specific preg
        visitor.regFixedDef(&pair.vreg, pair.preg);
    }
},
.rets => |*p| {
    for (p.ret_pairs) |*pair| {
        // Fixed use: the vreg must come from the specific preg
        visitor.regFixedUse(&pair.vreg, pair.preg);
    }
},
```

### Task 5: Update VCode emit loop

**File**: `compiler/codegen/native/machinst/vcode.zig`

**Current** (around line 866):
```zig
try vcode_inst.emitWithAllocs(&buffer, inst_allocs, emit_info);
```

This should work unchanged since `emitWithAllocs` signature stays the same.

### Task 6: Remove dead code

After implementing the new pattern, remove:
- The manual `switch` cases in old `emitWithAllocs`
- Any `tryApplyAlloc` helpers that were added as ad-hoc fixes
- The stub `getOperands` in `mod.zig` that returns empty

---

## Testing Strategy

1. **Unit test**: `getOperands` with collector returns same operands as before
2. **Unit test**: `getOperands` with callback mutates registers correctly
3. **Integration test**: Simple function compiles and emits valid code
4. **Regression test**: All 777 existing tests still pass

---

## Files to Modify

| File | Changes |
|------|---------|
| `isa/aarch64/inst/get_operands.zig` | Add callback visitor, change to `*Inst` |
| `isa/aarch64/inst/mod.zig` | Replace `emitWithAllocs` implementation |
| `machinst/vcode.zig` | Minor adjustments if needed |

---

## Reference Files

| Our File | Cranelift Reference |
|----------|---------------------|
| `get_operands.zig` | `cranelift/codegen/src/isa/aarch64/inst/mod.rs:354-780` |
| `mod.zig:emitWithAllocs` | `cranelift/codegen/src/machinst/vcode.rs:1014-1046` |
| `OperandVisitor` | `cranelift/codegen/src/machinst/reg.rs:378-552` |
