# Audit: ssa/stackalloc.zig

## Status: VERIFIED CORRECT

| Metric | Value |
|--------|-------|
| 0.2 lines | 494 |
| 0.3 lines | 364 |
| Reduction | 26% |
| Tests | 5/5 pass (vs 1 in 0.2) |

---

## Function-by-Function Verification

### Constants

| Constant | 0.2 | 0.3 | Verdict |
|----------|-----|-----|---------|
| FRAME_HEADER_SIZE | 16 | 16 | IDENTICAL |
| SPILL_SLOT_SIZE | 8 | 8 | IDENTICAL |

### StackAllocResult Struct

| Field | 0.2 | 0.3 | Verdict |
|-------|-----|-----|---------|
| frame_size | u32 | Same | IDENTICAL |
| num_spill_slots | u32 | Same | IDENTICAL |
| locals_size | u32 | Same | IDENTICAL |
| num_reused | u32 | Same | IDENTICAL |

### StackValState Struct

| Component | 0.2 | 0.3 | Verdict |
|-----------|-----|-----|---------|
| UseBlock | Nested | Hoisted out | REORGANIZED |
| Fields | 4 fields | Same | IDENTICAL |
| addUseBlock() | 10 lines | 6 lines | IDENTICAL |
| deinit() | 4 lines | 3 lines | IDENTICAL |

### StackAllocState Methods

| Method | 0.2 Lines | 0.3 Lines | Verdict |
|--------|-----------|-----------|---------|
| init() | 12 | 4 | IDENTICAL |
| deinit() | 20 | 11 | IDENTICAL |
| initValues() | 20 | 10 | IDENTICAL |
| computeLive() | 78 | 50 | IDENTICAL |
| pushLive() | 9 | 5 | IDENTICAL |
| buildInterference() | 47 | 24 | IDENTICAL |
| addInterference() | 26 | 4 + 8 | **DECOMPOSED** |
| addInterfereOne() | N/A | 8 | **NEW HELPER** |

### Main stackalloc Function

| Section | 0.2 Lines | 0.3 Lines | Verdict |
|---------|-----------|-----------|---------|
| State init | 8 | 6 | IDENTICAL |
| Locals allocation | 18 | 10 | IDENTICAL |
| Spill slot allocation | 65 | 45 | IDENTICAL |
| BUG-023 fix | Present | Present | IDENTICAL |
| Frame alignment | Present | Present | IDENTICAL |

### Tests (5/5 vs 1/1)

| Test | 0.2 | 0.3 | Verdict |
|------|-----|-----|---------|
| empty function | Yes | Yes | IDENTICAL |
| with locals | No | **NEW** | IMPROVED |
| UseBlock tracking | No | **NEW** | IMPROVED |
| State init/deinit | No | **NEW** | IMPROVED |
| frame alignment | No | **NEW** | IMPROVED |

---

## Algorithm Verification (preserved)

1. **Phase 1 - initValues**: Mark store_reg with uses > 0 as needing slot
2. **Phase 2 - computeLive**: Seed from spillLive, record uses, backward propagation
3. **Phase 3 - buildInterference**: Process blocks backward, track live set
4. **Phase 4 - Locals allocation**: Start at FRAME_HEADER_SIZE (16), align to 8
5. **Phase 5 - Spill slots**: Reuse non-interfering slots (except store_reg - BUG-023)
6. **Frame alignment**: Round to 16 bytes

### BUG-023 Fix (preserved)

```zig
// CONSERVATIVE FIX: Never reuse slots for store_reg values
var found_slot: ?usize = null;
if (v.op != .store_reg) {
    for (slots.items, 0..) |slot, i| {
        if (slot.type_idx == v.type_idx and !used.items[i]) {
            found_slot = i;
            // ...
        }
    }
}
```

---

## Key Changes

### 1. addInterference Decomposed
- 0.2: 26 lines inline for bidirectional edges
- 0.3: 4 lines + addInterfereOne helper (8 lines)
- Same logic, cleaner code

### 2. UseBlock Hoisted
- 0.2: Nested inside StackValState
- 0.3: Top-level struct (cleaner)

### 3. Field Default Values
- 0.3: Uses `= .{}` defaults instead of explicit init

### 4. More Tests
- 0.3 adds 4 new tests for better coverage

---

## Real Improvements

1. **26% line reduction** - Compact style, less verbose comments
2. **4x more tests** - Better coverage including locals, alignment
3. **addInterfereOne helper** - Cleaner bidirectional edge insertion
4. **UseBlock hoisted** - Cleaner struct organization
5. **Field defaults** - Compact initialization

## What Did NOT Change

- FRAME_HEADER_SIZE (16) and SPILL_SLOT_SIZE (8)
- StackAllocResult struct (4 fields)
- Stack allocation algorithm (5 phases)
- BUG-023 fix (no slot reuse for store_reg)
- Frame alignment (16-byte)
- spillLive integration from regalloc

---

## Verification

```
$ zig build test
248/248 tests passed
```

**VERIFIED: Logic 100% identical. BUG-023 fix preserved. 4x more tests. 26% reduction.**
