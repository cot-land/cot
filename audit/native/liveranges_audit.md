# Live Ranges Module Audit

**Source**: `regalloc2/src/ion/liveranges.rs` (915 lines)
**Target**: `compiler/codegen/native/regalloc/liveness.zig`
**Status**: ✅ Complete (~980 LOC Zig)

---

## Source File Analysis

### Line Count by Section

| Section | Lines | Description |
|---------|-------|-------------|
| SpillWeight type | 31-97 (67) | f32 wrapper with bfloat16 encoding |
| slot_idx helper | 99-101 (3) | Convert usize to u16 slot index |
| create_pregs_and_vregs | 104-143 (40) | Initialize PReg/VReg data structures |
| add_liverange_to_vreg | 148-213 (66) | Add range to vreg, merge if contiguous |
| insert_use_into_liverange | 215-247 (33) | Insert use with spill weight |
| find_vreg_liverange_for_pos | 249-260 (12) | Find range at position |
| add_liverange_to_preg | 262-270 (9) | Mark PReg busy for range |
| is_live_in | 272-274 (3) | Check if vreg live-in at block |
| compute_liveness | 276-368 (93) | Worklist algorithm for liveness |
| build_liveranges | 370-772 (403) | Build live ranges from liveness |
| fixup_multi_fixed_vregs | 774-914 (141) | Handle multiple fixed-reg constraints |
| **Total** | **~870** | |

---

## Function-by-Function Audit

### 1. SpillWeight (lines 31-97)

**Rust:**
```rust
pub struct SpillWeight(f32);

pub fn spill_weight_from_constraint(
    constraint: OperandConstraint,
    loop_depth: usize,
    is_def: bool,
) -> SpillWeight

impl SpillWeight {
    pub fn to_bits(self) -> u16      // bfloat16-like: top 16 bits of f32
    pub fn from_bits(bits: u16) -> SpillWeight
    pub fn zero() -> SpillWeight
    pub fn to_f32(self) -> f32
    pub fn from_f32(x: f32) -> SpillWeight
    pub fn to_int(self) -> u32
}

impl Add<SpillWeight> for SpillWeight
```

**Zig Port Status:**

| Method | Status | Notes |
|--------|--------|-------|
| `SpillWeight` struct | ✅ | f32 wrapper |
| `spill_weight_from_constraint` | ✅ | `spillWeightFromConstraint` |
| `to_bits` | ✅ | `toBits` |
| `from_bits` | ✅ | `fromBits` |
| `zero` | ✅ | |
| `to_f32` | ✅ | `toF32` |
| `from_f32` | ✅ | `fromF32` |
| `to_int` | ✅ | `toInt` |
| `Add` trait | ✅ | `add` method |

### 2. slot_idx (line 99-101)

**Rust:**
```rust
fn slot_idx(i: usize) -> Result<u16, RegAllocError>
```

**Zig Port Status:** ✅ Implemented as `slotIdx`

### 3. Env::create_pregs_and_vregs (lines 104-143)

**Rust:**
```rust
pub fn create_pregs_and_vregs(&mut self) {
    // 1. Resize pregs to PReg::NUM_INDEX
    // 2. Mark fixed_stack_slots as is_stack
    // 3. Set preferred_victim_by_class
    // 4. Create VRegs with VRegData
    // 5. Create allocations for each instruction operand
}
```

**Zig Port Status:**

| Step | Status | Notes |
|------|--------|-------|
| Resize pregs | ✅ | PReg.NUM_INDEX = 256 |
| Mark fixed_stack_slots | ✅ | From MachineEnv |
| Set preferred_victim_by_class | ✅ | PRegSet.maxPreg() added |
| Create VRegs | ✅ | With VRegData |
| Create allocations | ✅ | Per-instruction via scratch_vreg_ranges |

### 4. Env::add_liverange_to_vreg (lines 148-213)

**Rust:**
```rust
pub fn add_liverange_to_vreg(
    &mut self,
    vreg: VRegIndex,
    mut range: CodeRange,
) -> LiveRangeIndex {
    // 1. Handle allow_multiple_vreg_defs() case
    // 2. Assert range ordering invariant
    // 3. If not contiguous with last, create new range
    // 4. If contiguous, extend existing range
}
```

**Zig Port Status:**

