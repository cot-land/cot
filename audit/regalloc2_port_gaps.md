# regalloc2 Port Gap Analysis

This document compares the original regalloc2 Rust implementation (`~/learning/regalloc2/src/ion/`) with our Zig port (`/Users/johnc/cot-land/cot/compiler/codegen/native/regalloc/`).

## Summary of Findings

| Category | Critical | Major | Minor | Notes |
|----------|----------|-------|-------|-------|
| Missing Functions | 0 | 3 | 5 | |
| Logic Differences | ~~2~~ 0 | 4 | 6 | Clobber/def collision fixed |
| Missing State/Flags | ~~1~~ 0 | 2 | 3 | isSpilled flag removed |
| Data Structure Gaps | 0 | 2 | 4 | |

**Last Updated**: February 2026 - Critical gaps resolved (see Section 7)

---

## 1. process.rs vs process.zig

### 1.1 `process_bundle` Function Flow

**Rust (regalloc2)**:
1. Check requirement conflicts - if conflict, call `split_and_requeue_bundle` with `conflict.suggested_split_point()` and `conflict.should_trim_edges_around_split()`
2. Handle `Requirement::Any` - if spill bundle exists, move ranges to it and return
3. Main allocation loop with proper termination conditions
4. For `Requirement::Stack`, mark spillset.required = true and return immediately

**Zig (our port)**:
1. Similar flow but simplified conflict handling
2. **DIFFERENCE**: Doesn't use `RequirementConflictAt` variants for split decisions - just uses first range's `from` point

**Gap**: The Zig port loses precision in split point selection. The Rust version distinguishes:
- `StackToReg` - late split (just before reg use)
- `RegToStack` - early split (just after last reg use)
- `Other` - late split with edge trimming

### 1.2 Fixed-Reg Requirements Handling

**Rust**:
```rust
let fixed_preg = match req {
    Requirement::FixedReg(preg) | Requirement::FixedStack(preg) => Some(preg),
    // ...
};
```

**Zig**:
```zig
const fixed_preg: ?PReg = switch (req) {
    .fixed_reg => |preg| preg,
    .fixed_stack => |preg| preg,
    // ...
};
```

**Status**: Equivalent - correctly handles both cases.

### 1.3 Split and Eviction Logic

**Rust**:
```rust
if !self.minimal_bundle(bundle)
    && (attempts >= 2
        || lowest_cost_evict_conflict_cost.is_none()
        || our_spill_weight <= lowest_cost_evict_conflict_cost.unwrap())
{
    // Split path
} else {
    // Evict path
}
```

**Zig**:
```zig
if (!self.minimalBundle(bundle) and
    (attempts >= 2 or
    lowest_cost_evict_conflict_cost == null or
    our_spill_weight <= lowest_cost_evict_conflict_cost.?))
{
    // Split path
} else {
    // Evict path
}
```

**Status**: Equivalent logic.

### 1.4 Bundles Exiting Without Allocation

**Rust**: Several valid exit paths:
1. `Requirement::Stack` - sets `spillset.required = true`, returns Ok
2. `Requirement::Any` with existing spill bundle - moves ranges to spill bundle
3. `Requirement::Any` without spill bundle - adds to `spilled_bundles`
4. Successful allocation
5. Successful split and requeue

**Zig**: Same paths exist but with some differences:

**GAP - CRITICAL**: The Zig port has a bug in handling bundles that get spilled multiple times:
- When a bundle with `Requirement::Any` reaches the allocation loop, it sets `isSpilled()` and adds to `spilled_bundles`
- But if the same bundle was already queued before being marked spilled, it could be processed again
- The `isSpilled()` check at the start of `processBundle` was added to fix this, but this check didn't exist in regalloc2

**Regalloc2 approach**: Uses `spilled_bundles.push(bundle)` followed by `break` - the bundle is never re-added to the allocation queue. The bundle's allocation stays as `Allocation::none()`, and `tryAllocatingRegsForSpilledBundles` later gives it a second chance.

### 1.5 Split Into Minimal Bundles

**Rust**:
```rust
pub fn split_into_minimal_bundles(&mut self, bundle: LiveBundleIndex, hint: PReg) {
    // Uses scratch_removed_lrs (HashSet) for O(1) lookup
    // Uses scratch_removed_lrs_vregs (HashSet) for vreg tracking
    assert_eq!(self.ctx.scratch_removed_lrs_vregs.len(), 0);
    // ...
}
```

