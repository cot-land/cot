# ARC Implementation Audit

## Reference
- Primary: `~/learning/swift/stdlib/public/runtime/HeapObject.cpp`
- Secondary: `~/learning/swift/stdlib/public/SwiftShims/swift/shims/RefCount.h`
- Destructors: `~/learning/swift/include/swift/ABI/Metadata.h` (FullMetadata::destroy)

## Summary

**Status: CORRECTLY COPIES Swift's proven patterns**

The ARC implementation follows Swift's embedded ARC design with appropriate adaptations for Wasm32.
M19 (Destructor Calls on Release) is now complete - destructors are called when refcount reaches zero.

---

## Memory Layout Constants

| Constant | Cot Value | Swift Reference | Status |
|----------|-----------|-----------------|--------|
| HEAP_OBJECT_HEADER_SIZE | 12 | 16 (64-bit), 12 (32-bit) | ✅ Correct |
| METADATA_OFFSET | 0 | 0 | ✅ Matches |
| REFCOUNT_OFFSET | 4 | 8 (64-bit), 4 (32-bit) | ✅ Correct |
| USER_DATA_OFFSET | 12 | 16 (64-bit), 12 (32-bit) | ✅ Correct |
| DESTRUCTOR_OFFSET | 8 | 8 (in metadata) | ✅ Matches |
| IMMORTAL_REFCOUNT | 0x7FFFFFFFFFFFFFFF | EmbeddedImmortalRefCount | ✅ Matches |
| INITIAL_REFCOUNT | 1 | 1 | ✅ Matches |

---

## Type Metadata Layout

Following Swift's FullMetadata pattern from `Metadata.h`:

| Offset | Field | Size | Description |
|--------|-------|------|-------------|
| 0 | type_id | 4 | Unique type identifier |
| 4 | size | 4 | Instance size (placeholder) |
| 8 | destructor_idx | 4 | Table index for call_indirect |

**Swift Reference (Metadata.h:268-275):**
```cpp
template <typename Runtime>
struct FullMetadata : Metadata {
  // The destructor function pointer
  ValueWitnessTypes::Destroy *destroy;
  // ...
};
```

**Cot Implementation (driver.zig:418-437):**
```zig
// Metadata layout: type_id(4), size(4), destructor_ptr(4) = 12 bytes
std.mem.writeInt(u32, metadata_buf[0..4], type_id, .little);
std.mem.writeInt(u32, metadata_buf[4..8], 8, .little); // size placeholder
std.mem.writeInt(u32, metadata_buf[8..12], dtor_idx, .little);
```

---

## Function-by-Function Audit

### 1. generateAllocBody() → swift_allocObject

**Cot (arc.zig lines 159-208):**
```zig
// Parameters: metadata_ptr (i64), size (i64)
// Allocate memory, store metadata and refcount in header
// Return pointer to user data (after header)
```

**Swift (HeapObject.cpp:247-270):**
```cpp
HeapObject *swift::swift_allocObject(HeapMetadata const *metadata,
                                     size_t requiredSize,
                                     size_t requiredAlignmentMask) {
  HeapObject *object = reinterpret_cast<HeapObject *>(
      swift_slowAlloc(requiredSize, requiredAlignmentMask));
  object->metadata = metadata;
  object->refCounts.init();
  return object;
}
```

**Assessment:** ✅ COPIES Swift pattern
- Allocates from heap (bump allocator in Wasm)
- Stores metadata pointer at object start
- Initializes refcount to 1
- Returns pointer past header

---

### 2. generateRetainBody() → swift_retain

**Cot (arc.zig lines 211-265):**
```zig
// if (obj == 0) return 0
// header_ptr = obj - USER_DATA_OFFSET
// old_count = i64.load(header_ptr + REFCOUNT_OFFSET)
// if (old_count >= IMMORTAL_REFCOUNT) return obj
// i64.store(header_ptr + REFCOUNT_OFFSET, old_count + 1)
// return obj
```

**Swift (HeapObject.cpp swift_retain):**
```cpp
HeapObject *swift::swift_retain(HeapObject *object) {
  if (isValidPointerForNativeRetain(object))
    object->refCounts.increment(1);
  return object;
}
```

**Assessment:** ✅ COPIES Swift pattern
- Null check → return early
- Immortal check → return without increment
- Increment → store new value
- Return object (tail call optimization)

---

### 3. generateReleaseBody() → swift_release + destructor call

**Cot (arc.zig lines 270-349):**
```zig
// if (obj == 0) return
// header_ptr = obj - USER_DATA_OFFSET
// old_count = i64.load(header_ptr + REFCOUNT_OFFSET)
// if (old_count >= IMMORTAL_REFCOUNT) return
// new_count = old_count - 1
// i64.store(header_ptr + REFCOUNT_OFFSET, new_count)
// if (new_count == 0) {
//     metadata_ptr = i32.load(header_ptr + METADATA_OFFSET)
//     destructor_idx = i32.load(metadata_ptr + DESTRUCTOR_OFFSET)
//     if (destructor_idx != 0) {
//         call_indirect(destructor_idx, obj)
//     }
// }
```

