# jumptable.zig - Cranelift Port Audit

## Cranelift Source

- **File**: `~/learning/wasmtime/cranelift/codegen/src/ir/jumptable.rs`
- **File**: `~/learning/wasmtime/cranelift/codegen/src/ir/instructions.rs` (BlockCall)
- **Lines**: jumptable.rs (~176), BlockCall section (~100)
- **Commit**: wasmtime main branch (January 2026)

## Coverage Summary

### BlockCall (from instructions.rs)

| Cranelift | Cot | Status |
|-----------|-----|--------|
| `values: EntityList<Value>` | `block: Block, args: ValueList` | ✅ Simplified |
| `new()` | `init()`, `withArgs()`, `withArgsSlice()` | ✅ |
| `block()` | `getBlock()` | ✅ |
| `set_block()` | Not ported | ❌ Deferred |
| `append_argument()` | Not ported | ❌ Deferred |
| `len()` | `argLen()` | ✅ |
| `args()` | `getArgs()` | ✅ |
| `update_args()` | Not ported | ❌ Deferred |
| `remove()` | Not ported | ❌ Deferred |
| `clear()` | Not ported | ❌ Deferred |
| `extend()` | Not ported | ❌ Deferred |
| `display()` | `format()` | ✅ Simplified |

**Coverage**: 6/11 methods (55%)

### JumpTableData (from jumptable.rs)

| Cranelift | Cot | Status |
|-----------|-----|--------|
| `table: Vec<BlockCall>` | `default_block: BlockCall, entries: ArrayList` | ✅ Split |
| `new()` | `init()`, `initWithEntries()` | ✅ |
| `default_block()` | `getDefaultBlock()` | ✅ |
| `default_block_mut()` | `setDefaultBlock()` | ✅ |
| `all_branches()` | `allBranches()` | ✅ |
| `all_branches_mut()` | Not ported | ❌ Deferred |
| `as_slice()` | `asSlice()` | ✅ |
| `as_mut_slice()` | `asMutSlice()` | ✅ |
| `iter()` | Deprecated in Cranelift | ❌ |
| `iter_mut()` | Deprecated in Cranelift | ❌ |
| `clear()` | `clear()` | ✅ |
| `display()` | Not ported | ❌ Deferred |

**Coverage**: 8/12 methods (67%)

### JumpTables Collection (new)

| Cranelift | Cot | Status |
|-----------|-----|--------|
| `PrimaryMap<JumpTable, JumpTableData>` | `JumpTables` struct | ✅ |
| `push()` | `create()` | ✅ |
| `get()` | `get()` | ✅ |
| `get_mut()` | `getMut()` | ✅ |
| `len()` | `len()` | ✅ |
| `clear()` | `clear()` | ✅ |

**Coverage**: 6/6 methods (100%)

### Additional Features

| Feature | Status |
|---------|--------|
| `get()` by index | ✅ |
| `push()` entry | ✅ |
| `len()` | ✅ |
| `isEmpty()` | ✅ |
| `AllBranchesIterator` | ✅ |

## Tests Ported

| Test | Status |
|------|--------|
| `block call creation` | ✅ |
| `jump table empty` | ✅ |
| `jump table with entries` | ✅ |
| `jump tables collection` | ✅ |

**Test Coverage**: 4/4 tests (100%)

## Differences from Cranelift

1. **BlockCall simplified**: Cranelift encodes the block as a Value in the first element of a ValueList. We store block and args separately for clarity.

2. **Separate default block**: Cranelift stores default as first element of the table Vec. We store it as a separate field for clarity.

3. **No BlockArg encoding**: Cranelift uses BlockArg (Value or Blockparam) encoded as Value. We use plain Value for arguments.

4. **JumpTables wrapper**: We added a JumpTables struct to manage the collection, similar to Cranelift's PrimaryMap usage.

5. **No display()**: Jump table display formatting not ported (needs ValueListPool access).

## Verification

- [x] All 4 unit tests pass
- [x] Empty jump table works correctly
- [x] Jump table with entries works correctly
- [x] AllBranches iterator returns default first, then entries
- [x] JumpTables collection manages multiple tables
- [x] Total: 16 tests pass (including imported modules)