**Zig**:
```zig
pub fn splitIntoMinimalBundles(self: *Self, bundle: LiveBundleIndex, hint: PReg) !void {
    self.scratch_removed_lrs_vregs.clear();
    self.scratch_removed_lrs.clear();
    // ...
}
```

**Status**: Equivalent, but Zig uses IndexSet wrapper vs FxHashSet.

### 1.6 Missing: `try_to_allocate_bundle_to_reg` BTree Optimization

**Rust** uses BTreeMap with range iteration:
```rust
let mut preg_range_iter = self.ctx.pregs[reg.index()]
    .allocations
    .btree
    .range(from_key..)
    .peekable();
```

This enables O(n log n) + O(b) complexity for conflict detection.

**Zig** uses linear scan:
```zig
for (preg_allocs.items.items) |item| {
    if (item.key.order(key) != .eq) continue;
    // ...
}
```

**GAP - PERFORMANCE**: The Zig port has O(n * b) complexity where n = preg allocations, b = bundle ranges.

---

## 2. spill.rs vs spill.zig

### 2.1 `try_allocating_regs_for_spilled_bundles`

**Rust**:
```rust
pub fn try_allocating_regs_for_spilled_bundles(&mut self) {
    for i in 0..self.ctx.spilled_bundles.len() {
        let bundle = self.ctx.spilled_bundles[i];
        // Sort ranges
        self.ctx.bundles[bundle].ranges.sort_unstable_by_key(|entry| entry.range.from);
        // Try allocation
        if let AllocRegResult::Allocated(_) = self.try_to_allocate_bundle_to_reg(...) {
            success = true;
        }
        if !success {
            self.ctx.spillsets[self.ctx.bundles[bundle].spillset].required = true;
        }
    }
}
```

**Zig**:
```zig
pub fn tryAllocatingRegsForSpilledBundles(self: *Self) !void {
    // Similar flow but with additional debug prints
    // ...
}
```

**Status**: Equivalent core logic.

### 2.2 How `spillset.required` Gets Set

**Rust paths**:
1. `process_bundle` when `Requirement::Stack`
2. `try_allocating_regs_for_spilled_bundles` when allocation fails

**Zig paths**:
Same two paths exist.

**Status**: Equivalent.

### 2.3 `allocate_spillslots`

**Rust**:
```rust
pub fn allocate_spillslots(&mut self) {
    const MAX_ATTEMPTS: usize = 10;
    for spillset in 0..self.ctx.spillsets.len() {
        // Circular probing with probe_start
        // ...
    }
    // Assign actual slot indices
    for i in 0..self.ctx.spillslots.len() {
        self.ctx.spillslots[i].alloc = self.allocate_spillslot(self.ctx.spillslots[i].slots);
    }
}
```

**Zig**:
Same structure with `MAX_ATTEMPTS = 10` and circular probing.

**Status**: Equivalent.

---

## 3. data_structures.rs vs ion_data.zig

### 3.1 LiveBundle Fields

**Rust**:
```rust
pub struct LiveBundle {
    pub(crate) ranges: LiveRangeList,
    pub spillset: SpillSetIndex,
    pub allocation: Allocation,
    pub prio: u32,
    pub spill_weight_and_props: u32,  // bits: spill_weight | minimal | fixed | fixed_def | stack
    pub limit: Option<u8>,
}
```

**Zig**:
```zig
pub const LiveBundle = struct {
    ranges: std.ArrayListUnmanaged(LiveRangeListEntry),
    spillset: SpillSetIndex,
    allocation: Allocation,
    prio: u32,
    spill_weight_and_props: u32,  // bits 0-27 = spill_weight, bits 28-31 = props
    limit: ?u8,
    // ...
};
```

**Status (February 2026)**: Now matches regalloc2 exactly. The `isSpilled()` flag workaround was removed after fixing the root cause (clobber/def collisions in call lowering). Both use 28 bits for spill weight:
```rust
// Both Rust and Zig now:
pub const BUNDLE_MAX_SPILL_WEIGHT: u32 = (1 << 28) - 1;
```

### 3.2 LiveRangeSet Implementation

**Rust**: Uses `BTreeMap<LiveRangeKey, LiveRangeIndex>` for O(log n) operations.

**Zig**: Uses `ArrayListUnmanaged` with linear scan for O(n) operations.