| Step | Status | Notes |
|------|--------|-------|
| Multiple vreg defs handling | ✅ | allow_multiple_defs param |
| Range ordering assertion | ✅ | Via contiguous check |
| Create new range | ✅ | Full implementation |
| Extend existing range | ✅ | Contiguous merge |

### 5. Env::insert_use_into_liverange (lines 215-247)

**Rust:**
```rust
pub fn insert_use_into_liverange(&mut self, into: LiveRangeIndex, mut u: Use) {
    // 1. Get constraint, block, loop_depth
    // 2. Compute spill weight
    // 3. Set u.weight
    // 4. Push use to range
    // 5. Update range spill weight
}
```

**Zig Port Status:** ✅ Implemented as `insertUseIntoLiverange` with CFGInfo integration

### 6. Env::find_vreg_liverange_for_pos (lines 249-260)

**Rust:**
```rust
pub fn find_vreg_liverange_for_pos(
    &self,
    vreg: VRegIndex,
    pos: ProgPoint,
) -> Option<LiveRangeIndex>
```

**Zig Port Status:** ✅ Implemented as `findVregLiverangeForPos`

### 7. Env::add_liverange_to_preg (lines 262-270)

**Rust:**
```rust
pub fn add_liverange_to_preg(&mut self, range: CodeRange, reg: PReg)
```

**Zig Port Status:** ✅ Implemented as `addLiverangeToPreg`

### 8. Env::is_live_in (lines 272-274)

**Rust:**
```rust
pub fn is_live_in(&mut self, block: Block, vreg: VRegIndex) -> bool
```

**Zig Port Status:** ✅ Implemented as `isLiveIn`

### 9. Env::compute_liveness (lines 276-368)

**Rust:**
```rust
pub fn compute_liveness(&mut self) -> Result<(), RegAllocError> {
    // 1. Create livein/liveout IndexSets
    // 2. Initialize workqueue with postorder
    // 3. While workqueue not empty:
    //    a. Pop block
    //    b. Start with liveout
    //    c. Add branch blockparams
    //    d. Process instructions in reverse (Late then Early)
    //    e. Remove block params from live
    //    f. Propagate to predecessors
    //    g. Store livein
    // 4. Check entry block has no liveins
}
```

**Zig Port Status:**

| Step | Status | Notes |
|------|--------|-------|
| Create livein/liveout | ✅ | IndexSet per block |
| Initialize workqueue | ✅ | Stack-based worklist from postorder |
| Worklist loop | ✅ | Full worklist algorithm |
| Process instructions | ✅ | Reverse iteration with Late/Early |
| Handle blockparams | ✅ | Branch args via branchBlockparams |
| Propagate to preds | ✅ | Union with liveouts |
| Check entry liveins | ✅ | Returns EntryLivein error |

### 10. Env::build_liveranges (lines 370-772) - **CRITICAL**

This is the largest and most complex function (~403 lines).

**Rust structure:**
```rust
pub fn build_liveranges(&mut self) -> Result<(), RegAllocError> {
    // Setup (lines 379-385)
    let mut vreg_ranges = ...;
    let mut operand_rewrites = ...;

    // Main loop: blocks in reverse (lines 387-732)
    for i in (0..self.func.num_blocks()).rev() {
        // a. Init live from liveouts (394)
        // b. Create blockparam_out entries (398-418)
        // c. Create initial ranges for live vregs (421-433)
        // d. Set vreg blockparam data (436-438)
        // e. Process instructions in reverse (442-703):
        //    - Mark clobbers (444-455)
        //    - Find reused inputs (461-470)
        //    - Preprocess fixed-reg conflicts (485-570)
        //    - Process defs and uses (573-702)
        // f. Handle block parameters (708-731)
    }

    // Finalization (lines 744-769)
    // - Reverse ranges in vregs
    // - Reverse uses in ranges
    // - Sort blockparam_ins/outs
    // - Update stats
}
```

**Zig Port Status:**

