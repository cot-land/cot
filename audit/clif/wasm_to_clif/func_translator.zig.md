# func_translator.zig - Cranelift Port Audit

## Cranelift Source

- **File**: `~/learning/wasmtime/crates/cranelift/src/translate/func_translator.rs`
- **Lines**: 1-333
- **Commit**: wasmtime main branch (February 2026)

## Coverage Summary

### FuncTranslator

| Cranelift | Cot | Status |
|-----------|-----|--------|
| `FuncTranslator` struct | `FuncTranslator` struct | ✅ |
| `func_ctx: FunctionBuilderContext` | `translator: Translator` | ✅ Different approach |
| `new()` | `init()` | ✅ |
| `context()` | Not needed | ❌ N/A |
| `translate_body()` | `translateFunction()` | ✅ Simplified |

**Coverage**: 3/5 methods (60%)

### Helper Functions

| Cranelift | Cot | Status |
|-----------|-----|--------|
| `declare_wasm_parameters()` | Inline in translateFunction | ✅ Simplified |
| `parse_local_decls()` | Via `LocalDecl` input | ✅ Different interface |
| `declare_locals()` | Inline local initialization | ✅ Simplified |
| `parse_function_body()` | Via `WasmOperator[]` input | ✅ Different interface |
| `validate_op_and_get_operand_types()` | Not ported | ❌ Validation deferred |
| `cur_srcloc()` | Not ported | ❌ Source locations deferred |

**Coverage**: 4/6 functions (67%)

### Types

| Cranelift | Cot | Status |
|-----------|-----|--------|
| Uses wasmparser types | `WasmValType` enum | ✅ Simplified |
| Uses FunctionBody | `WasmOperator[]` | ✅ Simplified |
| Uses FuncEnvironment | Not needed | ❌ Environment deferred |

## Tests Ported

| Test | Status |
|------|--------|
| `translate simple function: (i32, i32) -> i32` | ✅ |
| `translate function with local` | ✅ |
| `translate function with block` | ✅ |
| `translate function with loop and br` | ✅ |
| `translate function with if-else` | ✅ |

**Test Coverage**: 5/5 tests (100%)

## Differences from Cranelift

1. **No FunctionBuilder integration**: Cranelift uses cranelift_frontend's FunctionBuilder for SSA construction. We use a simplified approach that records instructions.

2. **Simplified input interface**: Cranelift parses binary Wasm directly with wasmparser. We take pre-parsed operators as input for testing.

3. **No validation**: Cranelift integrates with FuncValidator. We assume valid input.

4. **No FuncEnvironment**: Cranelift uses an environment for runtime-specific details (memory base, globals, etc.). Deferred for MVP.

5. **No source locations**: Cranelift tracks source locations for debugging. Deferred.

6. **No stack maps**: Cranelift tracks which locals need stack maps for GC. Deferred.

## Translation Flow

**Cranelift** (func_translator.rs):
```rust
pub fn translate_body(&mut self, ...) -> WasmResult<()> {
    // 1. Create entry block
    let entry_block = builder.create_block();
    builder.append_block_params_for_function_params(entry_block);

    // 2. Declare parameters as locals
    let num_params = declare_wasm_parameters(&mut builder, ...);

    // 3. Create exit block
    let exit_block = builder.create_block();
    environ.stacks.initialize(&builder.func.signature, exit_block);

    // 4. Parse local declarations
    parse_local_decls(&mut reader, ...)?;

    // 5. Parse function body (operator by operator)
    parse_function_body(validator, reader, ...)?;

    // 6. Add return instruction
    if environ.is_reachable() {
        builder.ins().return_(&returns);
    }

    builder.finalize();
}
```

**Cot** (func_translator.zig):
```zig
pub fn translateFunction(self: *Self, ...) !void {
    // Save return count
    self.num_returns = signature.results.len;

    // 1. Calculate total locals
    var num_locals = signature.params.len;
    for (locals) |local| num_locals += local.count;

    // 2. Initialize translator
    try self.translator.initializeFunction(num_locals, signature.results.len);

    // 3. Create entry block, set up parameters
    const entry_block = self.translator.createBlock();
    for (signature.params) |_| {
        try self.translator.state.push1(self.translator.createValue());
    }

    // 4. Initialize declared locals
    for (locals) |local| { ... }

    // 5. Translate operators
    for (operators) |op| {
        try self.translateOperator(op);
    }

    // 6. Add return instruction
    if (self.translator.state.isReachable()) {
        try self.translator.emitVoid(.return_op, ...);
    }
}
```

## Verification

- [x] All 5 func_translator tests pass
- [x] All 19 total tests pass (stack + translator + func_translator)
- [x] Simple function translation works
- [x] Local variables work (params and declared)
- [x] Block control flow works
- [x] Loop control flow works (br back to header)
- [x] If-else control flow works

## Integration Notes

When integrating with the full pipeline:

1. Replace `WasmOperator` input with actual Wasm binary parsing (using our existing wasm_parser.zig)
2. Connect to CLIF IR builder for actual instruction emission
3. Add FuncEnvironment for runtime details (memory, globals, tables)
4. Add validation pass integration
5. Add source location tracking for debugging
