# List(T) Current State

**Date:** February 2026
**Status:** Functional prototype, NOT production-ready

---

## What Exists

List(T) is a generic dynamic array implemented in Cot userspace (not compiler-provided).
It lives in `test/native/e2e_all.cot` as both free functions and an impl block.

### Struct Layout

```cot
struct List(T) {
    items: i64,      // raw pointer to backing array (NOT *T, just a raw integer)
    count: i64,      // current number of elements
    capacity: i64,   // allocated slots
}
```

### Current API (5 methods via impl block)

| Method | Signature | Bounds Check | Notes |
|--------|-----------|:---:|-------|
| `ensureCapacity` | `(self, needed: i64) void` | No | Simple 2x doubling, starts at 8 |
| `append` | `(self, value: T) void` | No | Calls ensureCapacity then stores |
| `iget` | `(self, index: i64) T` | **No** | Raw pointer dereference |
| `iset` | `(self, index: i64, value: T) void` | **No** | Raw pointer dereference |
| `ipop` | `(self) T` | **No** | Decrements count, reads last |

### Current API (5 free functions)

| Function | Signature | Notes |
|----------|-----------|-------|
| `List_ensureCapacity(T)` | `(self: *List(T), needed: i64) void` | Same as impl |
| `List_append(T)` | `(self: *List(T), value: T) void` | Same as impl |
| `List_get(T)` | `(self: *List(T), index: i64) T` | No bounds check |
| `List_set(T)` | `(self: *List(T), index: i64, value: T) void` | No bounds check |
| `List_pop(T)` | `(self: *List(T)) T` | No bounds check |

### Tests

- 5 Wasm E2E tests (free function pattern)
- 5 Wasm E2E tests (impl pattern)
- 5 native E2E tests (free function pattern)
- 5 native E2E tests (impl pattern)
- All 20 tests pass

---

## What's Wrong

### 1. No Bounds Checking

`get(index)` will happily read garbage memory if `index >= count` or `index < 0`.
`pop()` will underflow count to -1 and read garbage. This is a safety bug.

**Fix requires:** `@assert(cond)` which already exists. Straightforward to add.

### 2. Naive Growth Algorithm

Current: always doubles capacity (`new_cap = capacity * 2`).
- Cap 0 -> 8 -> 16 -> 32 -> 64 -> 128 -> 256 -> 512 -> 1024 ...
- For 1000 elements: wastes up to 1024 slots (2x overshoot)
- For 1M elements: wastes up to 2M slots

Go uses `nextslicecap()` which transitions from 2x to ~1.25x growth at 256 elements.
This is a well-known optimization that every production list implementation uses.

**Fix requires:** Nothing new. Can implement `nextListCap()` as a plain function today.

### 3. No Cleanup (deinit)

No way to free the backing array. Memory leaks on every List that goes out of scope.

**Fix requires:** `@dealloc(self.items)` which already exists. Straightforward.

### 4. No Insert/Remove Operations

Can't insert at arbitrary index. Can't remove from arbitrary index.
This means List(T) can't be used as a stack, queue, or any data structure requiring mutation.

**Fix requires:**
- `insert(index, value)`: shift elements right via while loop with pointer arithmetic
- `orderedRemove(index)`: shift elements left
- `swapRemove(index)`: swap with last element (O(1))

These work today with while loops. `@memcpy` would make them cleaner but isn't required.

### 5. No Bulk Operations

Can't clone a list, reverse it, or append another list's contents.

**Fix requires:**
- `clone()`: allocate new backing array, copy elements via while loop. Works today.
- `reverse()`: swap elements from ends toward middle. Works today.
- `appendSlice(items: []T)`: **BLOCKED** — requires slice parameters to work.

### 6. No Capacity Management

No `ensureTotalCapacity`, `ensureUnusedCapacity`, `appendAssumeCapacity`, `clearRetainingCapacity`, `clearAndFree`.

**Fix requires:** Nothing new. All implementable today.

### 7. `items` is `i64`, not `*T`

The backing array pointer is stored as a raw `i64` integer. All access goes through
`@intToPtr(*T, self.items + index * @sizeOf(T))`. This works but is ugly and error-prone.

