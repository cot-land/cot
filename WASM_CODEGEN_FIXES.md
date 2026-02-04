# Wasm Codegen Fixes - Execution Plan

## Executive Summary

Two bugs identified in Wasm codegen (not native AOT) - **BOTH FIXED**:

| Bug | Symptom | Fix Location | Status |
|-----|---------|--------------|--------|
| Struct-by-value params | Stack underflow on call | `ssa_builder.zig:convertCall` | ✅ FIXED |
| Pointer arithmetic | Wrong address calculation | `lower.zig:lowerBinary` | ✅ FIXED |

**Methodology**: Follow TROUBLESHOOTING.md - copy Go reference exactly.

---

## Reference Files

| Our Code | Reference Code | Purpose |
|----------|----------------|---------|
| `compiler/ssa/passes/lower_wasm.zig` | `~/learning/go/src/cmd/compile/internal/wasm/ssa.go` | SSA → Wasm ops |
| `compiler/codegen/wasm/gen.zig` | `~/learning/go/src/cmd/internal/obj/wasm/wasmobj.go` | Wasm op → bytes |
| `compiler/frontend/lower.zig` | Go's expansion pass | AST → IR lowering |
| `compiler/ssa/passes/rewritedec.zig` | `~/learning/go/src/cmd/compile/internal/ssa/rewritedec.go` | Compound type decomposition |

---

## Bug 1: Struct-by-Value Parameters

### Symptom

```cot
struct Point { x: i64, y: i64 }
fn getX(p: Point) i64 { return p.x }
fn main() i64 {
    let p = Point { .x = 42, .y = 100 }
    return getX(p)  // CRASH: stack underflow
}
```

Wasm execution error: "not enough arguments on the stack for call (need 2, got 1)"

### Root Cause Hypothesis

The call site pushes 1 argument (the struct as a whole) but the callee expects 2 arguments (x and y fields decomposed).

### Investigation Plan

1. **Check how Go decomposes struct params**
   - File: `~/learning/go/src/cmd/compile/internal/ssa/rewritedec.go`
   - Look for: Struct decomposition at call sites

2. **Check our call lowering**
   - File: `compiler/frontend/lower.zig` (call expression handling)
   - File: `compiler/ssa/passes/lower_wasm.zig` (wasm call generation)

3. **Compare call instruction generation**
   - Go's pattern for struct-by-value
   - Our current implementation

### Tasks

- [x] **1.1** Read Go's `rewritedec.go` for struct decomposition pattern
- [x] **1.2** Find where Go handles struct args at call sites
- [x] **1.3** Compare with our `ssa_builder.zig` call handling
- [x] **1.4** Copy Go's decomposition pattern exactly
- [x] **1.5** Test: `getX(p)` returns 42

### Fix Details (Feb 5, 2026)

**Root Cause**: `convertCall` in `ssa_builder.zig` was adding struct arguments as-is, but the callee expected decomposed fields (2 args for a 16-byte struct).

**Go Reference**: `expand_calls.go:268` - `rewriteCallArgs` decomposes struct arguments

**Fix** (ssa_builder.zig:569-630): When a call argument is a large struct (>8 bytes, <=16 bytes), decompose it:
1. Get the struct's memory address
2. Load low part (first 8 bytes)
3. Load high part (next 8 bytes)
4. Add both as separate arguments

```zig
// In convertCall, for large struct args:
const is_large_struct = arg_type == .struct_type and type_size > 8 and type_size <= 16;
if (is_large_struct) {
    const addr = try self.getStructAddr(arg_val, cur);
    // Load low part
    const lo_val = try self.func.newValue(.load, TypeRegistry.I64, cur, self.cur_pos);
    lo_val.addArg(addr);
    try call_val.addArgAlloc(lo_val, self.allocator);
    // Load high part
    const hi_addr = try self.func.newValue(.off_ptr, TypeRegistry.VOID, cur, self.cur_pos);
    hi_addr.aux_int = 8;
    hi_addr.addArg(addr);
    const hi_val = try self.func.newValue(.load, TypeRegistry.I64, cur, self.cur_pos);
    hi_val.addArg(hi_addr);
    try call_val.addArgAlloc(hi_val, self.allocator);
}
```

**Tests**:
- `getX(Point{.x=42, .y=100})` returns 42 ✅
- `getY(Point{.x=42, .y=100})` returns 100 ✅
- `getX(p) + getY(p)` returns 142 ✅
- Works on both Wasm and Native targets ✅

---

## Bug 2: Pointer Arithmetic

### Symptom

```cot
fn main() i64 {
    let arr = [10, 20, 30, 40, 50]
    let p = &arr[0]
    let p2 = p + 2
    return p2.*  // Returns 0 (native) or garbage (wasm), expected 30
}
```

### Root Cause Hypothesis

