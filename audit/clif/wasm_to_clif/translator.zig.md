# translator.zig - Cranelift Port Audit

## Cranelift Source

- **File**: `~/learning/wasmtime/crates/cranelift/src/translate/code_translator.rs`
- **Lines**: 1-3400+
- **Commit**: wasmtime main branch (February 2026)

## Coverage Summary

### Control Flow Instructions

| Cranelift | Cot | Status |
|-----------|-----|--------|
| `Operator::Block` | `translateBlock()` | ✅ |
| `Operator::Loop` | `translateLoop()` | ✅ |
| `Operator::If` | `translateIf()` | ✅ |
| `Operator::Else` | `translateElse()` | ✅ |
| `Operator::End` | `translateEnd()` | ✅ |
| `Operator::Br` | `translateBr()` | ✅ |
| `Operator::BrIf` | `translateBrIf()` | ✅ |
| `Operator::BrTable` | `translateBrTable()` | ✅ CRITICAL |
| `Operator::Return` | `translateReturn()` | ✅ |
| `Operator::Unreachable` | Not ported | ❌ Deferred |
| `Operator::Call` | Not ported | ❌ Deferred |
| `Operator::CallIndirect` | Not ported | ❌ Deferred |

**Coverage**: 9/12 control flow instructions (75%)

### Variable Instructions

| Cranelift | Cot | Status |
|-----------|-----|--------|
| `Operator::LocalGet` | `translateLocalGet()` | ✅ |
| `Operator::LocalSet` | `translateLocalSet()` | ✅ |
| `Operator::LocalTee` | `translateLocalTee()` | ✅ |
| `Operator::GlobalGet` | Not ported | ❌ Deferred |
| `Operator::GlobalSet` | Not ported | ❌ Deferred |

**Coverage**: 3/5 variable instructions (60%)

### Constant Instructions

| Cranelift | Cot | Status |
|-----------|-----|--------|
| `Operator::I32Const` | `translateI32Const()` | ✅ |
| `Operator::I64Const` | `translateI64Const()` | ✅ |
| `Operator::F32Const` | Not ported | ❌ Deferred |
| `Operator::F64Const` | Not ported | ❌ Deferred |

**Coverage**: 2/4 constant instructions (50%)

### Binary Arithmetic (i32)

| Cranelift | Cot | Status |
|-----------|-----|--------|
| `Operator::I32Add` | `translateI32Add()` | ✅ |
| `Operator::I32Sub` | `translateI32Sub()` | ✅ |
| `Operator::I32Mul` | `translateI32Mul()` | ✅ |
| `Operator::I32DivS` | `translateI32DivS()` | ✅ |
| `Operator::I32DivU` | `translateI32DivU()` | ✅ |
| `Operator::I32RemS` | `translateI32RemS()` | ✅ |
| `Operator::I32RemU` | `translateI32RemU()` | ✅ |
| `Operator::I32And` | `translateI32And()` | ✅ |
| `Operator::I32Or` | `translateI32Or()` | ✅ |
| `Operator::I32Xor` | `translateI32Xor()` | ✅ |
| `Operator::I32Shl` | `translateI32Shl()` | ✅ |
| `Operator::I32ShrS` | `translateI32ShrS()` | ✅ |
| `Operator::I32ShrU` | `translateI32ShrU()` | ✅ |
| `Operator::I32Rotl` | `translateI32Rotl()` | ✅ |
| `Operator::I32Rotr` | `translateI32Rotr()` | ✅ |

**Coverage**: 15/15 i32 binary arithmetic (100%)

### Comparison Instructions (i32)

| Cranelift | Cot | Status |
|-----------|-----|--------|
| `Operator::I32Eqz` | `translateI32Eqz()` | ✅ |
| `Operator::I32Eq` | `translateI32Eq()` | ✅ |
| `Operator::I32Ne` | `translateI32Ne()` | ✅ |
| `Operator::I32LtS` | `translateI32LtS()` | ✅ |
| `Operator::I32LtU` | `translateI32LtU()` | ✅ |
| `Operator::I32GtS` | `translateI32GtS()` | ✅ |
| `Operator::I32GtU` | `translateI32GtU()` | ✅ |
| `Operator::I32LeS` | `translateI32LeS()` | ✅ |
| `Operator::I32LeU` | `translateI32LeU()` | ✅ |
| `Operator::I32GeS` | `translateI32GeS()` | ✅ |
| `Operator::I32GeU` | `translateI32GeU()` | ✅ |

**Coverage**: 11/11 i32 comparisons (100%)

### Conversion Instructions

| Cranelift | Cot | Status |
|-----------|-----|--------|
| `Operator::I32WrapI64` | `translateI32WrapI64()` | ✅ |
| `Operator::I64ExtendI32S` | `translateI64ExtendI32S()` | ✅ |
| `Operator::I64ExtendI32U` | `translateI64ExtendI32U()` | ✅ |
| Float conversions | Not ported | ❌ Deferred |

