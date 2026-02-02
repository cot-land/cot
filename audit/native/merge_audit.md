# Bundle Merging Module Audit

**Source**: `regalloc2/src/ion/merge.rs` (~440 lines) + `regalloc2/src/ion/requirement.rs` (~183 lines)
**Target**: `compiler/codegen/native/regalloc/merge.zig`
**Status**: ✅ Complete (~710 LOC, 10 tests)

---

## Source File Analysis

### merge.rs Line Count by Section

| Section | Lines | Description |
|---------|-------|-------------|
| merge_bundle_properties | 24-40 (17) | Transfer cached properties between bundles |
| merge_bundles | 42-257 (216) | Main merge logic with overlap detection |
| merge_vreg_bundles | 259-387 (129) | Create bundles per vreg and merge |
| compute_bundle_prio | 389-398 (10) | Calculate bundle priority |
| compute_bundle_limit | 400-424 (25) | Find most restrictive limit |
| queue_bundles | 426-439 (14) | Queue bundles for allocation |
| **Total** | **~411** | |

### requirement.rs Line Count by Section

| Section | Lines | Description |
|---------|-------|-------------|
| RequirementConflict | 18 | Error marker type |
| RequirementConflictAt | 20-57 (38) | Conflict with split suggestion |
| Requirement enum | 59-112 (54) | Operand requirement representation |
| requirement_from_operand | 116-130 (15) | Convert operand to requirement |
| compute_requirement | 132-167 (36) | Compute bundle's requirement |
| merge_bundle_requirements | 169-181 (13) | Merge two bundles' requirements |
| **Total** | **~156** | |

---

## Function-by-Function Audit

### 1. RequirementConflict (requirement.rs:18)

**Rust:**
```rust
pub struct RequirementConflict;
```

**Zig Port Status:** ✅ Implemented as `RequirementConflict` error type

### 2. RequirementConflictAt (requirement.rs:20-57)

**Rust:**
```rust
pub enum RequirementConflictAt {
    StackToReg(ProgPoint),
    RegToStack(ProgPoint),
    Other(ProgPoint),
}

impl RequirementConflictAt {
    pub fn should_trim_edges_around_split(self) -> bool
    pub fn suggested_split_point(self) -> ProgPoint
}
```

**Zig Port Status:** ✅ Implemented with `shouldTrimEdgesAroundSplit()` and `suggestedSplitPoint()`

### 3. Requirement (requirement.rs:59-112)

**Rust:**
```rust
pub enum Requirement {
    Any,
    Register,
    FixedReg(PReg),
    Limit(usize),
    Stack,
    FixedStack(PReg),
}

impl Requirement {
    pub fn merge(self, other: Requirement) -> Result<Requirement, RequirementConflict>
    pub fn is_stack(self) -> bool
    pub fn is_reg(self) -> bool
}
```

**Zig Port Status:** ✅ Implemented with `merge()`, `isStack()`, `isReg()`

### 4. requirement_from_operand (requirement.rs:116-130)

**Rust:**
```rust
pub fn requirement_from_operand(&self, op: Operand) -> Requirement
```

**Zig Port Status:** ✅ `MergeContext.requirementFromOperand()`

### 5. compute_requirement (requirement.rs:132-167)

**Rust:**
```rust
pub fn compute_requirement(
    &self,
    bundle: LiveBundleIndex,
) -> Result<Requirement, RequirementConflictAt>
```

**Zig Port Status:** ✅ `MergeContext.computeRequirement()`

### 6. merge_bundle_requirements (requirement.rs:169-181)

**Rust:**
```rust
pub fn merge_bundle_requirements(
    &self,
    a: LiveBundleIndex,
    b: LiveBundleIndex,
) -> Result<Requirement, RequirementConflict>
```

**Zig Port Status:** ✅ `MergeContext.mergeBundleRequirements()`

### 7. merge_bundle_properties (merge.rs:24-40)

**Rust:**
```rust
fn merge_bundle_properties(&mut self, from: LiveBundleIndex, to: LiveBundleIndex) {
    // Transfer: cached_fixed, cached_fixed_def, cached_stack, limit
}
```

**Zig Port Status:** ✅ `MergeContext.mergeBundleProperties()`

### 8. merge_bundles (merge.rs:42-257) - **CRITICAL**