Pointer arithmetic `p + n` is not scaling by element size. Adding 2 should add `2 * sizeof(i64) = 16 bytes`, but may be adding just 2 bytes.

### Investigation Plan

1. **Check how Go handles pointer arithmetic**
   - File: `~/learning/go/src/cmd/compile/internal/wasm/ssa.go`
   - Look for: `OpOffPtr`, `OpAddPtr`, `OpPtrAdd`

2. **Check our pointer arithmetic lowering**
   - File: `compiler/ssa/passes/lower_wasm.zig`
   - Look for: `add_ptr`, `off_ptr`, pointer operations

3. **Verify element size scaling**
   - Is `p + n` computing `p + n * sizeof(element)`?
   - Or is it computing `p + n` (no scaling)?

### Tasks

- [x] **2.1** Read Go's pointer arithmetic in `wasm/ssa.go`
- [x] **2.2** Find Go's `OpOffPtr` or equivalent handling
- [x] **2.3** Compare with our `add_ptr` / pointer operations
- [x] **2.4** Copy Go's scaling pattern exactly
- [x] **2.5** Test: `p + 2` points to arr[2]

---

## Execution Order

1. ✅ **Bug 2 (pointer arithmetic)** - FIXED
2. 🔄 **Bug 1 (struct params)** - Next

---

## Progress Log

### Date: Feb 5, 2026

**Bug 2 FIXED** - Pointer Arithmetic

**Root Cause**: `lowerBinary` in `compiler/frontend/lower.zig` was generating a plain `.add` for pointer + integer without scaling by element size.

**Go Reference**: `rewritegeneric.go:24958` - `PtrIndex(ptr, idx)` → `AddPtr(ptr, Mul64(idx, Const64(elem_size)))`

**Fix** (lower.zig:1013-1029): When binary op is add/sub and left operand is pointer type:
- For `p + n`: Use `emitAddrIndex(p, n, elem_size)` which generates scaled addition
- For `p - n`: Use `emitAddrIndex(p, 0-n, elem_size)` (Wasm has no neg for integers)

```zig
// Pointer arithmetic: p + n scales by element size (like Go's PtrIndex)
if (bin.op == .add or bin.op == .sub) {
    const left_type = self.type_reg.get(self.inferExprType(bin.left));
    if (left_type == .pointer) {
        const elem_size = self.type_reg.sizeOf(left_type.pointer.elem);
        if (bin.op == .add) {
            return try fb.emitAddrIndex(left, right, elem_size, result_type, bin.span);
        } else {
            // p - n => addr_index(p, 0-n, elem_size)
            const zero = try fb.emitConstInt(0, right_type, bin.span);
            const neg_right = try fb.emitBinary(.sub, zero, right, right_type, bin.span);
            return try fb.emitAddrIndex(left, neg_right, elem_size, result_type, bin.span);
        }
    }
}
```

**Tests**:
- `p + 2` on `*i64` → returns `arr[2]` = 30 ✅
- `p - 2` on `*i64` → returns `arr[4-2]` = 30 ✅
- Works on both Wasm and Native targets ✅

---

## Checklist (from TROUBLESHOOTING.md)

Before making ANY change:

- [ ] I identified which pipeline stage has the bug
- [ ] I found the exact reference file for this stage
- [ ] I found the exact function in the reference
- [ ] I did a line-by-line comparison
- [ ] I found a difference between our code and reference
- [ ] My change copies the reference pattern exactly
- [ ] I did NOT invent any new logic

---

## Test Commands

```bash
# Test pointer arithmetic (Bug 2)
cat > /tmp/test_ptr.cot << 'EOF'
fn main() i64 {
    let arr = [10, 20, 30, 40, 50]
    let p = &arr[0]
    let p2 = p + 2
    return p2.*
}
EOF
./zig-out/bin/cot --target=wasm32 /tmp/test_ptr.cot -o /tmp/test_ptr.wasm
node -e 'const fs=require("fs"); const wasm=fs.readFileSync("/tmp/test_ptr.wasm"); WebAssembly.instantiate(wasm).then(r=>console.log(r.instance.exports.main()));'
# Expected: 30n

# Test struct params (Bug 1)
cat > /tmp/test_struct.cot << 'EOF'
struct Point { x: i64, y: i64 }
fn getX(p: Point) i64 { return p.x }
fn main() i64 {
    let p = Point { .x = 42, .y = 100 }
    return getX(p)
}
EOF
./zig-out/bin/cot --target=wasm32 /tmp/test_struct.cot -o /tmp/test_struct.wasm
node -e 'const fs=require("fs"); const wasm=fs.readFileSync("/tmp/test_struct.wasm"); WebAssembly.instantiate(wasm).then(r=>console.log(r.instance.exports.main()));'
# Expected: 42n
```
