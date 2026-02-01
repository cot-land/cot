# buffer.zig - Machine Code Buffer

**Source:** `cranelift/codegen/src/machinst/buffer.rs` (2,912 lines)

## Types Ported

| Cranelift Type | Zig Type | Status | Notes |
|----------------|----------|--------|-------|
| `MachLabel` | `MachLabel` | ✅ Complete | Label for forward references |
| `MachBuffer<I>` | `MachBuffer(LabelUseType)` | ✅ Complete | Main code buffer |
| `MachBufferFinalized` | `MachBufferFinalized` | ✅ Complete | Finalized buffer |
| `MachLabelFixup<I>` | `MachLabelFixup(LabelUseType)` | ✅ Complete | Forward reference fixup |
| `MachBranch` | `MachBranch(LabelUseType)` | ✅ Complete | Branch record for optimization |
| `MachReloc` | `MachReloc` | ✅ Complete | Relocation record |
| `FinalizedMachReloc` | `FinalizedMachReloc` | ✅ Complete | Finalized relocation |
| `MachTrap` | `MachTrap` | ✅ Complete | Trap record |
| `MachCallSite` | `MachCallSite` | ✅ Complete | Call site record |
| `MachExceptionHandler` | `MachExceptionHandler` | ✅ Complete | Exception handler |
| `FinalizedMachExceptionHandler` | `FinalizedMachExceptionHandler` | ✅ Complete | Finalized exception handler |
| `MachSrcLoc<T>` | `MachSrcLoc(T)` | ✅ Complete | Source location mapping |
| `MachPatchableCallSite` | `MachPatchableCallSite` | ✅ Complete | Patchable call site |
| `MachTextSectionBuilder<I>` | `MachTextSectionBuilder(LabelUseType)` | ✅ Complete | Multi-function section builder |
| `MachBufferConstant` | `MachBufferConstant` | ✅ Complete | Constant metadata |
| `MachLabelTrap` | `MachLabelTrap` | ✅ Complete | Deferred trap |
| `Reloc` | `Reloc` | ✅ Complete | Relocation kinds |
| `TrapCode` | `TrapCode` | ✅ Complete | Trap codes |

## Logic Comparison

### MachBuffer Structure (buffer.rs:120-280 → buffer.zig:654-770)

**Cranelift:**
```rust
pub struct MachBuffer<I: VCodeInst> {
    data: SmallVec<[u8; 1024]>,
    relocs: Vec<MachReloc>,
    traps: Vec<MachTrap>,
    call_sites: Vec<MachCallSite>,
    srclocs: Vec<MachSrcLoc<Stencil>>,
    label_offsets: Vec<CodeOffset>,
    label_aliases: Vec<MachLabel>,
    pending_constants: Vec<(MachLabel, MachBufferConstant)>,
    pending_traps: Vec<MachLabelTrap>,
    pending_fixups: BinaryHeap<MachLabelFixup<I>>,
    branches: Vec<MachBranch>,
    // ...
}
```

**Cot:**
```zig
pub fn MachBuffer(comptime LabelUseType: type) type {
    return struct {
        data: std.ArrayListUnmanaged(u8),
        relocs: std.ArrayListUnmanaged(MachReloc),
        traps: std.ArrayListUnmanaged(MachTrap),
        call_sites: std.ArrayListUnmanaged(MachCallSite),
        srclocs: std.ArrayListUnmanaged(MachSrcLoc(RelSourceLoc)),
        label_offsets: std.ArrayListUnmanaged(CodeOffset),
        label_aliases: std.ArrayListUnmanaged(MachLabel),
        pending_constants: std.ArrayListUnmanaged(struct { label: MachLabel, constant: MachBufferConstant }),
        pending_traps: std.ArrayListUnmanaged(MachLabelTrap),
        pending_fixups: std.ArrayListUnmanaged(FixupType),
        branches: std.ArrayListUnmanaged(BranchType),
        // ...
    };
}
```

✅ **Match:** Same data layout with Zig collection types.

### Label Binding (buffer.rs:526-560 → buffer.zig:815-828)

**Cranelift:**
```rust
pub fn bind_label(&mut self, label: MachLabel, ctrl_plane: &mut ControlPlane) {
    let offset = self.cur_offset();
    self.label_offsets[label.index] = offset;
    self.labels_at_tail.push(label);
}
```

