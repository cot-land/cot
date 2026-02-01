# rewritegeneric.zig Audit

**Last Updated:** February 1, 2026
**Go Reference:** `cmd/compile/internal/ssa/rewritegeneric.go`
**Status:** ✅ WORKING

---

## Purpose

The rewritegeneric pass performs algebraic simplifications and canonicalizations on the SSA. In Cot, its primary job is converting `const_string` operations to `string_make`.

---

## Go Pattern

Go's `rewritegeneric.go` is auto-generated from `_gen/generic.rules` and contains thousands of rewrite rules. Key patterns:

```go
// (ConstString {s}) => (StringMake (Addr <StringPtrType> {s}) (Const64 [len(s)]))
```

The pattern matches a `ConstString` op and replaces it with a `StringMake` that contains the string's address and length.

---

## Cot Implementation

### File Location
`compiler/ssa/passes/rewritegeneric.zig`

### Core Function

```zig
pub fn rewrite(allocator: std.mem.Allocator, f: *Func) !void {
    for (f.blocks.items) |block| {
        for (block.values.items) |v| {
            _ = try rewriteValue(allocator, f, block, v);
        }
    }
}

fn rewriteValue(allocator, f, block, v) !bool {
    return switch (v.op) {
        .const_string => rewriteConstString(allocator, f, block, v),
        else => false,
    };
}
```

### const_string → string_make

```zig
fn rewriteConstString(allocator, f, block, v) !bool {
    // Get string literal index from aux
    const lit_idx = v.aux_int;
    const lit = f.string_literals[lit_idx];

    // Create const_64 for pointer (literal index, resolved to address at link time)
    const ptr_val = try f.newValue(.const_64, TypeRegistry.I64, block, v.pos);
    ptr_val.aux_int = @intCast(lit_idx);

    // Create const_64 for length
    const len_val = try f.newValue(.const_64, TypeRegistry.I64, block, v.pos);
    len_val.aux_int = @intCast(lit.len);

    // Create string_make(ptr, len)
    const result = try f.newValue(.string_make, TypeRegistry.STRING, block, v.pos);
    result.addArg2(ptr_val, len_val);

    // Replace original with copy of result
    copyOf(v, result);
    return true;
}
```

---

## Pass Order

rewritegeneric runs **before** rewritedec:

1. **rewritegeneric** - `const_string` → `string_make(ptr, len)`
2. **rewritedec** - `string_len(string_make(ptr, len))` → `copy(len)`
3. **lower_wasm** - Generic ops → Wasm-specific ops

---

## Test Coverage

- `test/cases/strings/len_simple.cot` - Basic string literal length
- `test/cases/strings/len_empty.cot` - Empty string
- `test/cases/strings/len_long.cot` - Long string

All pass as of M20.

---

## Potential Extensions

| Rule | Go Pattern | Status |
|------|------------|--------|
| Constant folding | `(Add64 (Const64 [a]) (Const64 [b]))` → `Const64 [a+b]` | Not implemented |
| Boolean simplification | `(Eq64 x x)` → `ConstBool [true]` | Not implemented |
| Dead code elimination | Remove unused values | Handled elsewhere |

These are lower priority since the current codebase works without them.
