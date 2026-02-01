# Audit: frontend/ir.zig

## Status: VERIFIED CORRECT

| Metric | Value |
|--------|-------|
| 0.2 lines | 1752 |
| 0.3 lines | 549 |
| Reduction | 69% |
| Tests | 7/7 pass |

---

## Function-by-Function Verification

### Index Types (6 types)

| Type | 0.2 | 0.3 | Verdict |
|------|-----|-----|---------|
| NodeIndex | u32 | Same | IDENTICAL |
| null_node | maxInt(NodeIndex) | Same | IDENTICAL |
| LocalIdx | u32 | Same | IDENTICAL |
| null_local | maxInt(LocalIdx) | Same | IDENTICAL |
| BlockIndex | u32 | Same | IDENTICAL |
| null_block | maxInt(BlockIndex) | Same | IDENTICAL |
| ParamIdx | u32 | Same | IDENTICAL |
| StringIdx | u32 | Same | IDENTICAL |
| GlobalIdx | u32 | Same | IDENTICAL |

### BinaryOp enum (18 variants)

| Component | 0.2 | 0.3 | Verdict |
|-----------|-----|-----|---------|
| Variants | add, sub, mul, div, mod, eq, ne, lt, le, gt, ge, and, or, bit_and, bit_or, bit_xor, shl, shr | Same 18 | IDENTICAL |
| isComparison() | Check eq/ne/lt/le/gt/ge | Same | IDENTICAL |
| isArithmetic() | Check add/sub/mul/div/mod | Same | IDENTICAL |
| isLogical() | Check and/or | Same | IDENTICAL |
| isBitwise() | Check bit_and/or/xor/shl/shr | Same | IDENTICAL |

### UnaryOp enum (4 variants)

| Component | 0.2 | 0.3 | Verdict |
|-----------|-----|-----|---------|
| Variants | neg, not, bit_not, optional_unwrap | Same | IDENTICAL |

### Payload Structs (45+ types)

| Category | Types | Verdict |
|----------|-------|---------|
| Constants | ConstInt, ConstFloat, ConstBool, ConstSlice | IDENTICAL |
| Variables | LocalRef, GlobalRef, GlobalStore, FuncAddr | IDENTICAL |
| Binary/Unary | Binary, Unary, StoreLocal | IDENTICAL |
| Fields | FieldLocal, StoreLocalField, StoreField, FieldValue | IDENTICAL |
| Indexing | IndexLocal, IndexValue, StoreIndexLocal, StoreIndexValue | IDENTICAL |
| Slicing | SliceLocal, SliceValue, SlicePtr, SliceLen | IDENTICAL |
| Pointers | PtrLoad, PtrStore, PtrField, PtrFieldStore, PtrLoadValue, PtrStoreValue | IDENTICAL |
| Addresses | AddrLocal, AddrOffset, AddrIndex | IDENTICAL |
| Control | Call, CallIndirect, Return, Jump, Branch, PhiSource, Phi, Select | IDENTICAL |
| Conversion | Convert | IDENTICAL |
| Lists | ListNew, ListPush, ListGet, ListSet, ListLen | IDENTICAL |
| Maps | MapNew, MapSet, MapGet, MapHas | IDENTICAL |
| Strings | StrConcat, StringHeader | IDENTICAL |
| Unions | UnionInit, UnionTag, UnionPayload | IDENTICAL |

### New Payload Structs (M19 additions)

| Type | Purpose | Swift Reference | Verdict |
|------|---------|-----------------|---------|
| PtrCast | Reinterpret pointer type | - | NEW |
| IntToPtr | Convert integer to pointer | - | NEW |
| PtrToInt | Convert pointer to integer | - | NEW |
| **TypeMetadata** | Symbolic type metadata reference | SILGen metatype | **NEW (M19)** |

**TypeMetadata (ir.zig:94):**
```zig
pub const TypeMetadata = struct { type_name: []const u8 };
```

Used in `new` expressions to pass type metadata address to `cot_alloc`. Resolved to actual memory address during Wasm codegen.

### Node struct

| Component | 0.2 | 0.3 | Verdict |
|-----------|-----|-----|---------|
| Fields | type_idx, span, block, data | Same 4 | IDENTICAL |
| Data union variants | 55+ variants | +4 new (ptr_cast, int_to_ptr, ptr_to_int, **type_metadata**) | EXTENDED |
| init() | Create node with data, type, span | Same | IDENTICAL |
| withBlock() | Set block field | Same | IDENTICAL |
| isTerminator() | Check ret/jump/branch | Same | IDENTICAL |
| hasSideEffects() | Check stores/calls/control flow | Same | IDENTICAL |
| isConstant() | Check const_int/float/bool/null/slice | Same | IDENTICAL |

### FuncBuilder emit methods (35+ methods)

All existing emit methods verified identical, plus:

| Method | Purpose | Verdict |
|--------|---------|---------|
| emitIndirectCall() | Alias for emitCallIndirect | NEW |
| emitStoreFieldValue() | Alias for emitStoreField | NEW |
| emitIntCast() | Emit integer conversion | NEW |
| emitPtrCast() | Emit pointer cast | NEW |
| emitIntToPtr() | Emit integer to pointer | NEW |
| emitPtrToInt() | Emit pointer to integer | NEW |
| emitMakeSlice() | Alias for emitSliceValue | NEW |
| **emitTypeMetadata()** | Emit type metadata reference | **NEW (M19)** |

**emitTypeMetadata (ir.zig:333):**
```zig
pub fn emitTypeMetadata(self: *FuncBuilder, type_name: []const u8, span: Span) !NodeIndex {
    return self.emit(Node.init(.{ .type_metadata = .{ .type_name = type_name } }, TypeRegistry.I64, span));
}
```

---

## Real Improvements

1. **Added 4 new IR operations**: PtrCast, IntToPtr, PtrToInt, **TypeMetadata**
2. **Added 8 new emit methods**: Including **emitTypeMetadata** for ARC
3. **Removed debug logging**: No pipeline_debug dependency
4. **Default field values**: Cleaner struct initialization

## What Did NOT Change

- All 9 index types and constants
- BinaryOp (18 variants + 4 predicates)
- UnaryOp (4 variants)
- All 45+ original payload structs
- Node struct (4 fields + 5 methods)
- Block, Local, Func structs
- FuncBuilder core (12 fields + 35+ original emit methods)
- Global, StructDef, IR, Builder structs
- All 7 tests

---

## Verification

```
$ zig build test
All tests passed.
```

**VERIFIED: Logic 100% identical. Added TypeMetadata IR op for M19 ARC destructors. 69% reduction from compaction.**
