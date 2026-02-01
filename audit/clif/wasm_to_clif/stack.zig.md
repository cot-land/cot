# stack.zig - Cranelift Port Audit

## Cranelift Source

- **File**: `~/learning/wasmtime/crates/cranelift/src/translate/stack.rs`
- **Lines**: 1-623
- **Commit**: wasmtime main branch (February 2026)

## Coverage Summary

### ElseData

| Cranelift | Cot | Status |
|-----------|-----|--------|
| `NoElse { branch_inst, placeholder }` | `no_else { branch_inst, placeholder }` | ✅ |
| `WithElse { else_block }` | `with_else { else_block }` | ✅ |

**Coverage**: 2/2 variants (100%)

### ControlStackFrame

| Cranelift | Cot | Status |
|-----------|-----|--------|
| `If { destination, else_data, num_param_values, num_return_values, original_stack_size, exit_is_branched_to, blocktype, head_is_reachable, consequent_ends_reachable }` | `if_frame { ... }` | ✅ (blocktype omitted) |
| `Block { destination, num_param_values, num_return_values, original_stack_size, exit_is_branched_to, try_table_info }` | `block_frame { ... }` | ✅ (try_table_info omitted) |
| `Loop { destination, header, num_param_values, num_return_values, original_stack_size }` | `loop_frame { ... }` | ✅ |

**Coverage**: 3/3 variants (100%)

### ControlStackFrame Methods

| Cranelift | Cot | Status |
|-----------|-----|--------|
| `num_return_values()` | `numReturnValues()` | ✅ |
| `num_param_values()` | `numParamValues()` | ✅ |
| `following_code()` | `followingCode()` | ✅ |
| `br_destination()` | `brDestination()` | ✅ CRITICAL |
| `original_stack_size()` | `originalStackSize()` | ✅ |
| `is_loop()` | `isLoop()` | ✅ |
| `exit_is_branched_to()` | `exitIsBranchedTo()` | ✅ |
| `set_branched_to_exit()` | `setBranchedToExit()` | ✅ |
| `truncate_value_stack_to_else_params()` | `truncateValueStackToElseParams()` | ✅ |
| `truncate_value_stack_to_original_size()` | `truncateValueStackToOriginalSize()` | ✅ |
| `restore_catch_handlers()` | Not ported | ❌ Deferred (exception handling) |

**Coverage**: 10/11 methods (91%)

### FuncTranslationStacks (→ TranslationState)

| Cranelift | Cot | Status |
|-----------|-----|--------|
| `stack: Vec<Value>` | `stack: ArrayListUnmanaged(Value)` | ✅ |
| `stack_shape: Vec<FrameStackShape>` | Not ported | ❌ Deferred (debug instrumentation) |
| `control_stack: Vec<ControlStackFrame>` | `control_stack: ArrayListUnmanaged(ControlStackFrame)` | ✅ |
| `handlers: HandlerState` | Not ported | ❌ Deferred (exception handling) |
| `reachable: bool` | `reachable: bool` | ✅ |

**Coverage**: 3/5 fields (60%)

### FuncTranslationStacks Methods

| Cranelift | Cot | Status |
|-----------|-----|--------|
| `new()` | `init()` | ✅ |
| `clear()` | `clear()` | ✅ |
| `initialize()` | `initialize()` | ✅ |
| `reachable()` | `isReachable()` | ✅ |
| `push1()` | `push1()` | ✅ |
| `push2()` | `push2()` | ✅ |
| `pushn()` | `pushn()` | ✅ |
| `pop1()` | `pop1()` | ✅ |
| `peek1()` | `peek1()` | ✅ |
| `pop2()` | `pop2()` | ✅ |
| `pop3()` | `pop3()` | ✅ |
| `pop4()` | Not ported | ❌ Deferred |
| `pop5()` | Not ported | ❌ Deferred |
| `popn()` | `popn()` | ✅ |
| `peekn()` | `peekn()` | ✅ |
| `peekn_mut()` | `peeknMut()` | ✅ |
| `push_block()` | `pushBlock()` | ✅ |
| `push_try_table_block()` | Not ported | ❌ Deferred (exception handling) |
| `push_loop()` | `pushLoop()` | ✅ |
| `push_if()` | `pushIf()` | ✅ |
| `assert_debug_stack_is_synced()` | Not ported | ❌ Deferred (debug instrumentation) |

**Coverage**: 17/21 methods (81%)

### HandlerState

| Cranelift | Cot | Status |
|-----------|-----|--------|
| `HandlerState` struct | Not ported | ❌ Deferred (exception handling) |
| `HandlerStateCheckpoint` | Not ported | ❌ Deferred (exception handling) |

**Coverage**: 0/2 (0%) - Deferred for exception handling MVP

## Tests Ported

| Test | Status |
|------|--------|
| `value stack operations` | ✅ |
| `push multiple values` | ✅ |
| `control stack block` | ✅ |
| `control stack loop - br_destination is header` | ✅ CRITICAL |
| `control stack if with else data` | ✅ |
| `set branched to exit` | ✅ |
| `truncate value stack to original size` | ✅ |

**Test Coverage**: 7/7 tests (100%)

## Differences from Cranelift

1. **No stack_shape tracking**: Cranelift tracks stack "shape" for debug instrumentation. Deferred for simplicity.

2. **No exception handling**: Cranelift's `HandlerState`, `try_table_info`, and `restore_catch_handlers` are not ported. Exception handling is a separate feature.

3. **No blocktype storage**: Cranelift stores `wasmparser::BlockType` in `If` frames. We don't need this for translation (types are handled separately).

4. **Local entity types**: Entity types (Block, Value, Inst) are defined locally rather than importing from CLIF IR. This allows standalone testing. Types will be unified when integrating.

5. **pop4/pop5 not ported**: These 4/5-value pops are rarely used. Easy to add if needed.

## Critical Algorithm: br_destination

The most critical method is `br_destination()`:

**Cranelift** (stack.rs:131-136):
```rust
pub fn br_destination(&self) -> Block {
    match *self {
        Self::If { destination, .. } | Self::Block { destination, .. } => destination,
        Self::Loop { header, .. } => header,
    }
}
```

**Cot** (stack.zig:135-143):
```zig
pub fn brDestination(self: Self) Block {
    return switch (self) {
        .if_frame => |f| f.destination,
        .block_frame => |f| f.destination,
        .loop_frame => |f| f.header,
    };
}
```

**CRITICAL**: For loops, `br` targets the **header** (loop re-entry), not the destination (exit block). This is fundamental to Wasm loop semantics.

## Verification

- [x] All 7 unit tests pass
- [x] Value stack push/pop operations work correctly
- [x] Control stack block/loop/if operations work correctly
- [x] Loop br_destination returns header (not destination)
- [x] If frame duplicates parameters on push
- [x] truncateValueStackToOriginalSize handles If frame parameter duplication
- [x] exit_is_branched_to flag can be set on block/if frames

## Integration Notes

When integrating with the full CLIF IR:

1. Replace local entity types with imports from `compiler/ir/clif/dfg.zig`
2. Add `allocator` parameter threading if needed
3. Consider adding `HandlerState` for exception handling support
4. Consider adding `stack_shape` for debug instrumentation