| Section | Status | Lines | Notes |
|---------|--------|-------|-------|
| Setup (vreg_ranges, operand_rewrites) | ✅ | 379-385 | scratch_vreg_ranges, scratch_operand_rewrites |
| Create blockparam_out entries | ✅ | 398-418 | For branch successors via branchBlockparams |
| Create initial live ranges | ✅ | 421-433 | Live vregs get [entry, exit) range |
| Set vreg blockparam | ✅ | 436-438 | vregs[i].blockparam = block |
| Mark clobbers | ✅ | 444-455 | addLiverangeToPreg at After point |
| Find reused inputs | ✅ | 461-470 | Reuse constraint detection |
| Preprocess fixed-reg conflicts | ✅ | 485-570 | MultiFixedRegFixup, operand rewriting |
| Process defs | ✅ | 621-670 | Create/extend range, insertUseIntoLiverange |
| Process uses | ✅ | 672-699 | Create/extend range, insertUseIntoLiverange |
| Handle block params | ✅ | 708-731 | blockparam_ins creation |
| Reverse ranges | ✅ | 744-755 | std.mem.reverse |
| Reverse uses | ✅ | 757-760 | std.mem.reverse |
| Sort blockparams | ✅ | 762-763 | std.mem.sort by key() |
| Update stats | ✅ | 765-768 | initial_liverange_count, etc. |

### 11. Env::fixup_multi_fixed_vregs (lines 774-914)

**Rust:**
```rust
pub fn fixup_multi_fixed_vregs(&mut self) {
    // For each vreg:
    //   For each range:
    //     Group uses by ProgPoint (chunk_by_mut)
    //     For groups with 2+ uses:
    //       Detect constraint conflicts
    //       Pick primary constraint (FixedReg > Reg > FixedStack)
    //       Rewrite incompatible to Any
    //       Add MultiFixedRegFixup entries
    //       Add extra clobbers
}
```

**Zig Port Status:**

| Step | Status | Notes |
|------|--------|-------|
| Iterate vregs | ✅ | Outer loop over vregs.items |
| Iterate ranges | ✅ | Inner loop over ranges.items |
| Group uses by pos | ✅ | Manual grouping with position comparison |
| Detect conflicts | ✅ | requires_reg, num_fixed_reg, min_limit, etc. |
| Pick primary constraint | ✅ | FixedReg priority, min_limit check |
| Rewrite to Any | ✅ | Operand.new() |
| Add fixups | ✅ | MultiFixedRegFixup with secondary level |
| Add clobbers | ✅ | addLiverangeToPreg for extra clobbers |

---

## Completed Implementation

All critical functions have been ported:

| Function | Status | Notes |
|----------|--------|-------|
| `slotIdx` | ✅ | Helper for u16 operand slot |
| `SpillWeight` | ✅ | Full type with bfloat16 encoding |
| `spillWeightFromConstraint` | ✅ | Loop depth, constraint bonuses |
| `createPregsAndVregs` | ✅ | PReg/VReg initialization |
| `addLiverangeToVreg` | ✅ | Range creation with merge |
| `insertUseIntoLiverange` | ✅ | Weight computation |
| `findVregLiverangeForPos` | ✅ | Position lookup |
| `addLiverangeToPreg` | ✅ | PReg busy marking |
| `isLiveIn` | ✅ | Liveness query |
| `computeLiveness` | ✅ | Full worklist algorithm |
| `buildLiveranges` | ✅ | 403-line algorithm |
| `fixupMultiFixedVregs` | ✅ | Multi-constraint handling |

### Data Structures in LivenessContext

All required data structures implemented:

| Field | Status | Type |
|-------|--------|------|
| `liveins` | ✅ | ArrayListUnmanaged(IndexSet) |
| `liveouts` | ✅ | ArrayListUnmanaged(IndexSet) |
| `ranges` | ✅ | ArrayListUnmanaged(LiveRange) |
| `vregs` | ✅ | ArrayListUnmanaged(VRegData) |
| `pregs` | ✅ | ArrayListUnmanaged(PRegData) |
| `blockparam_outs` | ✅ | ArrayListUnmanaged(BlockparamOut) |
| `blockparam_ins` | ✅ | ArrayListUnmanaged(BlockparamIn) |
| `multi_fixed_reg_fixups` | ✅ | ArrayListUnmanaged(MultiFixedRegFixup) |
| `scratch_workqueue` | ✅ | ArrayListUnmanaged(Block) as stack |
| `scratch_workqueue_set` | ✅ | AutoHashMap(u32, void) |
| `scratch_vreg_ranges` | ✅ | ArrayListUnmanaged(LiveRangeIndex) |
| `scratch_operand_rewrites` | ✅ | AutoHashMap(usize, Operand) |
| `preferred_victim_by_class` | ✅ | [3]PReg |

---

## Test Coverage

