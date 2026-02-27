# ARC Implementation Audit: Cot vs Swift

**Date**: February 18, 2026
**Status**: ALL 4 critical gaps FIXED + Phase 5 (Collection Element ARC) COMPLETE (Feb 27, 2026)

## Reference Files

| Cot File | Swift Reference | Purpose |
|----------|----------------|---------|
| `compiler/codegen/native/arc_native.zig` | `references/swift/stdlib/public/runtime/HeapObject.cpp` | ARC runtime (retain/release/dealloc) — native only. Wasm uses WasmGC. |
| `compiler/frontend/arc_insertion.zig` | `references/swift/lib/SILGen/Cleanup.h` | Cleanup stack, managed values |
| `compiler/frontend/lower.zig` | `references/swift/lib/SILGen/SILGenExpr.cpp` | ARC insertion during lowering |

---

## Phase 5: Collection Element ARC (Feb 27, 2026) — COMPLETE

**Changes**:

### stdlib/list.cot — @arcRetain on all insertion paths
- `append()`: retain before store
- `set()`: Swift SILGen pattern — load old, retain new, store new, release old
- `insert()`: retain before store
- `appendSlice()`, `insertSlice()`: per-element retain loop after memcpy
- `appendNTimes()`: retain before each store
- `replaceRange()`: release replaced elements, retain new elements
- `clone()`: per-element retain loop after memcpy
- `free()`, `clear()`, `deleteRange()`, `resize()`, `shrinkAndFree()`: release loops
- `compact()`, `removeIf()`: release removed elements
- `pop()`, `orderedRemove()`, `swapRemove()`: ownership transfer (no release)

### stdlib/map.cot — @arcRetain on insertion
- `set()` new entry: retain key + value
- `set()` overwrite: Swift SILGen load-old/retain-new/store/release-old
- `rehash()`: entries MOVED (no retain/release), matching Swift Dictionary._rehash
- `delete()`: release key + value
- `remove()`: release key, transfer value ownership
- `free()`, `clear()`: release all keys + values

### compiler/frontend/lower.zig — Index assignment guard
- `lowerIndexAssign()`: load old → retain new → store → release old (Swift SILGen pattern)
- `deref assignment`: managed pointer check prevents Phase 4 ARC on @intToPtr pointers

### compiler/frontend/types.zig — Type deduplication
- All compound type constructors (makePointer, makeOptional, makeErrorUnion, etc.) now deduplicate
- Prevents cache key mismatch for generic structs with pointer type parameters

### compiler/frontend/lower.zig — weak_locals leak fix
- `weak_locals` hash map now cleared at start of every function/test/generic body
- Prevents local indices from one function being incorrectly treated as weak vars in the next
- Fixed: "weak var cycle breaking" SIGSEGV
- Fixed: `import "std/list"` + `weak var` function index displacement

### Tests: test/e2e/arc.cot — 29 tests
All in one file (imports + weak + collections coexist after weak_locals fix).

---

## Gaps 1-4 (Feb 18, 2026) — ALL FIXED

### Gap 1: Weak References — FIXED (Phase 3)
Side table allocation, `weak var` keyword, weak_form_reference/weak_retain/weak_release/weak_load_strong.

### Gap 2: Collection Element ARC — FIXED (Phase 5)
@arcRetain/@arcRelease in List and Map methods.

### Gap 3: Narrow couldBeARC — FIXED (Phase 1)
`couldBeARC()` widened, managed pointer flag, type deduplication.

### Gap 4: Ownership Heuristic — FIXED (Phase 4)
Return ownership, field init retain, method field assignment, auto-generated deinit.

---

## What Cot Does Well (keep these)

- **Cleanup stack LIFO ordering** — correct, matches Swift
- **ManagedValue/forward pattern** — faithful Swift port, ownership transfer on return works
- **Error path handling** — errdefer + cleanup on error paths, well-implemented
- **Destructor dispatch** — metadata + table-based call_indirect, functional
- **Immortal refcount** — prevents wasteful ops on string constants
- **Null checks** — retain/release safely handle null pointers
- **Scope destroy** — auto-calls deinit for stack-allocated structs
- **Side tables** — Swift-faithful weak reference implementation
- **Type deduplication** — Go/Zig-style type interning for compound types

---

## Verification

After each fix:
1. `zig build test` — compiler internals pass
2. `cot test test/e2e/arc.cot` — 29 ARC tests pass
3. `cot test test/e2e/features.cot` — 341 features pass (native)
4. `./test/run_all.sh` — 67/67 test files pass
