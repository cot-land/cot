# Type Flow Through The Pipeline

**Last Updated:** February 1, 2026

This document explains how types transform as they flow through the Cot compilation pipeline. Understanding this is critical for debugging issues like the multi-variable string offset bug (M20).

---

## Type Registry (frontend/types.zig)

The TypeRegistry is the source of truth for all types. Key built-in types:

```zig
pub const BOOL: TypeIndex = 1;
pub const I8: TypeIndex = 2;
pub const I16: TypeIndex = 3;
pub const I32: TypeIndex = 4;
pub const I64: TypeIndex = 5;
pub const INT: TypeIndex = 6;    // alias for I64
pub const U8: TypeIndex = 7;
// ... more basic types ...
pub const STRING: TypeIndex = 17;
```

### STRING is a Slice

**Critical:** STRING is NOT a special type. It's defined as `{ .slice = .{ .elem = U8 } }`:

```zig
// In TypeRegistry.init():
try reg.types.append(allocator, .{ .slice = .{ .elem = U8 } }); // 17 = STRING
```

This means:
- `type_registry.get(STRING)` returns `.slice`, not `.string`
- `type_registry.sizeOf(STRING)` returns 16 (ptr + len)
- STRING values use slice handling code paths

### Type Sizes

| Type | Size (bytes) | Representation |
|------|--------------|----------------|
| BOOL | 1 | i32 in wasm |
| I32, U32, F32 | 4 | native |
| I64, U64, F64 | 8 | native |
| STRING | 16 | ptr (8) + len (8) |
| slice<T> | 16 | ptr (8) + len (8) |
| pointer<T> | 8 | i64 address |

---

## Stage 1: Frontend (AST → IR)

### String Literals in Parser

```cot
let s = "hello"
```

Parser creates a `Literal` AST node with kind `.string`.

### String Literals in Lowerer (lower.zig)

The lowerer converts string literals to IR:

```zig
.string => {
    // Add string to literal table
    const str_idx = try fb.addStringLiteral(unescaped);
    // Create const_slice referencing the literal
    return try fb.emitConstSlice(str_idx, lit.span);
}
```

This creates an IR node with `const_slice` data that references the string literal index.

### Local Variable Storage

When storing a string to a local variable:

```zig
// In lower.zig lowerLocalVarDecl:
if (type_idx == TypeRegistry.STRING) {
    try self.lowerStringInit(local_idx, var_stmt.value, var_stmt.span);
}

// In lowerStringInit:
const ptr_val = try fb.emitSlicePtr(str_node, ptr_type, span);
const len_val = try fb.emitSliceLen(str_node, span);
_ = try fb.emitStoreLocalField(local_idx, 0, 0, ptr_val, span);    // ptr at +0
_ = try fb.emitStoreLocalField(local_idx, 1, 8, len_val, span);    // len at +8
```

---

## Stage 2: SSA Builder (IR → SSA)

### String Literal Conversion

```zig
// In ssa_builder.zig convertConstSlice:
const ptr_val = try self.func.newValue(.const_64, ...);
ptr_val.aux_int = @intCast(literal_idx);  // Will become memory offset
const len_val = try self.func.newValue(.const_64, ...);
len_val.aux_int = @intCast(length);
const slice_val = try self.func.newValue(.string_make, type_idx, ...);
slice_val.addArg2(ptr_val, len_val);
```

**Output:** `string_make(const_64 ptr, const_64 len)`

### Loading String Locals

When loading a string from a local variable:

```zig
// In convertLoadLocal:
const load_type = self.type_registry.get(type_idx);

if (load_type == .slice) {  // STRING matches this!
    // Load ptr and len separately, combine with slice_make
    const ptr_load = try self.func.newValue(.load, TypeRegistry.I64, ...);
    ptr_load.addArg(addr_val);

    const len_addr = try self.func.newValue(.off_ptr, ...);
    len_addr.aux_int = 8;  // len is at offset 8

    const len_load = try self.func.newValue(.load, TypeRegistry.I64, ...);
    len_load.addArg(len_addr);

    const slice_val = try self.func.newValue(.slice_make, type_idx, ...);
    slice_val.addArg2(ptr_load, len_load);
    return slice_val;
}
```

**Critical:** STRING loads create `slice_make`, NOT `string_make`!

This is because `type_registry.get(STRING)` returns `.slice`.

---

## Stage 3: Rewrite Passes