| Test | Status | Description |
|------|--------|-------------|
| SpillWeight basic | ✅ | Creation and arithmetic |
| SpillWeight bits round-trip | ✅ | bfloat16 encoding |
| SpillWeight toBits matches regalloc2 | ✅ | Verifies >> 15 shift |
| spillWeightFromConstraint | ✅ | Weight computation |
| slotIdx | ✅ | u16 conversion and overflow |
| LivenessContext init/deinit | ✅ | Memory management |
| addLiverangeToVreg basic | ✅ | Single range |
| addLiverangeToVreg merge | ✅ | Contiguous merge |
| addLiverangeToVreg non-contiguous | ✅ | No merge for gap |
| findVregLiverangeForPos | ✅ | Position lookup |
| insertUseIntoLiverange | ✅ | Use and weight insertion |
| preferred_victim_by_class | ✅ | ARM64 victim selection |

Integration tests (require mock Function):

| Test | Status | Notes |
|------|--------|-------|
| computeLiveness basic | ⏳ | Needs Function interface implementation |
| computeLiveness loop | ⏳ | Needs CFGInfo with loop depth |
| buildLiveranges basic | ⏳ | Needs full Function impl |
| buildLiveranges blockparams | ⏳ | Needs block param iteration |
| fixupMultiFixedVregs | ⏳ | Needs populated ranges |

---

## Implementation Plan - COMPLETED

### Phase 1: Complete SpillWeight and helpers ✅
- [x] SpillWeight type
- [x] spillWeightFromConstraint
- [x] slotIdx helper

### Phase 2: LivenessContext data structures ✅
- [x] All scratch fields (workqueue, vreg_ranges, operand_rewrites)
- [x] Liveins/liveouts as IndexSets
- [x] Ranges, vregs, pregs arrays
- [x] Blockparam tracking

### Phase 3: computeLiveness ✅
- [x] Full worklist algorithm
- [x] Stack-based processing (order doesn't matter for fixed point)
- [x] scratch_workqueue/workqueue_set

### Phase 4: buildLiveranges ✅
- [x] blockparam_out creation
- [x] Initial live ranges for block live-outs
- [x] Clobber handling via addLiverangeToPreg
- [x] Reused input detection
- [x] Fixed-reg conflict preprocessing with MultiFixedRegFixup
- [x] Def processing (create/trim range, insert use)
- [x] Use processing (create/extend range, insert use)
- [x] Block param handling (blockparam_ins)
- [x] Finalization (reverse ranges/uses, sort blockparams)

### Phase 5: fixupMultiFixedVregs ✅
- [x] Use grouping by position (manual loop)
- [x] Conflict detection (requires_reg, num_fixed_reg, min_limit)
- [x] Constraint rewriting to Any
- [x] Fixup and clobber insertion

### Phase 6: Tests ✅
- [x] Unit tests for SpillWeight, slotIdx
- [x] Unit tests for LivenessContext operations
- [x] Integration tests deferred (need Function interface)

---

## Reference: Key Algorithms

### Liveness Worklist Algorithm
```
1. Initialize livein[b] = liveout[b] = {} for all blocks
2. Add all blocks to worklist in postorder
3. While worklist not empty:
   a. Pop block b
   b. live = liveout[b]
   c. Add branch blockparams to live
   d. For each inst in reverse:
      - For Late operands: use adds to live, def removes
      - For Early operands: use adds to live, def removes
   e. Remove block params from live
   f. For each predecessor p:
      if live ⊄ liveout[p]:
        liveout[p] = liveout[p] ∪ live
        add p to worklist
   g. livein[b] = live
4. Assert livein[entry] = {}
```

### Live Range Building Algorithm
```
For each block b in reverse order:
  1. live = liveout[b]
  2. Create blockparam_out entries for branch successors
  3. For each vreg in live:
     Create range [block_entry, block_exit)
  4. Set vreg.blockparam for block params
  5. For each inst in reverse:
     a. Mark clobbers at After point
     b. Find reused inputs
     c. Handle fixed-reg conflicts
     d. For After operands:
        - Def: create range if dead, insert use, trim range, set flag
        - Use: create/extend range, insert use
     e. For Before operands:
        - Same as After
  6. Handle block params (remove from live, create blockparam_ins)
Finally:
  - Reverse ranges in each vreg
  - Reverse uses in each range
  - Sort blockparam_ins/outs
```