**GAP - PERFORMANCE**: Significant for large allocation maps.

### 3.3 SpillSetRanges

**Rust**: Uses `BTreeMap<LiveRangeKey, SpillSetIndex>`.

**Zig**: Uses `ArrayListUnmanaged` with linear scan.

**Status**: Same performance gap as LiveRangeSet.

### 3.4 PrioQueue

**Rust**: Uses `alloc::collections::BinaryHeap<PrioQueueEntry>`.

**Zig**: Uses `std.PriorityQueue`.

**Status**: Equivalent functionality.

### 3.5 Missing: Ctx Fields

**Rust** has these fields in `Ctx` that may not be fully ported:
- `scratch_operand_rewrites: FxHashMap<usize, Operand>` - for operand rewriting
- `scratch_workqueue_set: FxHashSet<Block>` - for block processing dedup
- `annotations_enabled: bool` - for debug annotations
- `debug_annotations: FxHashMap<ProgPoint, Vec<String>>` - annotation storage

**Zig**: Most of these are not present or simplified.

### 3.6 BundleProperties Struct

**Rust** has a separate struct:
```rust
pub struct BundleProperties {
    pub minimal: bool,
    pub fixed: bool,
}
```

**Zig**: Uses inline methods on LiveBundle instead. **Status**: Equivalent.

---

## 4. moves.rs vs ion_moves.zig

### 4.1 `get_alloc_for_range`

**Rust**:
```rust
pub fn get_alloc_for_range(&self, range: LiveRangeIndex) -> Allocation {
    let bundle = self.ctx.ranges[range].bundle;
    let bundledata = &self.ctx.bundles[bundle];
    if bundledata.allocation != Allocation::none() {
        bundledata.allocation
    } else {
        self.ctx.spillslots[self.ctx.spillsets[bundledata.spillset].slot.index()].alloc
    }
}
```

**Zig**:
```zig
pub fn getAllocForRange(self: *const Self, range_idx: LiveRangeIndex) Allocation {
    // Same logic but with added panic if spillset not required
    if (!spillset_data.required) {
        @panic("Bundle has no allocation and spillset not required");
    }
    // ...
}
```

**GAP - BEHAVIOR**: The Zig port panics when a bundle has no allocation and spillset isn't required. This is defensive but differs from Rust which would just access the (potentially invalid) spillslot.

**Note**: In correct operation, this should never happen. The panic was added to catch bugs.

### 4.2 When No Allocation is Valid

**Rust**: In `get_alloc_for_range`, if bundle has no allocation, it falls through to spillslot lookup. This is valid because:
1. After `process_bundles`, all bundles either have allocation or are in `spilled_bundles`
2. After `try_allocating_regs_for_spilled_bundles`, failed bundles have `spillset.required = true`
3. After `allocate_spillslots`, all required spillsets have valid slots

**Zig**: Same invariants should hold, but the defensive panic catches violations.

### 4.3 Handling Spilled Bundles During Move Insertion

**Rust** in `apply_allocations_and_insert_moves`:
```rust
for range_idx in 0..self.vregs[vreg].ranges.len() {
    let entry = self.vregs[vreg].ranges[range_idx];
    let alloc = self.get_alloc_for_range(entry.index);
    debug_assert!(alloc != Allocation::none());
    // ...
}
```

The assertion `alloc != Allocation::none()` assumes all ranges have valid allocations.

**Zig**: Similar assertions exist.

### 4.4 Missing: PrevBuffer

**Rust** has a complex `PrevBuffer` struct for tracking previous live range during move insertion:
```rust
struct PrevBuffer {
    prev: Option<LiveRangeListEntry>,
    prev_ins_idx: usize,
    buffered: Option<LiveRangeListEntry>,
    buffered_ins_idx: usize,
}
```

This handles overlapping live ranges that start at the same program point.

**Zig**: Has `PrevBuffer` but with simplified logic.

### 4.5 Missing: Inter-Block Move Optimization

**Rust** uses `FxHashMap<Block, Allocation>` for `inter_block_sources` to prefer register allocations:
```rust
match inter_block_sources.entry(block) {
    Entry::Occupied(mut entry) => {
        if !entry.get().is_reg() {
            entry.insert(alloc);
        }
    }
    Entry::Vacant(entry) => {
        entry.insert(alloc);
    }
}
```

**Zig**: The `applyAllocationsAndInsertMoves` is simplified and may not have this optimization.

