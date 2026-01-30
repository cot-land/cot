# Audit: src/ssa/test_helpers.zig

## Line Count Comparison

| Version | Lines | Reduction |
|---------|-------|-----------|
| 0.2     | 360   | -         |
| 0.3     | 165   | 54.2%     |

## Structural Changes

### 0.2 Architecture
The 0.2 version provided extensive test infrastructure:

1. **DiamondCFG struct** (8 lines) - result of createDiamondCFG
2. **LinearCFG struct** (5 lines) - result of createLinearCFG
3. **TestFuncBuilder** (135 lines):
   - init() - create new function
   - withFunc() - wrap existing function
   - deinit() - cleanup
   - createDiamondCFG() - if-then-else-merge pattern
   - createDiamondWithPhi() - diamond with phi nodes
   - createLinearCFG() - sequential blocks
   - addConst() - add constant value
   - addBinOp() - add binary operation
4. **validateInvariants** (40 lines) - check SSA invariants
5. **validateUseCounts** (47 lines) - verify use count consistency
6. **freeErrors** (4 lines) - cleanup helper
7. **Tests** (60 lines)

Extensive doc comments explaining each fixture.

### 0.3 Architecture
The 0.3 version is significantly more compact:

1. **DiamondCFG struct** (1 line) - single-line struct
2. **LinearCFG struct** (1 line) - single-line struct
3. **TestFuncBuilder** (52 lines):
   - init, deinit
   - createDiamondCFG, createDiamondWithPhi
   - createLinearCFG
   - addConst
4. **validateInvariants** (8 lines)
5. **validateUseCounts** (18 lines)
6. **VerifyError struct** (1 line)
7. **freeErrors** (1 line)
8. **Tests** (42 lines)

## Function-by-Function Comparison

### TestFuncBuilder Methods
| Method | 0.2 Lines | 0.3 Lines | Change |
|--------|-----------|-----------|--------|
| init | 9 | 4 | Condensed |
| withFunc | 6 | N/A | Removed |
| deinit | 7 | 5 | Condensed |
| createDiamondCFG | 28 | 17 | Condensed |
| createDiamondWithPhi | 20 | 18 | Minimal change |
| createLinearCFG | 22 | 6 | Much more compact |
| addConst | 7 | 6 | Minimal change |
| addBinOp | 8 | N/A | Removed |

### Validation Functions
| Function | 0.2 Lines | 0.3 Lines | Change |
|----------|-----------|-----------|--------|
| validateInvariants | 40 | 8 | Greatly simplified |
| validateUseCounts | 47 | 18 | Condensed |
| freeErrors | 4 | 1 | Single line |

## Why the Refactor Improves the Code

### 1. Removed Unused Features

**withFunc()** - Never used in tests. If needed, tests create their own Func.

**addBinOp()** - Never used. Tests that need binary ops can create them directly.

### 2. Compact Struct Definitions

**0.2:**
```zig
pub const DiamondCFG = struct {
    entry: *Block,
    then_block: *Block,
    else_block: *Block,
    merge: *Block,
    /// Condition value in entry block
    condition: *Value,
    /// Phi node in merge block (if created)
    phi: ?*Value,
};
```

**0.3:**
```zig
pub const DiamondCFG = struct { entry: *Block, then_block: *Block, else_block: *Block, merge: *Block, condition: *Value, phi: ?*Value };
```

### 3. Simplified Validation

The 0.2 validateInvariants created detailed error messages with allocPrint. The 0.3 version uses simpler fixed error messages - for test helpers, you mainly care whether there ARE errors, not the exact wording.

**0.2:**
```zig
if (v.block != b) {
    try errors_list.append(allocator, .{
        .message = "value block pointer mismatch",
        .block_id = b.id,
        .value_id = v.id,
    });
}
```

**0.3:**
```zig
if (v.block != b) try errs.append(allocator, .{ .message = "value block mismatch", .block_id = b.id, .value_id = v.id });
```

### 4. Local VerifyError Type

The 0.2 version imported VerifyError from `../core/errors.zig`. The 0.3 version defines a simple local struct, avoiding the dependency:

```zig
pub const VerifyError = struct { message: []const u8, block_id: ID = 0, value_id: ID = 0 };
```

### 5. Streamlined createLinearCFG

**0.2 (22 lines):**
```zig
pub fn createLinearCFG(self: *TestFuncBuilder, count: usize) !LinearCFG {
    if (count == 0) return error.InvalidCount;

    var blocks = try self.allocator.alloc(*Block, count);

    // Create blocks
    for (0..count) |i| {
        const kind: BlockKind = if (i == count - 1) .ret else .plain;
        blocks[i] = try self.func.newBlock(kind);
    }

    // Connect edges
    for (0..count - 1) |i| {
        try blocks[i].addEdgeTo(self.allocator, blocks[i + 1]);
    }

    return .{
        .blocks = blocks,
        .entry = blocks[0],
        .exit = blocks[count - 1],
    };
}
```

**0.3 (6 lines):**
```zig
pub fn createLinearCFG(self: *TestFuncBuilder, count: usize) !LinearCFG {
    if (count == 0) return error.InvalidCount;
    var blocks = try self.allocator.alloc(*Block, count);
    for (0..count) |i| blocks[i] = try self.func.newBlock(if (i == count - 1) .ret else .plain);
    for (0..count - 1) |i| try blocks[i].addEdgeTo(self.allocator, blocks[i + 1]);
    return .{ .blocks = blocks, .entry = blocks[0], .exit = blocks[count - 1] };
}
```

## Behavioral Differences

### withFunc Removed
Code that called `TestFuncBuilder.withFunc(existing_func)` would need to be updated. No existing tests used this.

### addBinOp Removed
Code that called `builder.addBinOp(block, .add, left, right)` would need to create the value directly. No existing tests used this.

### ID Import
- **0.2**: Imports ID from `../core/types.zig`
- **0.3**: Imports ID from `../value.zig` (value.zig re-exports it)

### VerifyError Type
- **0.2**: Imported from `../core/errors.zig`
- **0.3**: Defined locally as a simple struct

## Fixes Included

1. **Removed unused withFunc()**: Code bloat
2. **Removed unused addBinOp()**: Code bloat
3. **Simplified error type**: No need for external dependency
4. **Better test focus**: Tests are more targeted and less verbose