**Root cause:** Cot doesn't support pointer arithmetic on typed pointers yet. This is a
deeper language issue, not a List-specific fix.

---

## What Blocks Production Quality

| Blocker | Severity | Feature Required | Status |
|---------|----------|-----------------|--------|
| Can't pass List contents to other functions as `[]T` | **HIGH** | Slice parameters | Type exists, call-site decomposition missing |
| Can't do `appendSlice`, `insertSlice` | **HIGH** | Slice parameters | Same as above |
| Element shifting is verbose while loops | **LOW** | `@memcpy` builtin | Works without it, just ugly |
| No abort-on-bug (trap instruction) | **LOW** | `@trap` builtin | `@assert` with exit(1) works |
| Can't implement `sort`, `contains`, `indexOf` | **MEDIUM** | Traits/interfaces | Need comparison protocol |
| Can't implement `map`, `filter`, `reduce` | **MEDIUM** | Closures as params to generic fns | May already work, untested |

### Dependency Order

```
1. @memcpy       (independent, small)
2. @trap          (independent, small)
3. Slice params   (independent, medium — enables appendSlice, passing lists around)
4. Traits         (depends on nothing, but large — enables sort, contains, generic algorithms)
5. List(T) v2     (depends on 1-4 being done)
```

---

## Parity Comparison

### vs Go's `[]T` + `slices` package

| Feature | Go | Cot List(T) |
|---------|:--:|:--:|
| Append | `append(s, v)` | `list.append(v)` |
| Index | `s[i]` | `list.get(i)` |
| Bounds check | Automatic panic | **Missing** |
| Growth algorithm | nextslicecap (2x then 1.25x) | Simple 2x |
| Len/Cap | `len(s)`, `cap(s)` | `list.count`, `list.capacity` |
| Insert | `slices.Insert(s, i, v)` | **Missing** |
| Delete | `slices.Delete(s, i, j)` | **Missing** |
| Clone | `slices.Clone(s)` | **Missing** |
| Reverse | `slices.Reverse(s)` | **Missing** |
| Sort | `slices.Sort(s)` | **Missing** (needs traits) |
| Contains | `slices.Contains(s, v)` | **Missing** (needs traits) |
| Compact | `slices.Compact(s)` | **Missing** (needs traits) |

**Estimated parity: ~15%**

### vs Zig's `std.ArrayList(T)`

| Feature | Zig | Cot List(T) |
|---------|:--:|:--:|
| append | `list.append(v)` | `list.append(v)` |
| appendAssumeCapacity | `list.appendAssumeCapacity(v)` | **Missing** |
| orderedRemove | `list.orderedRemove(i)` | **Missing** |
| swapRemove | `list.swapRemove(i)` | **Missing** |
| insert | `list.insert(i, v)` | **Missing** |
| pop | `list.pop()` | `list.ipop()` |
| getLast | `list.getLast()` | **Missing** |
| clearRetainingCapacity | `list.clearRetainingCapacity()` | **Missing** |
| clearAndFree | `list.clearAndFree()` | **Missing** |
| ensureTotalCapacity | `list.ensureTotalCapacity(n)` | **Missing** |
| ensureUnusedCapacity | `list.ensureUnusedCapacity(n)` | **Missing** |
| appendSlice | `list.appendSlice(items)` | **Missing** (needs []T params) |
| deinit | `list.deinit()` | **Missing** |
| clone | `list.clone()` | **Missing** |
| resize | `list.resize(n)` | **Missing** |

**Estimated parity: ~15%**

---

## Path to Production

1. Implement `@memcpy`, `@trap` (small, independent)
2. Implement slice parameter passing (medium, unblocks appendSlice)
3. Implement traits (large, unblocks sort/contains)
4. Rewrite List(T) with all 15+ methods, bounds checking, Go growth algorithm, cleanup
5. Add comprehensive E2E tests (13+ test functions covering every operation)

See:
- `docs/MEMCPY_BUILTIN.md` — @memcpy design
- `docs/TRAP_BUILTIN.md` — @trap design
- `docs/SLICE_PARAMS.md` — Slice parameter passing design
- `docs/TRAITS.md` — Traits/interfaces design
