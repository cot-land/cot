# rewritedec.zig Audit

**Last Updated:** February 1, 2026
**Go Reference:** `cmd/compile/internal/ssa/rewritedec.go`
**Status:** ✅ WORKING

---

## Purpose

The rewritedec (decomposition) pass decomposes compound type operations. When you extract a component from a compound type (like getting the length of a slice), this pass rewrites it to directly access the component.

---

## Go Pattern

Go's `rewritedec.go` handles decomposition of:
- Slices (ptr, len, cap)
- Strings (ptr, len)
- Complex numbers (real, imag)
- Interfaces (tab, data)

Key patterns from Go:

```go
// SliceLen(SliceMake _ len _) => len
// SlicePtr(SliceMake ptr _ _) => ptr
// StringLen(StringMake _ len) => len
// StringPtr(StringMake ptr _) => ptr

// SliceLen(Load<slice> ptr mem) => Load<int> (OffPtr [PtrSize] ptr) mem
// StringLen(Load<string> ptr mem) => Load<int> (OffPtr [PtrSize] ptr) mem
```

---

## Cot Implementation

### File Location
`compiler/ssa/passes/rewritedec.zig`

### Core Function

```zig
pub fn rewrite(allocator: std.mem.Allocator, f: *Func) !void {
    var iterations: usize = 0;
    const max_iterations = 100;

    while (iterations < max_iterations) {
        var changed = false;
        iterations += 1;

        for (f.blocks.items) |block| {
            for (block.values.items) |v| {
                const did_rewrite = try rewriteValue(allocator, f, block, v);
                if (did_rewrite) changed = true;
            }
        }

        if (!changed) break;  // Fixpoint reached
    }
}
```

### Dispatch Table

```zig
fn rewriteValue(allocator, f, block, v) !bool {
    return switch (v.op) {
        .slice_ptr => rewriteSlicePtr(allocator, f, block, v),
        .slice_len => rewriteSliceLen(allocator, f, block, v),
        .string_ptr => rewriteStringPtr(allocator, f, block, v),
        .string_len => rewriteStringLen(allocator, f, block, v),
        .string_concat => rewriteStringConcat(allocator, f, block, v),
        else => false,
    };
}
```

---

## Decomposition Patterns

### slice_len / slice_ptr

```zig
fn rewriteSliceLen(allocator, f, block, v) !bool {
    const v_0 = followCopy(v.args[0]);

    // Pattern 1: SliceLen(SliceMake _ len _) → len
    if (v_0.op == .slice_make and v_0.args.len >= 2) {
        copyOf(v, v_0.args[1]);  // len is arg[1]
        return true;
    }

    // Pattern 2: SliceLen(Load<slice> ptr) → Load<i64>(OffPtr ptr 8)
    if (v_0.op == .load and isSliceType(v_0.type_idx)) {
        const ptr = v_0.args[0];
        const off_ptr = try f.newValue(.off_ptr, ...);
        off_ptr.aux_int = 8;  // len offset
        off_ptr.addArg(ptr);

        const load_val = try f.newValue(.load, TypeRegistry.I64, ...);
        load_val.addArg(off_ptr);

        copyOf(v, load_val);
        return true;
    }

    // Pattern 3: SliceLen(StringMake _ len) → len
    if (v_0.op == .string_make and v_0.args.len >= 2) {
        copyOf(v, v_0.args[1]);
        return true;
    }

    return false;
}
```

### string_len / string_ptr

Same patterns, but also checks for `slice_make`:

```zig
fn rewriteStringLen(allocator, f, block, v) !bool {
    const v_0 = followCopy(v.args[0]);

    // Pattern 1: StringLen(StringMake _ len) → len
    if (v_0.op == .string_make and v_0.args.len >= 2) {
        copyOf(v, v_0.args[1]);
        return true;
    }

    // Pattern 2: StringLen(Load<STRING> ptr) → Load<i64>(OffPtr ptr 8)
    if (v_0.op == .load and v_0.type_idx == TypeRegistry.STRING) {
        // ... create off_ptr + load ...
        return true;
    }

    return false;
}
```

---

## String Concatenation (M20)