### rewritegeneric.zig

Converts `const_string` ops to `string_make`:

```
const_string("hello") → string_make(addr, 5)
```

This happens for inline string literals that weren't already converted.

### rewritedec.zig

Decomposes compound type operations:

```
slice_len(slice_make(ptr, len)) → copy(len)
slice_ptr(slice_make(ptr, len)) → copy(ptr)
string_len(string_make(ptr, len)) → copy(len)
string_ptr(string_make(ptr, len)) → copy(ptr)
```

**Critical Pattern:** Must handle BOTH `string_make` AND `slice_make`:

```zig
// In extractStringPtr:
if ((s.op == .string_make or s.op == .slice_make) and s.args.len >= 1) {
    return s.args[0];  // Return the ptr component
}
```

If this only checked `string_make`, it would miss STRING values loaded from locals!

### String Concatenation

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

## Stage 4: Wasm Codegen (gen.zig)

### Local Variable Layout

Local variables are allocated on the stack frame. The frame is at `SP` (stack pointer global).

**Critical:** Must use actual sizes, not assume 8 bytes per slot!

```zig
// WRONG (old code):
const offset = slot * 8;  // Assumes 8 bytes per slot

// CORRECT (fixed code):
fn getLocalOffset(self: *const GenState, local_idx: usize) i64 {
    var offset: i64 = 0;
    for (0..local_idx) |i| {
        offset += @intCast(self.func.local_sizes[i]);  // Use actual sizes
    }
    return offset;
}
```

**Example Layout with Two Strings:**

```
Frame:
+0:  s1.ptr (8 bytes)
+8:  s1.len (8 bytes)
+16: s2.ptr (8 bytes)  ← Was incorrectly at +8 with slot*8!
+24: s2.len (8 bytes)
```

### String Make/Slice Make

These are "compound type" ops that don't generate code directly:

```zig
.string_make, .slice_make => {
    // No code - these values are decomposed when accessed
},
```

The ptr and len components are accessed via `slice_ptr`/`slice_len` ops.

---

## Common Pitfalls

### 1. Forgetting STRING is a Slice

```zig
// WRONG: Checking for STRING specifically
if (type_idx == TypeRegistry.STRING) { ... }

// RIGHT: Checking the type structure
const type_info = type_registry.get(type_idx);
if (type_info == .slice) { ... }  // Matches STRING too
```

### 2. Only Checking string_make

```zig
// WRONG: Only handles literal strings
if (s.op == .string_make) { ... }

// RIGHT: Handles both literals and loaded values
if (s.op == .string_make or s.op == .slice_make) { ... }
```

### 3. Assuming Fixed Slot Size

```zig
// WRONG: Assumes 8 bytes per local
const offset = local_idx * 8;

// RIGHT: Sum actual sizes
var offset: i64 = 0;
for (0..local_idx) |i| {
    offset += local_sizes[i];
}
```

### 4. Missing Pattern Match in Decomposition

When adding new compound types, ensure ALL extraction patterns are updated:
- `extractStringPtr` / `extractStringLen`
- `rewriteSlicePtr` / `rewriteSliceLen`
- `rewriteStringPtr` / `rewriteStringLen`

---

## Debugging Type Issues

### Check What Type You Actually Have

```zig
const debug = @import("../../pipeline_debug.zig");
debug.log(.codegen, "type_idx={d}, type={s}", .{
    type_idx,
    @tagName(type_registry.get(type_idx))
});
```

### Check What Op Was Generated

```zig
debug.log(.codegen, "v{d}: op={s}, args.len={d}", .{
    v.id, @tagName(v.op), v.args.len
});
```

### Trace Decomposition

```zig
// In rewritedec.zig
debug.log(.codegen, "  v{d}: {s}({s}) -> ...", .{
    v.id, @tagName(v.op), @tagName(v.args[0].op)
});
```

---

## Summary: STRING Through Pipeline

| Stage | Representation |
|-------|----------------|
| Source | `"hello"` (literal) or `s1` (variable) |
| AST | `Literal { kind: .string, value: "hello" }` |
| IR | `const_slice { idx: 0 }` or `field_local { offset: 8 }` |
| SSA | `string_make(ptr, len)` (literal) or `slice_make(ptr_load, len_load)` (variable) |
| After rewritedec | `copy(ptr)` / `copy(len)` when extracted |
| Wasm | `i64.const` / `i64.load` depending on source |
