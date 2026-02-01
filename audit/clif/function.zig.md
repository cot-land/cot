# function.zig - Cranelift Port Audit

## Cranelift Source

- **File**: `~/learning/wasmtime/cranelift/codegen/src/ir/function.rs`
- **File**: `~/learning/wasmtime/cranelift/codegen/src/ir/extfunc.rs`
- **File**: `~/learning/wasmtime/cranelift/codegen/src/ir/stackslot.rs`
- **File**: `~/learning/wasmtime/cranelift/codegen/src/isa/call_conv.rs`
- **Lines**: function.rs (~520), extfunc.rs (~400), stackslot.rs (~250), call_conv.rs (~150)
- **Commit**: wasmtime main branch (January 2026)

## Coverage Summary

### CallConv (from call_conv.rs)

| Cranelift | Cot | Status |
|-----------|-----|--------|
| `Fast` | `fast` | ✅ |
| `Tail` | `tail` | ✅ |
| `SystemV` | `system_v` | ✅ |
| `WindowsFastcall` | `windows_fastcall` | ✅ |
| `AppleAarch64` | `apple_aarch64` | ✅ |
| `Probestack` | `probestack` | ✅ |
| `Winch` | `winch` | ✅ |
| `PreserveAll` | `preserve_all` | ✅ |
| `supports_tail_calls()` | `supportsTailCalls()` | ✅ |
| `triple_default()` | Not ported | ❌ Deferred |
| `for_libcall()` | Not ported | ❌ Deferred |

**Coverage**: 9/11 (82%)

### ArgumentExtension (from extfunc.rs)

| Cranelift | Cot | Status |
|-----------|-----|--------|
| `None` | `none` | ✅ |
| `Uext` | `uext` | ✅ |
| `Sext` | `sext` | ✅ |

**Coverage**: 3/3 (100%)

### ArgumentPurpose (from extfunc.rs)

| Cranelift | Cot | Status |
|-----------|-----|--------|
| `Normal` | `normal` | ✅ |
| `StructArgument(u32)` | `struct_argument: u32` | ✅ |
| `StructReturn` | `struct_return` | ✅ |
| `VMContext` | `vmctx` | ✅ |

**Coverage**: 4/4 (100%)

### AbiParam (from extfunc.rs)

| Cranelift | Cot | Status |
|-----------|-----|--------|
| `value_type` | `value_type` | ✅ |
| `purpose` | `purpose` | ✅ |
| `extension` | `extension` | ✅ |
| `new()` | `init()` | ✅ |
| `special()` | `special()` | ✅ |
| `uext()` | `uext()` | ✅ |
| `sext()` | `sext()` | ✅ |

**Coverage**: 7/7 (100%)

### Signature (from extfunc.rs)

| Cranelift | Cot | Status |
|-----------|-----|--------|
| `params` | `params` | ✅ |
| `returns` | `returns` | ✅ |
| `call_conv` | `call_conv` | ✅ |
| `new()` | `init()` | ✅ |
| `clear()` | `clear()` | ✅ |
| `special_param_index()` | `specialParamIndex()` | ✅ |
| `special_return_index()` | Not ported | ❌ Deferred |
| `uses_special_param()` | `usesSpecialParam()` | ✅ |
| `uses_struct_return_param()` | `usesStructReturnParam()` | ✅ |
| `num_special_params()` | `numSpecialParams()` | ✅ |
| `is_multi_return()` | `isMultiReturn()` | ✅ |

**Coverage**: 10/11 (91%)

### StackSlotKind (from stackslot.rs)

| Cranelift | Cot | Status |
|-----------|-----|--------|
| `ExplicitSlot` | `explicit_slot` | ✅ |
| `ExplicitDynamicSlot` | `explicit_dynamic_slot` | ✅ |

**Coverage**: 2/2 (100%)

### StackSlotData (from stackslot.rs)

| Cranelift | Cot | Status |
|-----------|-----|--------|
| `kind` | `kind` | ✅ |
| `size` | `size` | ✅ |
| `align_shift` | `align_shift` | ✅ |
| `key` | Not ported | ❌ Deferred |
| `new()` | `init()` | ✅ |
| `new_with_key()` | Not ported | ❌ Deferred |

**Coverage**: 5/6 (83%)

### ExtFuncData (from extfunc.rs)

| Cranelift | Cot | Status |
|-----------|-----|--------|
| `name` | `name` | ✅ |
| `signature` | `signature` | ✅ |
| `colocated` | `colocated` | ✅ |
| `patchable` | Not ported | ❌ Deferred |

**Coverage**: 3/4 (75%)

### Function (from function.rs)

| Cranelift | Cot | Status |
|-----------|-----|--------|
| `name` | `name` | ✅ |
| `signature` | `signature` | ✅ |
| `sized_stack_slots` | `stack_slots` | ✅ |
| `dynamic_stack_slots` | Not ported | ❌ Deferred |
| `global_values` | Not ported | ❌ Deferred |
| `global_value_facts` | Not ported | ❌ Deferred (PCC) |
| `memory_types` | Not ported | ❌ Deferred (PCC) |
| `dfg` | `dfg` | ✅ |
| `layout` | `layout` | ✅ |
| `srclocs` | Not ported | ❌ Deferred |
| `debug_tags` | Not ported | ❌ Deferred |
| `stack_limit` | Not ported | ❌ Deferred |
| `with_name_signature()` | `withNameSignature()` | ✅ |
| `new()` | `init()` | ✅ |
| `clear()` | `clear()` | ✅ |
| `create_sized_stack_slot()` | `createStackSlot()` | ✅ |
| `import_signature()` | `importSignature()` | ✅ |
| `import_function()` | `importFunction()` | ✅ |
| `fixed_stack_size()` | `fixedStackSize()` | ✅ |
| `special_param()` | `specialParam()` | ✅ |
| `entry_block()` | `entryBlock()` | ✅ |

**Coverage**: 14/23 (61%) - Essential subset for Wasm translation

## Tests Ported

| Test | Status |
|------|--------|
| `signature creation` | ✅ |
| `abi param extensions` | ✅ |
| `stack slot data` | ✅ |
| `function creation` | ✅ |
| `special params` | ✅ |
| `call conv` | ✅ |

**Test Coverage**: 6/6 tests (100%)

## Differences from Cranelift

1. **No FunctionStencil/FunctionParameters split**: Cranelift separates compilation-relevant parts (stencil) from metadata (parameters) for caching. We merge them for simplicity.

2. **No proof-carrying code (PCC)**: Cranelift has `global_value_facts` and `memory_types` for formal verification. Not needed for MVP.

3. **No dynamic stack slots**: Cranelift supports dynamic-sized stack slots for vector types. Not needed for MVP.

4. **No source locations**: Cranelift tracks source locations for debugging. Not ported yet.

5. **No debug tags**: Cranelift has opaque debug info. Not ported yet.

6. **No stack limit**: Cranelift can insert stack overflow checks. Not ported yet.

7. **Simplified ExternalName**: Cranelift has complex `UserExternalName` with `namespace` and `index`. We simplified to `user` and `libcall` variants.

8. **No StackSlotKey**: Cranelift has opaque metadata handles for stack slots. Not needed for MVP.

## Verification

- [x] All 6 unit tests pass
- [x] CallConv variants match Cranelift
- [x] AbiParam extension and purpose handling works
- [x] Signature parameter/return handling works
- [x] StackSlotData creation and alignment works
- [x] Function creation with stack slots works
- [x] Total: 27 tests pass (including imported modules)
