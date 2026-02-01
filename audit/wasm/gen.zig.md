# Audit: wasm/gen.zig

## Status: WORKING - 75% PARITY

| Metric | Value |
|--------|-------|
| Lines | ~650 |
| Go Reference | cmd/compile/internal/wasm/ssa.go (595 lines) |
| Tests | 3 unit tests |

---

## M20 Update: Local Variable Offset Fix

### Bug: Multi-Variable String Offset Calculation

**Problem:** `len(s1) + len(s2)` returned wrong values (14 instead of 11) when both s1 and s2 were string variables.

**Root Cause:** Local variable offsets were calculated as `slot * 8`, but STRING is 16 bytes (ptr + len).

**Fix:** Added `getLocalOffset()` function to sum actual sizes from `local_sizes` array.

### New Function: getLocalOffset

**gen.zig (new function):**
```zig
fn getLocalOffset(self: *const GenState, local_idx: usize) i64 {
    // If no local_sizes available, fall back to 8-byte slots
    if (self.func.local_sizes.len == 0) {
        return @intCast(local_idx * 8);
    }

    // Sum actual sizes of all locals before this one
    var offset: i64 = 0;
    const count = @min(local_idx, self.func.local_sizes.len);
    for (0..count) |i| {
        offset += @intCast(self.func.local_sizes[i]);
    }
    return offset;
}
```

### Updated local_addr Handler

**Before (broken):**
```zig
.local_addr => {
    const slot = @intCast(v.aux_int);
    const offset = slot * 8;  // WRONG: assumes 8 bytes per slot
    // ...
},
```

**After (fixed):**
```zig
.local_addr => {
    _ = try self.builder.appendFrom(.get, prog_mod.regAddr(.sp));
    _ = try self.builder.append(.i64_extend_i32_u);
    const local_idx: usize = @intCast(v.aux_int);
    const offset = self.getLocalOffset(local_idx);  // Sum actual sizes
    if (offset != 0) {
        _ = try self.builder.appendFrom(.i64_const, prog_mod.constAddr(offset));
        _ = try self.builder.append(.i64_add);
    }
},
```

### Frame Layout Example

With two STRING variables (each 16 bytes):

| Variable | Slot | Old Offset (slot*8) | New Offset (sum sizes) |
|----------|------|---------------------|------------------------|
| s1.ptr | 0 | 0 | 0 |
| s1.len | 0 | 0+8 | 0+8 |
| s2.ptr | 1 | 8 ❌ | 16 ✅ |
| s2.len | 1 | 8+8 ❌ | 16+8 ✅ |

**Related:** See audit/TYPE_FLOW.md for full explanation of how STRING flows through the pipeline.

---

## M19 Update: metadata_addr and metadata_offsets

### New GenState Field

**gen.zig:78:**
```zig
/// Maps type names to metadata memory offsets
metadata_offsets: ?*const std.StringHashMap(i32) = null,
```

### New Method

**gen.zig:97-99:**
```zig
pub fn setMetadataOffsets(self: *GenState, offsets: *const std.StringHashMap(i32)) void {
    self.metadata_offsets = offsets;
}
```

### New Op Handler

**gen.zig:377-390:**
```zig
// Type metadata address (for ARC destructor lookup)
// Resolved at link time: metadata_offsets[type_name]
.metadata_addr => {
    const type_name = v.aux.string;
    if (self.metadata_offsets) |offsets| {
        if (offsets.get(type_name)) |offset| {
            _ = try self.builder.appendFrom(.i64_const, prog_mod.constAddr(offset));
        } else {
            // Type has no destructor - pass 0 (null metadata)
            _ = try self.builder.appendFrom(.i64_const, prog_mod.constAddr(0));
        }
    } else {
        // No metadata available - pass 0
        _ = try self.builder.appendFrom(.i64_const, prog_mod.constAddr(0));
    }
},
```

### Updated isRematerializable

**gen.zig:657:**
```zig
fn isRematerializable(v: *const SsaValue) bool {
    return switch (v.op) {
        .wasm_i64_const, .wasm_i32_const, .wasm_f64_const,
        .const_int, .const_32, .const_64, .const_float, .const_bool,
        .local_addr, .global_addr, .metadata_addr,  // metadata_addr added
        => true,
        else => false,
    };
}
```

---

## Go Reference Mapping

### Core Functions

| Go Function | Go Lines | Our Function | Our Lines | Parity |
|-------------|----------|--------------|-----------|--------|
| ssaGenValue | 217-311 | ssaGenValue | 156-240 | **GOOD** |
| ssaGenValueOnStack | 313-461 | ssaGenValueOnStack | 244-395 | **GOOD** |
| ssaGenBlock | 169-215 | ssaGenBlock | 400-470 | **GOOD** |
| getValue32 | 474-489 | getValue32 | 480-505 | **YES** |
| getValue64 | 491-503 | getValue64 | 510-530 | **YES** |
| setReg | 530-533 | setReg | 535-540 | **YES** |
| isCmp | 463-472 | isCmp | 550-565 | **YES** |