**Rust:**
```rust
pub fn merge_bundles(&mut self, from: LiveBundleIndex, to: LiveBundleIndex) -> bool {
    // 1. Check from == to (trivial merge)
    // 2. Check RegClass match
    // 3. Check neither bundle is pinned
    // 4. Check for range overlap (with fixed_def adjustment)
    // 5. Check requirements compatibility
    // 6. Perform merge:
    //    a. Empty from -> trivial
    //    b. Empty to -> move list
    //    c. Single item from -> binary search insert
    //    d. Multiple items -> concat and sort
    // 7. Update spillset range
    // 8. Transfer properties
}
```

**Zig Port Status:** ✅ `MergeContext.mergeBundles()`

| Step | Status | Notes |
|------|--------|-------|
| Trivial merge (from == to) | ✅ | Return true |
| RegClass check | ✅ | From spillset |
| Pinned check | ✅ | !allocation.isNone() |
| Range overlap check | ✅ | With fixed_def adjustment via adjust_range_start |
| Requirements check | ✅ | Via mergeBundleRequirements |
| Empty from merge | ✅ | Return true |
| Empty to merge | ✅ | Move list, update bundle pointers |
| Single item insert | ✅ | Binary search + insert |
| Multi-item merge | ✅ | Concat + sort |
| Spillset range update | ✅ | join() ranges |
| Property transfer | ✅ | mergeBundleProperties() |

### 9. merge_vreg_bundles (merge.rs:259-387)

**Rust:**
```rust
pub fn merge_vreg_bundles(&mut self) {
    // 1. Create bundle for each vreg with ranges
    // 2. Compute fixed/fixed_def/stack/limit from uses
    // 3. Create spillset for each bundle
    // 4. Merge reuse-constraint operands
    // 5. Merge blockparams with inputs
}
```

**Zig Port Status:** ✅ `MergeContext.mergeVregBundles()`

| Step | Status | Notes |
|------|--------|-------|
| Create vreg bundles | ✅ | Clone ranges, set bundle ptr |
| Compute cached props | ✅ | Scan uses for fixed/stack/limit |
| Create spillsets | ✅ | With class, range |
| Merge reuse operands | ✅ | Find Reuse constraints, call mergeBundles |
| Merge blockparams | ✅ | From blockparam_outs |

### 10. compute_bundle_prio (merge.rs:389-398)

**Rust:**
```rust
pub fn compute_bundle_prio(&self, bundle: LiveBundleIndex) -> u32 {
    // Sum of range.len() for all ranges
}
```

**Zig Port Status:** ✅ `MergeContext.computeBundlePrio()`

### 11. compute_bundle_limit (merge.rs:400-424)

**Rust:**
```rust
pub fn compute_bundle_limit(&self, bundle: LiveBundleIndex) -> Option<u8> {
    // Find minimum Limit constraint across all uses
}
```

**Zig Port Status:** ✅ `MergeContext.computeBundleLimit()`

### 12. queue_bundles (merge.rs:426-439)

**Rust:**
```rust
pub fn queue_bundles(&mut self) {
    // 1. For each non-empty bundle:
    //    a. recompute_bundle_properties
    //    b. Insert into allocation_queue with prio
    // 2. Update stats
}
```

**Zig Port Status:** ✅ `MergeContext.queueBundles()` - Uses PrioQueue

### 13. recompute_bundle_properties (process.rs:265-365)

**Rust:**
```rust
pub fn recompute_bundle_properties(&mut self, bundle: LiveBundleIndex) {
    // 1. Compute prio and limit
    // 2. Determine if minimal bundle
    // 3. Compute spill_weight
    // 4. Set cached properties
}
```

**Zig Port Status:** ✅ `MergeContext.recomputeBundleProperties()` with `minimalRangeForUse()`

---

## Dependencies

### Required from ion_data.zig

| Type | Status |
|------|--------|
| LiveBundleIndex | ✅ |
| LiveRangeIndex | ✅ |
| LiveBundle | ✅ |
| LiveRange | ✅ |
| SpillSet | ✅ |
| SpillSlotIndex | ✅ |
| VRegIndex | ✅ |
| CodeRange | ✅ |
| PrioQueue | ✅ |
| BlockparamOut | ✅ |

### Required from operand.zig

