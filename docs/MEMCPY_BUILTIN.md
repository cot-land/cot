# @memcpy Builtin Design

**Date:** February 2026
**Status:** Not implemented
**Priority:** LOW (List(T) works without it, but code is verbose)
**Estimated effort:** Small (1-2 hours)

---

## Motivation

Currently, copying a range of elements requires manual while loops:

```cot
// Clone a list: copy count elements from src to dst
var i: i64 = 0
while i < self.count {
    let src = @intToPtr(*T, self.items + i * @sizeOf(T))
    let dst = @intToPtr(*T, new_items + i * @sizeOf(T))
    dst.* = src.*
    i = i + 1
}
```

With `@memcpy`:

```cot
@memcpy(new_items, self.items, self.count * @sizeOf(T))
```

This matters for:
- `List.clone()` — copy entire backing array
- `List.insert()` — shift elements right
- `List.orderedRemove()` — shift elements left
- `List.appendSlice()` — bulk append (once slice params exist)

---

## Reference Implementations

### Go: `copy()` builtin

**File:** `~/learning/go/src/cmd/compile/internal/walk/builtin.go:159-235`

Go's `copy(dst, src)` lowers to:
1. Extract `dst.ptr`, `src.ptr`, `min(dst.len, src.len)`
2. If element type has pointers: call `typedslicecopy()` (write barrier)
3. Otherwise: call `memmove(dst_ptr, src_ptr, n * sizeof(elem))`

Key: Go uses `memmove` (handles overlapping regions), not `memcpy`.

### Zig: `@memcpy`

Zig's `@memcpy(dest, source)` compiles to:
- **Wasm:** `memory.copy` instruction (bulk memory proposal)
- **Native:** `memmove` call or inline copy loop

Semantics: `dest` and `source` must not overlap (undefined behavior if they do).
For overlapping copies, Zig provides `std.mem.copyBackwards`.

### Wasm: `memory.copy`

Wasm bulk memory instruction (opcode `0xFC 0x0A`):
```
memory.copy dst_offset src_offset length
```
- Handles overlapping regions correctly (like memmove)
- Part of the bulk memory proposal (widely supported)

### C: `memcpy` / `memmove`

- `memcpy(dst, src, n)`: UB on overlap. Fast.
- `memmove(dst, src, n)`: Safe on overlap. Slightly slower.

---

## Design

### Syntax

```cot
@memcpy(dst: i64, src: i64, num_bytes: i64) void
```

All arguments are raw `i64` values (byte addresses), matching Cot's current pointer model
where `items: i64` stores raw pointers. No typed pointer arithmetic needed.

### Semantics

- Copies `num_bytes` bytes from `src` to `dst`
- `dst` and `src` may overlap (memmove semantics, like Go and Wasm)
- If `num_bytes <= 0`, no-op
- If `dst` or `src` is invalid, undefined behavior (same as pointer dereference)

**Why memmove semantics:** `List.insert()` and `List.orderedRemove()` need to shift
elements within the same backing array, which means overlapping source and destination.
Using memcpy semantics would be a footgun.

### Alternative: `@memmove` name

Could name it `@memmove` to be explicit about overlap safety. But:
- Zig uses `@memcpy` (users expect it)
- Go's `copy()` handles overlap too
- The name `@memcpy` is more discoverable

**Decision:** `@memcpy` with memmove semantics. Document that overlap is safe.

---

## Implementation Plan

### 1. Scanner/Parser

No changes needed. `@memcpy` uses the existing builtin call syntax (`@identifier(args)`).

### 2. Checker (`compiler/frontend/checker.zig`)

Add to `checkBuiltinCall` (around line 652):

```zig
if (std.mem.eql(u8, bc.name, "memcpy")) {
    if (bc.args.len != 3) return error.WrongArgCount;
    // All 3 args must be integer types (i64 addresses + byte count)
    for (bc.args) |arg| {
        const arg_type = try self.checkExpr(arg);
        if (!self.type_reg.isIntegerType(arg_type)) return error.TypeMismatch;
    }
    return TypeRegistry.VOID;
}
```

### 3. Lowerer (`compiler/frontend/lower.zig`)

Add to `lowerBuiltinCall` (around line 2959):