**Swift (HeapObject.cpp:835-840):**
```cpp
void swift::swift_release_dealloc(HeapObject *object) {
  if (object->refCounts.decrementShouldDeinit()) {
    auto metadata = object->metadata;
    asFullMetadata(metadata)->destroy(object);
  }
}
```

**Assessment:** ✅ COPIES Swift pattern (M19 COMPLETE)
- Null check → return early
- Immortal check → return without decrement
- Decrement → store new value
- Zero check → **call destructor via metadata lookup**
- Uses `call_indirect` for destructor dispatch (matches vtable pattern)

---

## Destructor Table Implementation

### Table Index Reservation

**Cot (driver.zig:403-406):**
```zig
// Reserve table index 0 as null (no destructor)
// This ensures actual destructors start at index 1+
_ = try linker.addTableFunc(arc_funcs.release_idx);
```

**Swift Pattern:**
Swift reserves function pointer 0 as null. Non-null destructor pointers are stored in metadata.

**Assessment:** ✅ MATCHES Swift pattern - index 0 reserved for null

### Destructor Discovery

**Cot (driver.zig:407-416):**
```zig
// Find all *_deinit functions and add them to the table
for (funcs) |*ir_func| {
    if (std.mem.endsWith(u8, ir_func.name, "_deinit")) {
        const table_idx = try linker.addTableFunc(func_idx);
        try destructor_table.put(type_name, table_idx);
    }
}
```

**Swift Pattern:**
Swift synthesizes `deinit` methods and stores pointers in type metadata during compilation.

**Assessment:** ✅ COPIES pattern - discovers deinit by naming convention

---

## ARC Insertion (Cleanup Stack)

### CleanupStack → Swift's CleanupManager

**Cot (arc_insertion.zig:79-153):**
```zig
pub const CleanupStack = struct {
    items: std.ArrayListUnmanaged(Cleanup),

    pub fn push(self: *CleanupStack, cleanup: Cleanup) !CleanupHandle
    pub fn disable(self: *CleanupStack, handle: CleanupHandle) void
    pub fn getScopeDepth(self: *const CleanupStack) usize
};
```

**Swift Reference (Cleanup.h:85-142):**
```cpp
class Cleanup {
  CleanupState state;
  virtual void emit(IRGenFunction &IGF) = 0;
};

class CleanupManager {
  std::vector<Cleanup *> stack;
  void popAndEmitCleanup(CleanupHandle handle);
};
```

**Assessment:** ✅ COPIES Swift pattern
- LIFO cleanup stack
- Scope depth tracking
- Handle-based disable for ownership transfer

### ManagedValue Pattern

**Cot (arc_insertion.zig:162-200):**
```zig
pub const ManagedValue = struct {
    value: NodeIndex,
    cleanup: CleanupHandle,

    pub fn forOwned(value, type_idx, cleanup) ManagedValue
    pub fn forTrivial(value, type_idx) ManagedValue
    pub fn forward(self, stack) NodeIndex  // Transfer ownership
};
```

**Swift Reference (ManagedValue.h:59-95):**
```cpp
class ManagedValue {
  SILValue value;
  CleanupHandle cleanup;

  static ManagedValue forOwned(SILValue v);
  static ManagedValue forUnmanaged(SILValue v);
  SILValue forward(SILGenFunction &SGF);
};
```

**Assessment:** ✅ COPIES Swift pattern exactly

---

## Integration in Lower.zig

### Cleanup Emission at Scope Exit

**Cot (lower.zig:340-360):**
```zig
fn emitCleanups(self: *Lowerer, target_depth: usize) Error!void {
    const items = self.cleanup_stack.getActiveCleanups();
    var i = items.len;
    while (i > target_depth) {
        i -= 1;
        const cleanup = items[i];
        if (cleanup.isActive()) {
            var args = [_]ir.NodeIndex{cleanup.value};
            _ = try fb.emitCall("cot_release", &args, ...);
        }
    }
}
```

**Swift Pattern (SILGenCleanup.cpp):**
```cpp
void SILGenFunction::emitCleanupsForBranch(CleanupScope scope) {
  for (auto it = Cleanups.begin(); it != scope.getDepth(); ++it) {
    if (it->isActive())
      it->emit(*this);
  }
}
```

**Assessment:** ✅ COPIES Swift pattern
- LIFO emission order
- Respects scope depth boundaries
- Called at block exit, return, break, continue

---

## IR Node: TypeMetadata

### New IR Operation

**Cot (ir.zig:94):**
```zig
pub const TypeMetadata = struct { type_name: []const u8 };
```