| Type | Status |
|------|--------|
| Operand | ✅ |
| OperandConstraint | ✅ |
| OperandKind | ✅ |
| ProgPoint | ✅ |
| PReg | ✅ |

### Required from liveness.zig

| Type | Status |
|------|--------|
| SpillWeight (ion_data) | ✅ |

---

## Key Algorithms

### Bundle Merge Algorithm

```
merge_bundles(from, to):
  1. If from == to: return true (trivial)
  2. If RegClass(from) != RegClass(to): return false
  3. If either is pinned (has allocation): return false

  4. Check overlap with fixed_def adjustment:
     For each range pair:
       adjust_start(r) = if cached_fixed_def: Before(r.from.inst) else r.from
       If adjusted ranges overlap: return false

  5. If either has constraints (fixed/stack/limit):
     If merge_bundle_requirements fails: return false

  6. Merge:
     a. If from.ranges empty: return true
     b. If to.ranges empty: move from's list to to
     c. If from.ranges.len == 1: binary search insert
     d. Else: concat + sort by range.from

  7. Update spillset range via join
  8. Transfer properties (fixed, fixed_def, stack, limit)

  return true
```

### Requirement Merge Rules

```
merge(a, b):
  Any + X = X
  Register + Register = Register
  Stack + Stack = Stack
  Limit(a) + Limit(b) = Limit(min(a, b))
  FixedReg(a) + FixedReg(b) = FixedReg(a) if a == b, else CONFLICT
  FixedStack(a) + FixedStack(b) = FixedStack(a) if a == b, else CONFLICT
  Limit(a) + Register = Limit(a)
  Limit(a) + FixedReg(b) = FixedReg(b) if a > b.hw_enc, else CONFLICT
  Register + FixedReg(p) = FixedReg(p)
  Stack + FixedStack(p) = FixedStack(p)
  Everything else = CONFLICT
```

---

## Test Coverage

| Test | Status | Description |
|------|--------|-------------|
| Requirement merge - Any | ✅ | Any + X = X |
| Requirement merge - Same kinds | ✅ | Register + Register, Stack + Stack |
| Requirement merge - FixedReg same | ✅ | Same PReg |
| Requirement merge - FixedReg different | ✅ | Conflict |
| Requirement merge - Register with FixedReg | ✅ | Constrain to fixed |
| Requirement merge - Limit with FixedReg | ✅ | Check hw_enc |
| Requirement merge - Stack with Register | ✅ | Conflict |
| Requirement is_stack/is_reg | ✅ | Classification |
| RequirementConflictAt methods | ✅ | Split point, trim edges |
| Spill weight constants | ✅ | Ordering |

Integration tests (require MergeContext with data):

| Test | Status | Notes |
|------|--------|-------|
| merge_bundles trivial | ⏳ | Needs populated context |
| merge_bundles class mismatch | ⏳ | Needs spillsets |
| merge_vreg_bundles | ⏳ | Needs full setup |

---

## Implementation Plan - COMPLETED

### Phase 1: Requirement Types ✅
- [x] RequirementConflict error type
- [x] RequirementConflictAt tagged union with methods
- [x] Requirement enum with merge logic

### Phase 2: Requirement Functions ✅
- [x] requirementFromOperand
- [x] computeRequirement
- [x] mergeBundleRequirements

### Phase 3: Bundle Merge Core ✅
- [x] mergeBundleProperties
- [x] mergeBundles (full algorithm with all steps)

### Phase 4: Bundle Creation ✅
- [x] mergeVregBundles
- [x] computeBundlePrio
- [x] computeBundleLimit

### Phase 5: Queue Integration ✅
- [x] minimalRangeForUse
- [x] recomputeBundleProperties
- [x] queueBundles

### Phase 6: Tests ✅
- [x] 10 unit tests for Requirement and constants

---

## Notes

1. **Annotations**: The Rust code has `annotations_enabled` checks for debug output. We'll skip these in the initial port but can add later if needed.

2. **Bump Allocator**: Rust uses a bump allocator (`self.ctx.bump()`) for LiveRangeList. In Zig we use standard allocator.

3. **Complexity Limit**: `merge_bundles` has a range_count > 200 check to limit merge complexity.

4. **Binary Search Optimization**: For single-item merges, regalloc2 uses binary search + insert rather than concat + sort (added in response to rustc 1.81 sorting changes).