```zig
fn rewriteStringConcat(allocator, f, block, v) !bool {
    const s1 = v.args[0];
    const s2 = v.args[1];

    // Extract ptr/len from both strings
    const s1_ptr = try extractStringPtr(allocator, f, block, s1, v.pos);
    const s1_len = try extractStringLen(allocator, f, block, s1, v.pos);
    const s2_ptr = try extractStringPtr(allocator, f, block, s2, v.pos);
    const s2_len = try extractStringLen(allocator, f, block, s2, v.pos);

    // Create static_call to cot_string_concat
    const call = try f.newValue(.static_call, TypeRegistry.I64, ...);
    call.aux = .{ .string = "cot_string_concat" };
    call.addArg(s1_ptr);
    call.addArg(s1_len);
    call.addArg(s2_ptr);
    call.addArgAlloc(s2_len, allocator);  // 4th arg needs allocator

    // Create new_len = s1_len + s2_len
    const new_len = try f.newValue(.add, TypeRegistry.I64, ...);
    new_len.addArg2(s1_len, s2_len);

    // Create string_make(call_result, new_len)
    const result = try f.newValue(.string_make, TypeRegistry.STRING, ...);
    result.addArg2(call, new_len);

    copyOf(v, result);
    return true;
}
```

### Extract Helpers

**Critical:** Must handle BOTH `string_make` AND `slice_make`:

```zig
fn extractStringPtr(allocator, f, block, s, pos) !*Value {
    // Pattern 1: string_make or slice_make - direct extraction
    if ((s.op == .string_make or s.op == .slice_make) and s.args.len >= 1) {
        return s.args[0];
    }

    // Pattern 2: Load<STRING> - create load of ptr field
    if (s.op == .load and s.type_idx == TypeRegistry.STRING) {
        const load_val = try f.newValue(.load, TypeRegistry.I64, ...);
        load_val.addArg(s.args[0]);
        return load_val;
    }

    // Fallback: create string_ptr op (rewritten next iteration)
    const ptr_val = try f.newValue(.string_ptr, TypeRegistry.I64, ...);
    ptr_val.addArg(s);
    return ptr_val;
}
```

**Why both ops?**
- `string_make` - Created for string literals
- `slice_make` - Created when loading STRING from local variable (because STRING is internally a slice type)

---

## Copy Following

Values can be wrapped in `copy` ops. Must follow the chain:

```zig
fn followCopy(v: *Value) *Value {
    var current = v;
    while (current.op == .copy and current.args.len >= 1) {
        current = current.args[0];
    }
    return current;
}
```

---

## Pass Order

rewritedec runs **after** rewritegeneric:

1. **rewritegeneric** - `const_string` → `string_make(ptr, len)`
2. **rewritedec** - Decompose extractions and concatenations
3. **lower_wasm** - Generic ops → Wasm-specific ops

---

## Test Coverage

| Test | Pattern Exercised |
|------|-------------------|
| len_simple.cot | `string_len(string_make)` |
| len_empty.cot | `string_len(string_make)` with len=0 |
| concat_direct_len.cot | `string_concat` inline |
| concat_simple.cot | `string_concat` with variables |
| concat_two_vars.cot | Multiple variable loads |
| concat_var_direct.cot | Mix of variable and literal |

All pass as of M20.

---

## Known Limitations

1. **No cap field** - Cot slices don't have capacity (unlike Go's 3-field slice)
2. **No interface decomposition** - Cot doesn't have Go-style interfaces
3. **No complex numbers** - Not supported in Cot

---

## Debugging Tips

### Check if pattern matched

```zig
debug.log(.codegen, "  v{d}: {s}({s}) -> copy v{d}", .{
    v.id, @tagName(v.op), @tagName(v_0.op), result.id
});
```

### Check iteration count

If iterations = 100, decomposition didn't converge - likely creating new ops that recreate the pattern.

### Check for undecomposed ops in gen.zig

```zig
.string_ptr, .string_len, .slice_ptr, .slice_len => {
    debug.log(.codegen, "wasm/gen: undecomposed extraction op {s}", .{@tagName(v.op)});
},
```

If this fires, a pattern in rewritedec is missing.
