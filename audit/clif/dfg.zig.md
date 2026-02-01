# dfg.zig - Cranelift Port Audit

## Cranelift Source

- **File**: `~/learning/wasmtime/cranelift/codegen/src/ir/dfg.rs`
- **File**: `~/learning/wasmtime/cranelift/codegen/src/ir/entities.rs`
- **Lines**: dfg.rs (~1884), entities.rs (~450)
- **Commit**: wasmtime main branch (January 2026)

## Coverage Summary

### Entity Types (from entities.rs)

| Cranelift | Cot | Status |
|-----------|-----|--------|
| `Block(u32)` | `Block` | ✅ |
| `Value(u32)` | `Value` | ✅ |
| `Inst(u32)` | `Inst` | ✅ |
| `StackSlot(u32)` | `StackSlot` | ✅ |
| `FuncRef(u32)` | `FuncRef` | ✅ |
| `SigRef(u32)` | `SigRef` | ✅ |
| `JumpTable(u32)` | `JumpTable` | ✅ |
| `DynamicStackSlot` | Not ported | ❌ Deferred |
| `DynamicType` | Not ported | ❌ Deferred |
| `GlobalValue` | Not ported | ❌ Deferred |
| `MemoryType` | Not ported | ❌ Deferred |

**Coverage**: 7/11 entity types (64%) - Essential types ported

### Entity Methods

| Cranelift | Cot | Status |
|-----------|-----|--------|
| `from_u32()` / `with_number()` | `fromIndex()` | ✅ |
| `as_u32()` | `asU32()` | ✅ |
| `reserved_value()` | `RESERVED` | ✅ |
| `Display::fmt()` | `format()` | ✅ |
| `PartialEq` | `eql()` | ✅ |

**Coverage**: 5/5 essential methods (100%)

### ValueList

| Cranelift | Cot | Status |
|-----------|-----|--------|
| `EntityList<Value>` | `ValueList` | ✅ |
| `ListPool<Value>` | `ValueListPool` | ✅ |
| `new()` | `init()` | ✅ |
| `push()` | `push()` | ✅ |
| `as_slice()` | `getSlice()` | ✅ |
| `len()` | `len()` | ✅ |
| `is_empty()` | `isEmpty()` | ✅ |

**Coverage**: 7/7 (100%)

### ValueDef (from dfg.rs)

| Cranelift | Cot | Status |
|-----------|-----|--------|
| `Result(Inst, usize)` | `result: {inst, num}` | ✅ |
| `Param(Block, usize)` | `param: {block, num}` | ✅ |
| `Union(Value, Value)` | Not ported | ❌ Deferred |
| `inst()` | `inst()` | ✅ |
| `unwrap_inst()` | `unwrapInst()` | ✅ |
| `unwrap_block()` | `block()` | ✅ |
| `num()` | `num()` | ✅ |

**Coverage**: 6/7 (86%)

### ValueData (from dfg.rs)

| Cranelift | Cot | Status |
|-----------|-----|--------|
| `Inst { ty, num, inst }` | Mapped to ValueDef.result | ✅ |
| `Param { ty, num, block }` | Mapped to ValueDef.param | ✅ |
| `Alias { ty, original }` | Mapped to ValueDef.alias | ✅ |
| `Union { ty, x, y }` | Not ported | ❌ Deferred |
| `ValueDataPacked` | Not ported (uses struct) | ✅ Simplified |

**Coverage**: 3/4 variants (75%)

### DataFlowGraph

| Cranelift | Cot | Status |
|-----------|-----|--------|
| `new()` | `init()` | ✅ |
| `clear()` | `clear()` | ✅ |
| `value_is_valid()` | `valueIsValid()` | ✅ |
| `value_type()` | `valueType()` | ✅ |
| `value_def()` | `valueDef()` | ✅ |
| `resolve_aliases()` | `resolveAliases()` | ✅ |
| `change_to_alias_of()` | `changeToAliasOf()` | ✅ |
| `make_block()` | `makeBlock()` | ✅ |
| `block_is_valid()` | `blockIsValid()` | ✅ |
| `num_block_params()` | `numBlockParams()` | ✅ |
| `block_params()` | `blockParams()` | ✅ |
| `append_block_param()` | `appendBlockParam()` | ✅ |
| `make_inst_results()` | `makeInstResult()` | ✅ |
| `inst_results()` | `instResults()` | ✅ |
| `first_result()` | `firstResult()` | ✅ |
| `num_values()` | Not ported | ❌ Deferred |
| `make_inst()` | Not ported (handled by builder) | ❌ |
| `display_inst()` | Not ported | ❌ Deferred |

**Coverage**: 15/~40 methods (essential subset)

## Tests Ported

| Test | Status |
|------|--------|
| Entity formatting | ✅ |
| Value list operations | ✅ |
| DFG basic operations | ✅ |
| Value aliasing | ✅ |

**Test Coverage**: 4/4 tests (100%)

## Differences from Cranelift

1. **No bit-packing**: Cranelift uses `ValueDataPacked` (64-bit packed) for efficiency. We use a simple struct for clarity.

2. **Simplified ValueList**: Cranelift uses power-of-two allocation pools. We use append-only allocation.

3. **No Union values**: The aegraph `Union` variant is not needed for MVP.

4. **Separate ValueData/ValueDef**: We merge them into one structure for simplicity.

5. **No secondary maps**: Cranelift uses `SecondaryMap` for sparse storage. We use dense arrays.

## Verification

- [x] All 4 unit tests pass
- [x] Entity formatting matches Cranelift (v0, block0, inst0, ss0, jt0)
- [x] Value list push/get operations work correctly
- [x] Block parameter tracking works correctly
- [x] Value aliasing and resolution works correctly