```zig
if (std.mem.eql(u8, bc.name, "memcpy")) {
    const dst = try self.lowerExprNode(bc.args[0]);
    const src = try self.lowerExprNode(bc.args[1]);
    const len = try self.lowerExprNode(bc.args[2]);
    var args = [_]ir.NodeIndex{ dst, src, len };
    return try fb.emitCall("memcpy", &args, false, TypeRegistry.VOID, bc.span);
}
```

Note: The lowerer already emits `memcpy` calls internally for struct/array copies
(lower.zig:567, 1106, 1128). This just exposes it to user code.

### 4. Wasm Backend

`memcpy` is already handled as an extern function import. The Wasm runtime provides it.
No changes needed for the basic case.

**Future optimization:** Emit `memory.copy` instruction directly instead of calling
the imported `memcpy` function. This is a performance optimization, not required for
correctness.

### 5. Native Backend

`memcpy` calls are already handled by the native AOT pipeline (translated as regular
function calls). The C linker resolves `memcpy` from libc.
No changes needed.

---

## Test Plan

### Unit Tests (checker)

```cot
// Should compile: valid @memcpy
fn test_memcpy_valid() void {
    let dst = @alloc(16)
    let src = @alloc(16)
    @memcpy(dst, src, 16)
    @dealloc(src)
    @dealloc(dst)
}

// Should fail: wrong arg count
fn test_memcpy_wrong_args() void {
    @memcpy(0, 0)  // error: expected 3 arguments
}
```

### E2E Tests (Wasm + Native)

```cot
fn test_memcpy_basic() i64 {
    let src = @alloc(24)
    let dst = @alloc(24)
    // Write 3 i64 values to src
    let p0 = @intToPtr(*i64, src)
    p0.* = 10
    let p1 = @intToPtr(*i64, src + 8)
    p1.* = 20
    let p2 = @intToPtr(*i64, src + 16)
    p2.* = 30
    // Copy all 24 bytes
    @memcpy(dst, src, 24)
    // Verify
    let d0 = @intToPtr(*i64, dst)
    let d1 = @intToPtr(*i64, dst + 8)
    let d2 = @intToPtr(*i64, dst + 16)
    if d0.* != 10 { return 1 }
    if d1.* != 20 { return 2 }
    if d2.* != 30 { return 3 }
    @dealloc(src)
    @dealloc(dst)
    return 0
}

fn test_memcpy_overlap() i64 {
    // Test memmove semantics: shift elements right within same buffer
    let buf = @alloc(40)  // 5 i64 slots
    // Write [10, 20, 30, 40, 50]
    @intToPtr(*i64, buf).* = 10
    @intToPtr(*i64, buf + 8).* = 20
    @intToPtr(*i64, buf + 16).* = 30
    @intToPtr(*i64, buf + 24).* = 40
    @intToPtr(*i64, buf + 32).* = 50
    // Shift elements 0-3 right by 1: copy 32 bytes from buf to buf+8
    @memcpy(buf + 8, buf, 32)
    // Expect [10, 10, 20, 30, 40]
    if @intToPtr(*i64, buf).* != 10 { return 1 }
    if @intToPtr(*i64, buf + 8).* != 10 { return 2 }
    if @intToPtr(*i64, buf + 16).* != 20 { return 3 }
    @dealloc(buf)
    return 0
}

fn test_memcpy_zero_length() i64 {
    let buf = @alloc(8)
    @intToPtr(*i64, buf).* = 42
    @memcpy(buf, buf, 0)  // no-op
    if @intToPtr(*i64, buf).* != 42 { return 1 }
    @dealloc(buf)
    return 0
}
```

---

## Files to Modify

| File | Change |
|------|--------|
| `compiler/frontend/checker.zig` | Add `memcpy` case to `checkBuiltinCall` (~3 lines) |
| `compiler/frontend/lower.zig` | Add `memcpy` case to `lowerBuiltinCall` (~5 lines) |
| `test/native/e2e_all.cot` | Add E2E test functions |
| `compiler/codegen/wasm_e2e_test.zig` | Add Wasm compilation test |
| `compiler/codegen/native_e2e_test.zig` | Update sub-test count |

**Total code change: ~10 lines of compiler code + test cases**

The lowerer already calls `memcpy` internally. This just exposes it as a builtin.