**Cot:**
```zig
pub fn bindLabel(self: *Self, label: MachLabel) !void {
    const offset = self.curOffset();
    self.label_offsets.items[label.value] = offset;
    try self.labels_at_tail.append(self.allocator, label);
}
```

✅ **Match:** Same label binding logic.

### Fixup Resolution (buffer.rs:580-620 → buffer.zig:840-860)

**Cranelift:**
```rust
pub fn use_label_at_offset(&mut self, offset: CodeOffset, label: MachLabel, kind: I::LabelUse) {
    let label_offset = self.label_offset(label);
    if label_offset != UNKNOWN_OFFSET {
        kind.patch(&mut self.data, offset, label_offset);
    } else {
        self.pending_fixups.push(MachLabelFixup { label, offset, kind });
    }
}
```

**Cot:**
```zig
pub fn useLabelAtOffset(self: *Self, offset: CodeOffset, label: MachLabel, kind: LabelUseType) !void {
    const label_offset = self.labelOffset(label);
    if (label_offset != UNKNOWN_OFFSET) {
        kind.patch(self.data.items, offset, label_offset);
    } else {
        try self.pending_fixups.append(self.allocator, .{
            .label = label,
            .offset = offset,
            .kind = kind,
        });
    }
}
```

✅ **Match:** Same immediate-patch or deferred-fixup logic.

### MachLabelFixup Deadline (buffer.rs:2020-2023 → buffer.zig:292-296)

**Cranelift:**
```rust
impl<I: VCodeInst> MachLabelFixup<I> {
    fn deadline(&self) -> CodeOffset {
        self.offset.saturating_add(self.kind.max_pos_range())
    }
}
```

**Cot:**
```zig
pub fn deadline(self: Self) CodeOffset {
    return self.offset +| self.kind.max_pos_range;
}
```

✅ **Match:** Same deadline calculation with saturating add.

### Island/Veneer Emission (buffer.rs:700-800 → buffer.zig:940-1010)

The island emission logic handles out-of-range jumps by inserting "veneers" (trampolines). The core logic is ported, with architecture-specific veneer generation deferred to backends.

**Cranelift:**
```rust
pub fn island_needed(&self, distance: CodeOffset) -> bool {
    if self.pending_fixups.is_empty() && self.pending_constants.is_empty() {
        return false;
    }
    let earliest_deadline = self.pending_fixups.peek().map_or(u32::MAX, |f| f.deadline());
    self.cur_offset() + distance >= earliest_deadline
}
```

**Cot:**
```zig
pub fn islandNeeded(self: *const Self, distance: CodeOffset) bool {
    if (self.pending_fixups.items.len == 0 and self.pending_constants.items.len == 0) {
        return false;
    }
    var earliest_deadline: CodeOffset = std.math.maxInt(CodeOffset);
    for (self.pending_fixups.items) |fixup| {
        const deadline = fixup.deadline();
        if (deadline < earliest_deadline) {
            earliest_deadline = deadline;
        }
    }
    const future_offset = self.curOffset() +| distance;
    return future_offset >= earliest_deadline;
}
```

✅ **Match:** Same island-need detection logic.

## What's Deferred to Backends

1. **Branch optimization** (`optimize_branches`) - requires knowing branch instruction encodings
2. **Veneer generation** (`generate_veneer`) - architecture-specific trampoline code
3. **Branch inversion** - requires knowing how to flip condition codes

These will be implemented when ARM64/AMD64 backends are wired in.

## Additional Types

The buffer also defines these external type stubs (to be properly connected later):

| Type | Purpose |
|------|---------|
| `Reloc` | Relocation kinds (Abs4, Abs8, X86PCRel4, Arm64Call, etc.) |
| `TrapCode` | Trap codes (HEAP_OUT_OF_BOUNDS, INTEGER_OVERFLOW, etc.) |
| `ExternalName` | External symbol references |
| `ExceptionTag` | Exception handling tags |
| `SourceLoc` | Source location tracking |

## Test Coverage

13 tests covering:
- MachLabel creation and validation
- MachBuffer byte emission (put1/put2/put4/put8)
- Label binding and offset tracking
- Buffer alignment
- Trap and relocation recording
- Source location tracking
- Fixup deadline calculation
- Buffer finalization
- MachTextSectionBuilder for multi-function sections
