# Audit: ssa/liveness.zig

## Status: VERIFIED CORRECT

| Metric | Value |
|--------|-------|
| 0.2 lines | 947 |
| 0.3 lines | 947 |
| Reduction | 0% |
| Tests | 11/11 pass |

---

## Function-by-Function Verification

### Distance Constants

| Constant | 0.2 | 0.3 | Verdict |
|----------|-----|-----|---------|
| likely_distance | 1 | 1 | IDENTICAL |
| normal_distance | 10 | 10 | IDENTICAL |
| unlikely_distance | 100 | 100 | IDENTICAL |
| unknown_distance | -1 | -1 | IDENTICAL |

### LiveInfo Struct

| Component | 0.2 | 0.3 | Verdict |
|-----------|-----|-----|---------|
| Fields | id: ID, dist: i32, pos: Pos | Same | IDENTICAL |
| format() | Print v{id}@{dist} | Same | IDENTICAL |

### LiveMap Struct

| Method | 0.2 | 0.3 | Verdict |
|--------|-----|-----|---------|
| init() | Return empty entries/sparse | Same | IDENTICAL |
| deinit() | Free entries and sparse | Same | IDENTICAL |
| clear() | clearRetainingCapacity | Same | IDENTICAL |
| set() | Update if closer distance | Same | IDENTICAL |
| setForce() | Always overwrite | Same | IDENTICAL |
| get() | Return dist or null | Same | IDENTICAL |
| getInfo() | Return LiveInfo or null | Same | IDENTICAL |
| contains() | Check sparse.contains | Same | IDENTICAL |
| remove() | Swap-remove pattern | Same | IDENTICAL |
| size() | Return entries.items.len | Same | IDENTICAL |
| items() | Return entries.items | Same | IDENTICAL |
| addDistanceToAll() | Add delta, skip unknown | Same | IDENTICAL |

### BlockLiveness Struct

| Method | 0.2 | 0.3 | Verdict |
|--------|-----|-----|---------|
| Fields | live_out, live_in, next_call, allocator | Same | IDENTICAL |
| init() | Return with empty slices | Same | IDENTICAL |
| deinit() | Free all slices | Same | IDENTICAL |
| computeNextCall() | Backward scan for calls | Same | IDENTICAL |
| updateLiveOut() | Dupe from LiveMap | Same | IDENTICAL |

### LivenessResult Struct

| Method | 0.2 | 0.3 | Verdict |
|--------|-----|-----|---------|
| init() | Alloc blocks array | Same | IDENTICAL |
| deinit() | Free all BlockLiveness | Same | IDENTICAL |
| getLiveOut() | Return live_out slice | Same | IDENTICAL |
| getNextCall() | Return next_call slice | Same | IDENTICAL |
| hasCallAtOrAfter() | Check != maxInt | Same | IDENTICAL |
| getNextCallIdx() | Return index or null | Same | IDENTICAL |

### computeLiveness (Main Function)

| Line | 0.2 | 0.3 | Verdict |
|------|-----|-----|---------|
| 362 | `f.blocks.items.len` | `f.bid.next_id` | **FIXED** |
| Rest | Same algorithm | Same | IDENTICAL |

**Critical Fix:** Uses `f.bid.next_id` instead of `f.blocks.items.len` for proper array sizing. Block IDs are 1-based, so array size must equal max ID, not count.

### Helper Functions

| Function | 0.2 | 0.3 | Verdict |
|----------|-----|-----|---------|
| branchDistance() | Check succs[0]/[1], return likely/unlikely/normal | Same | IDENTICAL |
| processSuccessorPhis() | Add phi args to live set | Same | IDENTICAL |
| needsRegister() | Conservative: return true for most ops | Same | IDENTICAL |
| isCall() | Return op.info().call | Same | IDENTICAL |
| computePostorder() | DFS from entry | Same | IDENTICAL |
| postorderDFS() | Recursive DFS helper | Same | IDENTICAL |

### Tests (11/11)

| Test | 0.2 | 0.3 | Verdict |
|------|-----|-----|---------|
| LiveMap basic operations | set/get/remove/clear | Same | IDENTICAL |
| LiveMap addDistanceToAll | Add delta, skip unknown | Same | IDENTICAL |
| distance constants match Go | Verify values | Same | IDENTICAL |
| branchDistance for two-way branch | Compile check | Same | IDENTICAL |
| needsRegister classification | Check ops | Same | IDENTICAL |
| LivenessResult initialization | Alloc and check | Same | IDENTICAL |
| computeLiveness on simple function | Single block | Same | IDENTICAL |
| computeLiveness straight-line code | Const + add | Same | IDENTICAL |
| computeLiveness with loop | Header/body/exit | Same | IDENTICAL |
| nextCall tracking | Call indices | Same | IDENTICAL |
| nextCall no calls | All maxInt | Same | IDENTICAL |

---

## Why No Line Reduction

1. **Algorithm complexity** - Liveness analysis is a complex dataflow algorithm
2. **Documentation preserved** - Go references and explanations aid maintainability
3. **Extensive tests** - 11 tests verify algorithm correctness
4. **Fix priority** - The ID indexing fix was the critical change

## What Did NOT Change

- Distance constants (4 values)
- LiveInfo struct (3 fields + format)
- LiveMap struct (12 methods)
- BlockLiveness struct (4 fields + 4 methods)
- LivenessResult struct (6 methods)
- computeLiveness algorithm (except fix)
- All 6 helper functions
- All 11 tests

---

## Verification

```
$ zig build test
248/248 tests passed
```

**VERIFIED: Logic 100% identical except f.bid.next_id fix for proper array sizing. 0% reduction - documentation preserved for complex algorithm.**
