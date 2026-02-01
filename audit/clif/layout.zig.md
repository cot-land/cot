# layout.zig - Cranelift Port Audit

## Cranelift Source

- **File**: `~/learning/wasmtime/cranelift/codegen/src/ir/layout.rs`
- **Lines**: ~1196
- **Commit**: wasmtime main branch (January 2026)

## Coverage Summary

### SequenceNumber

| Cranelift | Cot | Status |
|-----------|-----|--------|
| `SequenceNumber (u32)` | `SequenceNumber (u32)` | ✅ |
| `MAJOR_STRIDE = 10` | `MAJOR_STRIDE = 10` | ✅ |
| `MINOR_STRIDE = 2` | `MINOR_STRIDE = 2` | ✅ |
| `midpoint()` | `midpoint()` | ✅ |

**Coverage**: 4/4 (100%)

### BlockNode

| Cranelift | Cot | Status |
|-----------|-----|--------|
| `prev: PackedOption<Block>` | `prev: ?Block` | ✅ |
| `next: PackedOption<Block>` | `next: ?Block` | ✅ |
| `first_inst: PackedOption<Inst>` | `first_inst: ?Inst` | ✅ |
| `last_inst: PackedOption<Inst>` | `last_inst: ?Inst` | ✅ |
| `cold: bool` | `cold: bool` | ✅ |
| `seq: SequenceNumber` | `seq: SequenceNumber` | ✅ |

**Coverage**: 6/6 fields (100%)

### InstNode

| Cranelift | Cot | Status |
|-----------|-----|--------|
| `block: PackedOption<Block>` | `block: ?Block` | ✅ |
| `prev: PackedOption<Inst>` | `prev: ?Inst` | ✅ |
| `next: PackedOption<Inst>` | `next: ?Inst` | ✅ |
| `seq: SequenceNumber` | `seq: SequenceNumber` | ✅ |

**Coverage**: 4/4 fields (100%)

### Layout

| Cranelift | Cot | Status |
|-----------|-----|--------|
| `blocks: SecondaryMap<Block, BlockNode>` | `block_nodes: ArrayListUnmanaged(BlockNode)` | ✅ |
| `insts: SecondaryMap<Inst, InstNode>` | `inst_nodes: ArrayListUnmanaged(InstNode)` | ✅ |
| `first_block: Option<Block>` | `first_block: ?Block` | ✅ |
| `last_block: Option<Block>` | `last_block: ?Block` | ✅ |

**Coverage**: 4/4 fields (100%)

### Layout Methods - Block Operations

| Cranelift | Cot | Status |
|-----------|-----|--------|
| `new()` | `init()` | ✅ |
| `clear()` | `clear()` | ✅ |
| `entry_block()` | `entryBlock()` | ✅ |
| `last_block()` | `lastBlock()` | ✅ |
| `is_block_inserted()` | `isBlockInserted()` | ✅ |
| `append_block()` | `appendBlock()` | ✅ |
| `insert_block()` | `insertBlock()` | ✅ |
| `insert_block_after()` | `insertBlockAfter()` | ✅ |
| `remove_block()` | `removeBlock()` | ✅ |
| `next_block()` | `nextBlock()` | ✅ |
| `prev_block()` | `prevBlock()` | ✅ |
| `blocks()` (iterator) | `blocks()` | ✅ |
| `set_block_cold()` | `setBlockCold()` | ✅ |
| `is_block_cold()` | `isBlockCold()` | ✅ |

**Coverage**: 14/14 methods (100%)

### Layout Methods - Instruction Operations

| Cranelift | Cot | Status |
|-----------|-----|--------|
| `is_inst_inserted()` | `isInstInserted()` | ✅ |
| `inst_block()` | `instBlock()` | ✅ |
| `append_inst()` | `appendInst()` | ✅ |
| `insert_inst()` | `insertInst()` | ✅ |
| `remove_inst()` | `removeInst()` | ✅ |
| `next_inst()` | `nextInst()` | ✅ |
| `prev_inst()` | `prevInst()` | ✅ |
| `first_inst()` | `firstInst()` | ✅ |
| `last_inst()` | `lastInst()` | ✅ |
| `block_insts()` (iterator) | `blockInsts()` | ✅ |

**Coverage**: 10/10 methods (100%)

### Layout Methods - Program Point Comparison

| Cranelift | Cot | Status |
|-----------|-----|--------|
| `pp_cmp()` (Block, Block) | `ppCmpBlock()` | ✅ |
| `pp_cmp()` (Block, Inst) | `ppCmpBlockInst()` | ✅ |
| `pp_cmp()` (Inst, Inst) | `ppCmpInst()` | ✅ |

**Coverage**: 3/3 methods (100%)

### Layout Methods - Block Splitting

| Cranelift | Cot | Status |
|-----------|-----|--------|
| `split_block()` | `splitBlock()` | ✅ |

**Coverage**: 1/1 methods (100%)

### Iterators

| Cranelift | Cot | Status |
|-----------|-----|--------|
| `Blocks` iterator | `BlockIterator` | ✅ |
| `Blocks::next()` | `BlockIterator.next()` | ✅ |
| `Blocks::next_back()` | `BlockIterator.nextBack()` | ✅ |
| `Insts` iterator | `InstIterator` | ✅ |
| `Insts::next()` | `InstIterator.next()` | ✅ |
| `Insts::next_back()` | `InstIterator.nextBack()` | ✅ |

**Coverage**: 6/6 (100%)

## Tests Ported

| Test | Status |
|------|--------|
| `test_midpoint` | ✅ |
| `append_block` | ✅ |
| `insert_block` | ✅ |
| `append_inst` | ✅ |
| `insert_inst` | ✅ |
| `remove_inst` | ✅ |
| `multiple_blocks` | ✅ |
| `split_block` | ✅ |
| `pp_cmp` | ✅ |

**Test Coverage**: 9/9 tests (100%)

## Differences from Cranelift

1. **No SecondaryMap**: Cranelift uses `SecondaryMap<K, V>` for sparse storage. We use `ArrayListUnmanaged` for simplicity.

2. **No PackedOption**: Cranelift packs Option<Entity> into u32 with sentinel values. We use Zig's native `?T` optional.

3. **No Cursor integration**: Cranelift has tight integration with `Cursor` trait for navigation. We expose direct methods instead.

4. **Simplified pp_cmp**: Cranelift has a unified `pp_cmp` that works with `ProgramPoint` enum. We have separate methods for different comparisons.

5. **No serde**: Serialization not needed.

6. **No renumbering**: Cranelift has `full_block_renumber()` for when sequence numbers run out. We simplified to saturating arithmetic.

## Verification

- [x] All 9 unit tests pass
- [x] Block append/insert/remove operations work correctly
- [x] Instruction append/insert/remove operations work correctly
- [x] Block splitting works correctly
- [x] Program point comparison works correctly
- [x] Iterators support both forward and backward traversal