### ssaGenValueOnStack (Go: lines 313-461)

| Op Category | Go Lines | Our Lines | Parity |
|-------------|----------|-----------|--------|
| Constants | 370-377 | 249-263 | **YES** |
| Loads | 379-382 | 268-278 | **YES** |
| Binary i64 ops | 401-406 | 283-288 | **YES** |
| Comparisons | 391-399 | 293-304 | **YES** |
| Float ops | 402-406 | 309-319 | **YES** |
| Copy | 454-455 | 324-326 | **YES** |
| Arg | (in ssaGenValue) | 331-342 | **ADDED** |
| LocalAddr | (in ssaGenValue) | 347-365 | **ADDED** |
| GlobalAddr | (custom) | 368-373 | **ADDED** |
| **MetadataAddr** | N/A | 377-390 | **NEW (M19)** |
| OffPtr | (custom) | 393-405 | **ADDED** |

---

## metadata_addr Pattern

The `metadata_addr` op follows the same pattern as `global_addr`:

| Op | aux.string | Resolution | Emit |
|----|------------|------------|------|
| global_addr | variable name | GLOBAL_BASE + idx*8 | i64.const |
| metadata_addr | type name | metadata_offsets lookup | i64.const |

**Swift Reference (IRGenModule.cpp):**
```cpp
llvm::Constant *IRGenModule::getAddrOfTypeMetadata(CanType type) {
  return getAddrOfTypeMetadataRecord(type)->getValue();
}
```

---

## Op to Instruction Mapping

| SSA Op | Go Instruction | Our Instruction | Parity |
|--------|---------------|-----------------|--------|
| wasm_i64_add | AI64Add | .i64_add | **YES** |
| wasm_i64_sub | AI64Sub | .i64_sub | **YES** |
| wasm_i64_mul | AI64Mul | .i64_mul | **YES** |
| wasm_i64_div_s | AI64DivS | .i64_div_s | **YES** |
| wasm_i64_rem_s | AI64RemS | .i64_rem_s | **YES** |
| wasm_i64_and | AI64And | .i64_and | **YES** |
| wasm_i64_or | AI64Or | .i64_or | **YES** |
| wasm_i64_xor | AI64Xor | .i64_xor | **YES** |
| wasm_i64_shl | AI64Shl | .i64_shl | **YES** |
| wasm_i64_shr_s | AI64ShrS | .i64_shr_s | **YES** |
| wasm_i64_shr_u | AI64ShrU | .i64_shr_u | **YES** |
| wasm_i64_eq | AI64Eq | .i64_eq | **YES** |
| wasm_i64_ne | AI64Ne | .i64_ne | **YES** |
| wasm_i64_lt_s | AI64LtS | .i64_lt_s | **YES** |
| wasm_i64_le_s | AI64LeS | .i64_le_s | **YES** |
| wasm_i64_gt_s | AI64GtS | .i64_gt_s | **YES** |
| wasm_i64_ge_s | AI64GeS | .i64_ge_s | **YES** |
| local_addr | - | SP offset calc | **ADDED** |
| global_addr | - | GLOBAL_BASE + idx | **ADDED** |
| **metadata_addr** | - | **metadata lookup** | **NEW (M19)** |
| off_ptr | - | i64.const + i64.add | **ADDED** |
| add_ptr | - | mul + i64.add | **ADDED** |

---

## generateFunc Signature Update

**wasm.zig:71-76 (before M19):**
```zig
pub fn generateFunc(
    allocator: std.mem.Allocator,
    ssa_func: *const SsaFunc,
    func_indices: ?*const FuncIndexMap,
    string_offsets: ?*const StringOffsetMap,
) ![]u8
```

**wasm.zig:71-77 (after M19):**
```zig
pub fn generateFunc(
    allocator: std.mem.Allocator,
    ssa_func: *const SsaFunc,
    func_indices: ?*const FuncIndexMap,
    string_offsets: ?*const StringOffsetMap,
    metadata_offsets: ?*const StringOffsetMap,  // NEW
) ![]u8
```

---

## What's Not Implemented

| Feature | Go Lines | Status | Reason |
|---------|----------|--------|--------|
| ClosureCall | 223-231 | **SKIPPED** | No closures |
| InterCall | 234-243 | **SKIPPED** | No interfaces |
| WB (write barrier) | 274-278 | **SKIPPED** | No GC |
| Select | 286-293 | **FUTURE** | Conditional move |
| Convert ops | 407-449 | **FUTURE** | Type conversions |

---

## Verification

```bash
$ zig build test
All tests passed.

$ ./zig-out/bin/cot --target=wasm32 test/cases/arc/destructor_called.cot -o /tmp/dtor.wasm
$ node -e '...'
Result: 99n  # Destructor called via metadata lookup
```

**VERDICT: 75% parity. Core value/block generation matches Go. Added metadata_addr for M19 ARC destructors. Advanced ops (closures, interfaces, GC) not yet implemented.**