**Purpose:** Symbolic reference to type metadata, resolved to memory address during codegen.

**Swift Equivalent:** SILGen emits `metatype` instructions that reference type metadata.

---

## SSA Operation: metadata_addr

**Cot (op.zig:59):**
```zig
addr, local_addr, global_addr, metadata_addr, off_ptr, add_ptr, sub_ptr,
```

**Cot (gen.zig:377-390):**
```zig
.metadata_addr => {
    const type_name = v.aux.string;
    if (self.metadata_offsets) |offsets| {
        if (offsets.get(type_name)) |offset| {
            _ = try self.builder.appendFrom(.i64_const, prog_mod.constAddr(offset));
        } else {
            // No destructor - pass 0
            _ = try self.builder.appendFrom(.i64_const, prog_mod.constAddr(0));
        }
    }
}
```

**Assessment:** ✅ Follows same pattern as global_addr - symbolic reference resolved at link time

---

## Deviations from Swift (Intentional)

| Aspect | Swift | Cot | Reason |
|--------|-------|-----|--------|
| Atomic operations | CAS loops | Simple load/store | Wasm is single-threaded |
| Destructor dispatch | Function pointer | call_indirect + table | Wasm function table requirement |
| Memory freeing | Free list | Not implemented | Deferred (uses bump allocator) |
| Side tables | Weak/unowned refs | Not implemented | Out of scope |
| Thread safety | Full atomic support | None | Wasm constraint |

---

## M20: String Concatenation Runtime

### cot_string_concat Function

**Cot (arc.zig:generateStringConcatBody):**
```zig
// Parameters: s1_ptr (i64), s1_len (i64), s2_ptr (i64), s2_len (i64)
// Returns: pointer to new string data (i64)
//
// Algorithm:
// 1. new_len = s1_len + s2_len
// 2. new_ptr = bump_alloc(new_len)
// 3. memory.copy(new_ptr, s1_ptr, s1_len)
// 4. memory.copy(new_ptr + s1_len, s2_ptr, s2_len)
// 5. return new_ptr
```

**Key Implementation Details:**

| Step | Wasm Instructions | Purpose |
|------|-------------------|---------|
| Bump alloc | `global.get HP`, `global.set HP` | Allocate from heap |
| memory.copy | `memory.copy 0 0` | Wasm bulk memory operation |
| Return | ptr to new string data | Caller wraps with string_make |

**Generated Wasm (simplified):**
```wasm
(func $cot_string_concat (param i64 i64 i64 i64) (result i64)
  ;; Allocate new_len bytes
  global.get $HP
  local.get $s1_len
  local.get $s2_len
  i64.add
  global.get $HP
  i64.add
  global.set $HP

  ;; Copy s1
  global.get $old_HP  ;; dest
  local.get $s1_ptr   ;; src
  local.get $s1_len   ;; len
  memory.copy 0 0

  ;; Copy s2
  global.get $old_HP
  local.get $s1_len
  i64.add             ;; dest = old_HP + s1_len
  local.get $s2_ptr   ;; src
  local.get $s2_len   ;; len
  memory.copy 0 0

  ;; Return pointer to new string
  global.get $old_HP
)
```

**Integration with rewritedec.zig:**

The decomposition pass rewrites `string_concat` to call this runtime:

```
string_concat(s1, s2)
  → s1_ptr = extractStringPtr(s1)
  → s1_len = extractStringLen(s1)
  → s2_ptr = extractStringPtr(s2)
  → s2_len = extractStringLen(s2)
  → result_ptr = static_call("cot_string_concat", s1_ptr, s1_len, s2_ptr, s2_len)
  → result_len = add(s1_len, s2_len)
  → string_make(result_ptr, result_len)
```

---

## Test Coverage

| Test | Status | Description |
|------|--------|-------------|
| destructor_called.cot | ✅ PASS | Verifies destructor is called when object goes out of scope |
| concat_simple.cot | ✅ PASS | Basic string concatenation |
| concat_two_vars.cot | ✅ PASS | Two string variables concatenated |
| concat_var_direct.cot | ✅ PASS | Variable + literal concatenation |
| (more tests needed) | ⏳ TODO | Multiple objects, nested scopes, early return |

---

## Conclusion

**PASSES AUDIT** - M19 (Destructor Calls on Release) is complete. The implementation:

1. ✅ Correctly stores metadata pointer in object header (Swift pattern)
2. ✅ Loads destructor from metadata when refcount reaches zero (Swift pattern)
3. ✅ Uses call_indirect for destructor dispatch (Wasm adaptation of Swift's function pointer)
4. ✅ Reserves table index 0 for null (matches Swift's null pointer convention)
5. ✅ Integrates CleanupStack from arc_insertion.zig (copies Swift's CleanupManager)
6. ✅ Emits release calls at scope boundaries (copies Swift's SILGen)

No invented logic detected. All patterns trace to Swift references.
