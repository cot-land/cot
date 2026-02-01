# builder.zig - Cranelift Port Audit

## Cranelift Source

- **File**: `~/learning/wasmtime/cranelift/codegen/src/ir/builder.rs`
- **File**: `~/learning/wasmtime/cranelift/codegen/meta/src/shared/formats.rs`
- **Generated**: `cranelift-codegen/meta/src/gen_inst.rs` → InstructionData, InstBuilder
- **Lines**: builder.rs (~283), formats.rs (~200)
- **Commit**: wasmtime main branch (January 2026)

## Coverage Summary

### InstructionFormat

| Cranelift | Cot | Status |
|-----------|-----|--------|
| `Nullary` | `nullary` | ✅ |
| `Unary` | `unary` | ✅ |
| `UnaryImm` | `unary_imm` | ✅ |
| `UnaryIeee32` | `unary_ieee32` | ✅ |
| `UnaryIeee64` | `unary_ieee64` | ✅ |
| `Binary` | `binary` | ✅ |
| `BinaryImm64` | `binary_imm64` | ✅ |
| `Ternary` | `ternary` | ✅ |
| `IntCompare` | `int_compare` | ✅ |
| `FloatCompare` | `float_compare` | ✅ |
| `Jump` | `jump` | ✅ |
| `Brif` | `brif` | ✅ |
| `BranchTable` | `branch_table` | ✅ |
| `Call` | `call` | ✅ |
| `CallIndirect` | `call_indirect` | ✅ |
| `Trap` | `trap` | ✅ |
| `CondTrap` | `cond_trap` | ✅ |
| `Load` | `load` | ✅ |
| `Store` | `store` | ✅ |
| `StackLoad` | `stack_load` | ✅ |
| `StackStore` | `stack_store` | ✅ |
| `FuncAddr` | `func_addr` | ✅ |
| `AtomicCas` | Not ported | ❌ Deferred |
| `AtomicRmw` | Not ported | ❌ Deferred |
| `Shuffle` | Not ported | ❌ Deferred |
| `DynamicStackLoad` | Not ported | ❌ Deferred |
| `DynamicStackStore` | Not ported | ❌ Deferred |

**Coverage**: 22/27 formats (81%) - Essential for Wasm translation

### InstructionData

| Cranelift | Cot | Status |
|-----------|-----|--------|
| `opcode()` | `opcode()` | ✅ |
| `format()` | `format()` | ✅ |
| `arguments()` | Not ported | ❌ Deferred |
| `arguments_mut()` | Not ported | ❌ Deferred |

**Coverage**: 2/4 methods (50%)

### MemFlags

| Cranelift | Cot | Status |
|-----------|-----|--------|
| `aligned` | `aligned` | ✅ |
| `readonly` | `readonly` | ✅ |
| `trap` | `trap_on_null` | ✅ |
| `heap` | `heap` | ✅ |
| `notrap` | Not ported | ❌ Deferred |
| `big_endian` | Not ported | ❌ Deferred |

**Coverage**: 4/6 flags (67%)

### Builder Traits (from builder.rs)

| Cranelift | Cot | Status |
|-----------|-----|--------|
| `InstBuilderBase` trait | `FuncBuilder` struct | ✅ Simplified |
| `InstBuilder` trait | Methods on `FuncBuilder` | ✅ |
| `InstInserterBase` trait | Not ported (merged) | ❌ |
| `InsertBuilder` | Merged into `FuncBuilder` | ✅ |
| `InsertReuseBuilder` | Not ported | ❌ Deferred |
| `ReplaceBuilder` | Not ported | ❌ Deferred |

**Coverage**: 4/6 (67%)

### FuncBuilder Methods - Control Flow

| Cranelift | Cot | Status |
|-----------|-----|--------|
| `jump()` | `jump()` | ✅ |
| `brif()` | `brif()` | ✅ |
| `br_table()` | `brTable()` | ✅ |
| `return_()` | `ret()` | ✅ |
| `call()` | `call()` | ✅ |
| `call_indirect()` | `callIndirect()` | ✅ |

**Coverage**: 6/6 (100%)

### FuncBuilder Methods - Traps

| Cranelift | Cot | Status |
|-----------|-----|--------|
| `trap()` | `trap()` | ✅ |
| `trapnz()` | `trapnz()` | ✅ |
| `trapz()` | `trapz()` | ✅ |

**Coverage**: 3/3 (100%)

### FuncBuilder Methods - Constants

| Cranelift | Cot | Status |
|-----------|-----|--------|
| `iconst()` | `iconst()` | ✅ |
| `f32const()` | `f32const()` | ✅ |
| `f64const()` | `f64const()` | ✅ |

**Coverage**: 3/3 (100%)

### FuncBuilder Methods - Integer Arithmetic

