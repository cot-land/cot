# Slice Parameter Passing Design

**Date:** February 2026
**Status:** Partially implemented (type exists, call-site decomposition missing)
**Priority:** HIGH (unblocks appendSlice, passing collections between functions)
**Estimated effort:** Medium (2-4 hours)

---

## Motivation

Cot has slice types (`[]T`) in the type system and can create slices with `arr[start:end]`.
But you **cannot pass a slice to a function**:

```cot
fn sum(items: []i64) i64 {    // Parser: OK. Checker: OK. Lowerer: BROKEN.
    var total: i64 = 0
    var i: i64 = 0
    while i < items.len {
        total = total + items[i]
        i = i + 1
    }
    return total
}

fn main() i64 {
    var arr = [10, 20, 30]
    return sum(arr[0:3])       // Call site doesn't decompose slice into (ptr, len)
}
```

This blocks:
- `List.appendSlice(items: []T)` — can't bulk-append from another collection
- `List.insertSlice(index: i64, items: []T)` — can't bulk-insert
- Passing sub-arrays to utility functions
- Any function that operates on a "view" of data without owning it

---

## Current State: What Works and What Doesn't

### Works (5 stages)

| Stage | What Works | Location |
|-------|-----------|----------|
| **Parser** | `[]T` parsed as type expression | parser.zig:400-403 |
| **Type System** | `SliceType { elem: TypeIndex }`, 24 bytes (ptr+len+cap) | types.zig:69-70, 253 |
| **Checker** | `[]T` validated in params, `len()` on slices, indexing | checker.zig:595-672 |
| **SSA Builder** | Receives `[]T` params as 2 args (ptr, len), reconstructs via `slice_make` | ssa_builder.zig:58-75 |
| **SSA Passes** | `slice_ptr`, `slice_len`, `slice_cap` decomposition | rewritedec.zig |

### Broken (1 stage)

| Stage | What's Broken | Location |
|-------|--------------|----------|
| **Lowerer (call site)** | When calling `fn foo(items: []T)`, the slice argument is passed as a single 24-byte value instead of being decomposed into (ptr, len) | lower.zig:2463-2488 |

### The Mismatch

```
Call site (lowerer):     passes slice as 1 argument (24-byte struct)
                              ↓
Function entry (SSA):    expects slice as 2 arguments (ptr: i64, len: i64)
                              ↕ MISMATCH
Result:                  SSA arg indices are wrong → garbage values
```

---

## Reference Implementations

### Go: Slice Calling Convention

**File:** `~/learning/go/src/cmd/compile/internal/walk/builtin.go:159-235`

Go passes slices as 3 values on the stack: `(ptr, len, cap)`.
At the call site, Go extracts these with unary operators:
- `OSPTR(slice)` → pointer
- `OLEN(slice)` → length
- `OCAP(slice)` → capacity

The compiler explicitly decomposes slices at call sites and recomposes them at function entry.

### Zig: Slice Calling Convention

Zig slices are `{ ptr: [*]T, len: usize }` (2 words, no capacity).
Passed as 2 register values or a 16-byte struct depending on ABI.

### Cot's Current Design

Cot slices are 24 bytes: `(ptr: i64, len: i64, cap: i64)` — matching Go's layout.
At SSA level, they're decomposed into 2 register values `(ptr, len)` via the
`slice_make` / `slice_ptr` / `slice_len` SSA ops.

**The issue is only in the lowerer's call-site code.**

---

## Implementation Plan

### The Fix: Call-Site Slice Decomposition

The lowerer's function call handling (`lowerFuncCall`, around line 2463) currently does:

```zig
for (call.args, 0..) |arg_idx, arg_i| {
    var arg_node = try self.lowerExprNode(arg_idx);
    try args.append(self.allocator, arg_node);
}
```

It needs to check if the parameter type is a slice and decompose:

```zig
for (call.args, 0..) |arg_idx, arg_i| {
    const param_type = callee_func.params[arg_i].type_idx;

    if (self.type_reg.get(param_type) == .slice) {
        // Decompose slice into (ptr, len) — 2 args for 1 param
        const slice_val = try self.lowerExprNode(arg_idx);
        const ptr_val = try fb.emitSlicePtr(slice_val, TypeRegistry.I64, span);
        const len_val = try fb.emitSliceLen(slice_val, TypeRegistry.I64, span);
        try args.append(self.allocator, ptr_val);
        try args.append(self.allocator, len_val);
    } else {
        var arg_node = try self.lowerExprNode(arg_idx);
        try args.append(self.allocator, arg_node);
    }
}
```