### 4.6 Missing: Reuse Input Handling

**Rust** has dedicated handling for reuse-input constraints:
```rust
let mut reuse_input_insts = Vec::with_capacity(self.func.num_insts() / 2);
// ... collect reuse instructions
for inst in reuse_input_insts {
    // Insert moves for reuse operands
}
```

**Zig**: Has basic handling in `applyAllocationsAndInsertMoves` but may be less complete.

### 4.7 RedundantMoveEliminator

**Rust** has `RedundantMoveEliminator` imported from separate file.

**Zig**: Has inline implementation in `ion_moves.zig`.

**Status**: Equivalent functionality.

---

## 5. requirement.rs vs merge.zig

### 5.1 RequirementConflictAt

**Rust**:
```rust
pub enum RequirementConflictAt {
    StackToReg(ProgPoint),
    RegToStack(ProgPoint),
    Other(ProgPoint),
}
```

**Zig**:
```zig
pub const RequirementConflictAt = union(enum) {
    stack_to_reg: ProgPoint,
    reg_to_stack: ProgPoint,
    other: ProgPoint,
};
```

**Status**: Equivalent.

### 5.2 Requirement.merge

**Rust**: Returns `Result<Requirement, RequirementConflict>`.

**Zig**: Returns `RequirementConflict!Requirement`.

**Status**: Equivalent semantics.

### 5.3 compute_requirement

**Rust** tracks `last_pos` for better split suggestions:
```rust
let mut last_pos = ProgPoint::before(Inst::new(0));
for entry in ranges {
    for u in &self.ranges[entry.index].uses {
        req = req.merge(r).map_err(|_| {
            if req.is_stack() && r.is_reg() {
                RequirementConflictAt::StackToReg(u.pos)
            } else if req.is_reg() && r.is_stack() {
                RequirementConflictAt::RegToStack(last_pos)  // Uses previous position!
            } else {
                RequirementConflictAt::Other(u.pos)
            }
        })?;
        last_pos = u.pos;
    }
}
```

**Zig**: Has similar logic but doesn't return the conflict details up the call stack properly:
```zig
req = mergeRequirements(req, r) catch {
    // Computes conflict type but just returns error.ConflictAt
    return error.ConflictAt;
};
```

**GAP**: The conflict details are computed but discarded in Zig.

---

## 6. Architectural Differences

### 6.1 Bump Allocator

**Rust**: Uses `Bump` allocator for arena-style allocation of ranges and bundles.
```rust
pub type LiveRangeList = Vec2<LiveRangeListEntry, Bump>;
pub type UseList = Vec2<Use, Bump>;
```

**Zig**: Uses standard `ArrayListUnmanaged` with passed allocator.

**Implication**: Memory allocation patterns differ. Rust version may have better cache locality.

### 6.2 Error Handling

**Rust**: Uses `Result<T, RegAllocError>` with `?` operator.

**Zig**: Uses `error` unions with `try` keyword.

**Status**: Semantically equivalent but different ergonomics.

### 6.3 Trace Macro

**Rust**: Uses `trace!` macro throughout for debugging.

**Zig**: Uses `std.debug.print` inline.

**Status**: Equivalent but Zig version may have more overhead in release builds.

---

## 7. Known Critical Issues

### 7.1 Bundle Re-Queueing Bug (FIXED - February 2026)

**Issue**: When splitting bundles, the split parts were being re-queued even if they were already marked as spilled.

**Rust approach**: Never marks bundles as "spilled" explicitly. Uses the spilled_bundles list and never re-queues bundles that are in that list.

**Resolution**: The `isSpilled()` flag workaround was removed. The root cause was actually clobber/def collisions in call lowering (see 7.2). With that fixed, bundles no longer get stuck in the allocation loop.

### 7.2 Clobber/Def Collision in Call Instructions (FIXED - February 2026)

**Issue**: Call instructions had clobber sets that included return registers, violating regalloc2's invariant: "clobbers and defs must not collide."

**Root cause**: Our call lowering in `isa/aarch64/lower.zig` was not removing return registers from the clobber set.

**Resolution**: Ported Cranelift's `gen_call_info` pattern - after building the defs list, remove return registers from clobbers:
```zig
// Port of Cranelift's gen_call_info: remove return regs from clobbers.
// regalloc2 requires that clobbers and defs must not collide.
// See cranelift/codegen/src/machinst/abi.rs lines 2114-2119
clobbers.remove(ret_preg);
```