**Coverage**: 3/10+ conversions (30%)

### Parametric Instructions

| Cranelift | Cot | Status |
|-----------|-----|--------|
| `Operator::Drop` | `translateDrop()` | ✅ |
| `Operator::Select` | `translateSelect()` | ✅ |

**Coverage**: 2/2 parametric (100%)

### Memory Instructions

| Cranelift | Cot | Status |
|-----------|-----|--------|
| All load/store instructions | Not ported | ❌ Deferred |

**Coverage**: 0/20+ memory (0%) - Deferred for MVP

### SIMD Instructions

| Cranelift | Cot | Status |
|-----------|-----|--------|
| All SIMD instructions | Not ported | ❌ Deferred |

**Coverage**: 0/100+ SIMD (0%) - Deferred for MVP

## Tests Ported

| Test | Status |
|------|--------|
| `translate i32.const and i32.add` | ✅ |
| `translate block and end` | ✅ |
| `translate loop - br_destination is header` | ✅ CRITICAL |
| `translate br` | ✅ |
| `translate local.get and local.set` | ✅ |
| `translate br_table simple (no args)` | ✅ |
| `translate comparison` | ✅ |

**Test Coverage**: 7/7 tests (100%)

## Critical Algorithm: br_table with Edge Splitting

The most critical algorithm is `translateBrTable()`. Cranelift's br_table instruction does not support jump arguments, so when targets have arguments, we need edge splitting.

**Cranelift** (code_translator.rs:485-569):
```rust
Operator::BrTable { targets } => {
    // 1. Find minimum depth to determine jump args count
    let mut min_depth = default;
    for depth in targets.targets() {
        if depth < min_depth { min_depth = depth; }
    }

    // 2. Get return count from min depth frame
    let jump_args_count = if frame.is_loop() {
        frame.num_param_values()
    } else {
        frame.num_return_values()
    };

    // 3a. Simple case (no args): direct br_table
    if jump_args_count == 0 {
        builder.ins().br_table(val, jt);
    } else {
        // 3b. Edge splitting: create intermediate blocks
        let mut dest_block_map = HashMap::new();
        for depth in targets {
            let intermediate = *dest_block_map
                .entry(depth)
                .or_insert_with(|| builder.create_block());
        }
        builder.ins().br_table(val, jt);

        // Fill intermediates with jumps to real targets
        for (depth, intermediate) in dest_block_sequence {
            builder.switch_to_block(intermediate);
            let real_dest = frame.br_destination();
            builder.ins().jump(real_dest, args);
        }
    }
}
```

**Cot** (translator.zig:500-560):
```zig
pub fn translateBrTable(self: *Self, targets: []const u32, default: u32) !void {
    const val = self.state.pop1();

    // 1. Find minimum depth
    var min_depth = default;
    for (targets) |depth| {
        if (depth < min_depth) min_depth = depth;
    }

    // 2. Get return count
    const min_depth_frame = self.state.getFrame(min_depth);
    const jump_args_count = if (min_depth_frame.isLoop())
        min_depth_frame.numParamValues()
    else
        min_depth_frame.numReturnValues();

    if (jump_args_count == 0) {
        // Simple case
        try self.emitVoid(.br_table, ...);
    } else {
        // Edge splitting
        var dest_block_map = std.AutoHashMap(u32, Block).init(self.allocator);
        // ... create intermediates and emit jumps
    }
}
```

## Differences from Cranelift

1. **Simplified instruction emission**: We record instructions to an ArrayList for testing/debugging rather than directly building CLIF IR. This will be replaced with actual CLIF builder calls.

2. **No SIMD bitcasting**: Cranelift handles SIMD type canonicalization (converting all vector types to I8X16). We defer SIMD support.

3. **No FunctionBuilder integration**: Cranelift uses cranelift_frontend's FunctionBuilder for SSA variable handling. We store locals directly.

4. **No validation**: Cranelift integrates with wasmparser's FuncValidator. We assume valid Wasm input.

5. **Memory operations deferred**: All load/store operations require heap and memory management, deferred for MVP.

6. **No exception handling**: try_table, throw, catch not ported.

## Verification

- [x] All 7 translator tests pass
- [x] All 7 stack tests pass (14 total)
- [x] Block/loop/if control flow works
- [x] br_destination returns header for loops (CRITICAL)
- [x] br_table edge splitting implemented
- [x] Local variable get/set/tee works
- [x] Binary arithmetic translation works
- [x] Comparison translation works with IntCC

## Integration Notes

When integrating with the full CLIF IR:

1. Replace `EmittedInst` recording with actual `FuncBuilder` calls
2. Connect to CLIF's `DataFlowGraph` for value/block allocation
3. Add type tracking for proper CLIF type annotations
4. Add memory operations (load, store) with heap access
5. Add call/call_indirect with function signature handling