### Detailed Steps

#### 1. Lowerer: Call-site decomposition (`compiler/frontend/lower.zig`)

**Where:** `lowerFuncCall` function, around line 2463-2488.

**What:** When the callee's parameter type is `.slice`:
1. Lower the argument expression (produces a 24-byte slice value)
2. Extract `slice_ptr` (offset 0)
3. Extract `slice_len` (offset 8)
4. Append both as separate arguments to the call

**Edge cases:**
- String arguments to `[]u8` params: strings are already (ptr, len) — may need special handling
- Multiple slice params: each decomposes independently
- Slice literals (`[1,2,3]` passed directly): must create slice_make first

#### 2. Lowerer: Return type handling

If a function returns `[]T`, the return value should be recomposed from (ptr, len) at the
call site. Check if this already works via the existing `slice_make` pattern.

#### 3. Wasm Backend

No changes expected. The SSA already decomposes slices into i64 values. The Wasm backend
just sees two i64 arguments instead of one.

#### 4. Native Backend

No changes expected. Same reasoning as Wasm.

#### 5. Checker

May need to verify that:
- Array expressions can be implicitly converted to slices when passed to `[]T` params
- `[10, 20, 30]` creates a slice when the parameter expects `[]T`

---

## Test Plan

### Phase 1: Basic Slice Passing

```cot
fn sum(items: []i64) i64 {
    var total: i64 = 0
    var i: i64 = 0
    while i < items.len {
        let ptr = @intToPtr(*i64, items.ptr + i * 8)
        total = total + ptr.*
        i = i + 1
    }
    return total
}

fn main() i64 {
    var arr = [10, 20, 30]
    let s = arr[0:3]
    return sum(s)  // Expected: 60
}
```

### Phase 2: Slice from Array Literal

```cot
fn first(items: []i64) i64 {
    let ptr = @intToPtr(*i64, items.ptr)
    return ptr.*
}

fn main() i64 {
    return first([42, 99, 7])  // Expected: 42
}
```

### Phase 3: Multiple Slice Params

```cot
fn concat_sum(a: []i64, b: []i64) i64 {
    var total: i64 = 0
    var i: i64 = 0
    while i < a.len {
        let ptr = @intToPtr(*i64, a.ptr + i * 8)
        total = total + ptr.*
        i = i + 1
    }
    i = 0
    while i < b.len {
        let ptr = @intToPtr(*i64, b.ptr + i * 8)
        total = total + ptr.*
        i = i + 1
    }
    return total
}

fn main() i64 {
    var arr1 = [10, 20]
    var arr2 = [30, 40]
    return concat_sum(arr1[0:2], arr2[0:2])  // Expected: 100
}
```

### Phase 4: Slice Return

```cot
fn take(items: []i64, n: i64) []i64 {
    // Return first n elements as a slice
    return items[0:n]  // This creates a new slice from existing
}
```

### Phase 5: List.appendSlice

Once slice params work, this becomes possible:

```cot
impl List(T) {
    fn appendSlice(self: *List(T), items: []T) void {
        self.ensureTotalCapacity(self.count + items.len)
        @memcpy(
            self.items + self.count * @sizeOf(T),
            items.ptr,
            items.len * @sizeOf(T)
        )
        self.count = self.count + items.len
    }
}
```

---

## Files to Modify

| File | Change | Effort |
|------|--------|--------|
| `compiler/frontend/lower.zig` | Decompose slice args at call sites | Main change (~20 lines) |
| `compiler/frontend/lower.zig` | Handle slice return values if needed | ~10 lines |
| `compiler/frontend/checker.zig` | Array-to-slice implicit conversion at call sites | ~10 lines |
| `test/native/e2e_all.cot` | Add E2E test functions | ~50 lines |
| `compiler/codegen/wasm_e2e_test.zig` | Add Wasm compilation tests | ~30 lines |
| `compiler/codegen/native_e2e_test.zig` | Update sub-test count | ~5 lines |

**Total code change: ~40 lines of compiler code + test cases**

The heavy lifting (type system, SSA decomposition, SSA builder) is already done.
This is purely a lowerer call-site fix.

---

## Risks

| Risk | Mitigation |
|------|-----------|
| String/slice confusion (strings are also ptr+len) | Check existing string param handling, ensure consistency |
| Array-to-slice coercion at call sites | May need explicit slice syntax initially (`arr[0:len]`) |
| Generic functions with `[]T` params | Test with monomorphized generics |
| Multiple slices expanding arg count | SSA builder already handles multi-arg, just verify |