### 7.3 Label Fixup Timing (FIXED - February 2026)

**Issue**: Loop test panic with "index out of bounds" - trying to patch label at offset 40 but buffer only had 36 bytes.

**Root cause**: Code was patching labels immediately when bound, but the instruction bytes hadn't been emitted yet.

**Resolution**: Ported Cranelift's `use_label_at_offset` pattern - always defer fixups to be processed during `finish()`:
```zig
/// Port of Cranelift's use_label_at_offset: always defers fixups to be
/// processed later during finish(). This is critical because the
/// instruction bytes may not have been emitted yet when this is called.
pub fn useLabelAtOffset(self: *Self, offset: CodeOffset, label: MachLabel, kind: LabelUseType) !void {
    // Always add to pending_fixups - fixups are processed during finish()
    try self.pending_fixups.append(self.allocator, .{...});
}
```

### ~~7.4 Spill Weight Bit Layout Mismatch~~ (NO LONGER APPLICABLE)

The `isSpilled` flag that caused the bit layout mismatch was removed. Spill weight now uses the full 28 bits matching regalloc2.

---

## 8. Recommendations

### High Priority

1. **Fix RequirementConflictAt propagation** - The conflict details should be returned to `processBundle` for better split point selection.

2. ~~**Consider removing isSpilled flag**~~ ✅ **DONE** - Flag removed after fixing clobber/def collision root cause.

3. **Review inter-block move optimization** - The register-preferring logic for inter_block_sources may be missing.

### Medium Priority

4. **Implement BTreeMap for LiveRangeSet** - Would improve allocation performance for large functions.

5. **Add proper reuse-input tracking** - Ensure all reuse constraints are handled correctly.

### Low Priority

6. **Add debug annotation support** - Would help with debugging allocation issues.

7. **Consider arena allocation** - Could improve memory locality and allocation performance.

---

## 9. Change Log

| Date | Fix | Files Changed |
|------|-----|---------------|
| Feb 2026 | Remove isSpilled flag, fix clobber/def collision | lower.zig, ion_data.zig |
| Feb 2026 | Fix label fixup timing (defer to finish()) | buffer.zig |
| Feb 2026 | Add TooManyLiveRegs handling for fixed regs | process.zig |

---

## Appendix: Function Mapping

| regalloc2 (Rust) | Cot (Zig) | Status |
|------------------|-----------|--------|
| `process_bundles` | `processBundles` | Complete |
| `process_bundle` | `processBundle` | Minor gaps |
| `try_to_allocate_bundle_to_reg` | `tryToAllocateBundleToReg` | Performance gap |
| `evict_bundle` | `evictBundle` | Complete |
| `bundle_spill_weight` | `bundleSpillWeight` | Complete |
| `maximum_spill_weight_in_bundle_set` | `maximumSpillWeightInBundleSet` | Complete |
| `recompute_bundle_properties` | `recomputeBundleProperties` | Complete |
| `minimal_bundle` | `minimalBundle` | Complete |
| `recompute_range_properties` | `recomputeRangeProperties` | Complete |
| `get_or_create_spill_bundle` | `getOrCreateSpillBundle` | Complete |
| `split_and_requeue_bundle` | `splitAndRequeueBundle` | Complete |
| `split_into_minimal_bundles` | `splitIntoMinimalBundles` | Complete |
| `compute_requirement` | `computeRequirement` | Gap in error details |
| `requirement_from_operand` | `requirementFromOperand` | Complete |
| `try_allocating_regs_for_spilled_bundles` | `tryAllocatingRegsForSpilledBundles` | Complete |
| `spillslot_can_fit_spillset` | `spillslotCanFitSpillset` | Complete |
| `allocate_spillset_to_spillslot` | `allocateSpillsetToSpillslot` | Complete |
| `allocate_spillslots` | `allocateSpillslots` | Complete |
| `allocate_spillslot` | `allocateSpillslot` | Complete |
| `get_alloc_for_range` | `getAllocForRange` | Added defensive panic |
| `apply_allocations_and_insert_moves` | `applyAllocationsAndInsertMoves` | Simplified |
| `resolve_inserted_moves` | `resolveInsertedMoves` | Complete |
| `is_start_of_block` | `isStartOfBlock` | Complete |
| `is_end_of_block` | `isEndOfBlock` | Complete |