| Cranelift | Cot | Status |
|-----------|-----|--------|
| `copy()` | `copy()` | ✅ |
| `iadd()` | `iadd()` | ✅ |
| `isub()` | `isub()` | ✅ |
| `imul()` | `imul()` | ✅ |
| `ineg()` | `ineg()` | ✅ |
| `udiv()` | `udiv()` | ✅ |
| `sdiv()` | `sdiv()` | ✅ |
| `urem()` | `urem()` | ✅ |
| `srem()` | `srem()` | ✅ |
| `iadd_imm()` | Not ported | ❌ Deferred |

**Coverage**: 9/10 (90%)

### FuncBuilder Methods - Bitwise

| Cranelift | Cot | Status |
|-----------|-----|--------|
| `band()` | `band()` | ✅ |
| `bor()` | `bor()` | ✅ |
| `bxor()` | `bxor()` | ✅ |
| `bnot()` | `bnot()` | ✅ |
| `ishl()` | `ishl()` | ✅ |
| `ushr()` | `ushr()` | ✅ |
| `sshr()` | `sshr()` | ✅ |
| `rotl()` | `rotl()` | ✅ |
| `rotr()` | `rotr()` | ✅ |

**Coverage**: 9/9 (100%)

### FuncBuilder Methods - Comparison

| Cranelift | Cot | Status |
|-----------|-----|--------|
| `icmp()` | `icmp()` | ✅ |
| `fcmp()` | `fcmp()` | ✅ |

**Coverage**: 2/2 (100%)

### FuncBuilder Methods - Float Arithmetic

| Cranelift | Cot | Status |
|-----------|-----|--------|
| `fadd()` | `fadd()` | ✅ |
| `fsub()` | `fsub()` | ✅ |
| `fmul()` | `fmul()` | ✅ |
| `fdiv()` | `fdiv()` | ✅ |
| `fneg()` | `fneg()` | ✅ |
| `fabs()` | `fabs()` | ✅ |
| `sqrt()` | `sqrt()` | ✅ |

**Coverage**: 7/7 (100%)

### FuncBuilder Methods - Conversions

| Cranelift | Cot | Status |
|-----------|-----|--------|
| `uextend()` | `uextend()` | ✅ |
| `sextend()` | `sextend()` | ✅ |
| `ireduce()` | `ireduce()` | ✅ |
| `fpromote()` | `fpromote()` | ✅ |
| `fdemote()` | `fdemote()` | ✅ |
| `bitcast()` | Not ported | ❌ Deferred |
| `fcvt_*` | Not ported | ❌ Deferred |

**Coverage**: 5/7 (71%)

### FuncBuilder Methods - Memory

| Cranelift | Cot | Status |
|-----------|-----|--------|
| `load()` | `load()` | ✅ |
| `store()` | `store()` | ✅ |
| `stack_load()` | `stackLoad()` | ✅ |
| `stack_store()` | `stackStore()` | ✅ |

**Coverage**: 4/4 (100%)

### FuncBuilder Methods - Other

| Cranelift | Cot | Status |
|-----------|-----|--------|
| `select()` | `select()` | ✅ |
| `nop()` | `nop()` | ✅ |
| `func_addr()` | `funcAddr()` | ✅ |
| `createBlock()` | `createBlock()` | ✅ |
| `switchToBlock()` | `switchToBlock()` | ✅ |
| `appendBlockParam()` | `appendBlockParam()` | ✅ |

**Coverage**: 6/6 (100%)

## Tests Ported

| Test | Status |
|------|--------|
| `instruction data opcode` | ✅ |
| `mem flags` | ✅ |
| `builder basic operations` | ✅ |

**Test Coverage**: 3/3 tests (100%)

## Differences from Cranelift

1. **Simplified builder pattern**: Cranelift uses traits (`InstBuilderBase`, `InstBuilder`, `InstInserterBase`) for maximum flexibility. We use a single `FuncBuilder` struct for simplicity.

2. **No InsertReuseBuilder**: Cranelift allows reusing result values. Not needed for MVP.

3. **No ReplaceBuilder**: Cranelift can replace instructions in-place. Not needed for MVP.

4. **No codegen/meta**: Cranelift generates `InstBuilder` methods from meta language. We manually implement essential methods.

5. **Minimal instruction storage**: Instruction data storage is simplified - just an instruction count for generating IDs. Full instruction storage TBD.

6. **No atomic operations**: Atomic CAS/RMW formats not ported.

7. **No shuffle operations**: Vector shuffle not ported.

## Verification

- [x] All 3 unit tests pass
- [x] InstructionData opcode/format extraction works
- [x] MemFlags creation and modification works
- [x] FuncBuilder can create blocks, parameters, and instructions
- [x] Total: 30 tests pass (including imported modules)
