# instructions.zig - Cranelift Port Audit

## Cranelift Source

- **File**: `~/learning/wasmtime/cranelift/codegen/src/ir/condcodes.rs`
- **File**: `~/learning/wasmtime/cranelift/codegen/src/ir/trapcode.rs`
- **File**: `~/learning/wasmtime/cranelift/codegen/meta/src/shared/instructions.rs`
- **File**: `~/learning/wasmtime/cranelift/codegen/meta/src/shared/formats.rs`
- **Lines**: condcodes.rs (~350), trapcode.rs (~160), instructions.rs (~1500)
- **Commit**: wasmtime main branch (January 2026)

## Coverage Summary

### IntCC (Integer Condition Codes)

| Cranelift | Cot | Status |
|-----------|-----|--------|
| `Equal` | `eq` | ✅ |
| `NotEqual` | `ne` | ✅ |
| `SignedLessThan` | `slt` | ✅ |
| `SignedGreaterThanOrEqual` | `sge` | ✅ |
| `SignedGreaterThan` | `sgt` | ✅ |
| `SignedLessThanOrEqual` | `sle` | ✅ |
| `UnsignedLessThan` | `ult` | ✅ |
| `UnsignedGreaterThanOrEqual` | `uge` | ✅ |
| `UnsignedGreaterThan` | `ugt` | ✅ |
| `UnsignedLessThanOrEqual` | `ule` | ✅ |

**Methods:**

| Cranelift | Cot | Status |
|-----------|-----|--------|
| `complement()` | `complement()` | ✅ |
| `swap_args()` | `swapArgs()` | ✅ |
| `without_equal()` | `withoutEqual()` | ✅ |
| `unsigned()` | `unsigned()` | ✅ |
| `to_static_str()` | `toStr()` | ✅ |
| `Display::fmt()` | `format()` | ✅ |

**Coverage**: 10/10 variants, 6/6 methods (100%)

### FloatCC (Floating Point Condition Codes)

| Cranelift | Cot | Status |
|-----------|-----|--------|
| `Ordered` | `ord` | ✅ |
| `Unordered` | `uno` | ✅ |
| `Equal` | `eq` | ✅ |
| `NotEqual` | `ne` | ✅ |
| `OrderedNotEqual` | `one` | ✅ |
| `UnorderedOrEqual` | `ueq` | ✅ |
| `LessThan` | `lt` | ✅ |
| `LessThanOrEqual` | `le` | ✅ |
| `GreaterThan` | `gt` | ✅ |
| `GreaterThanOrEqual` | `ge` | ✅ |
| `UnorderedOrLessThan` | `ult` | ✅ |
| `UnorderedOrLessThanOrEqual` | `ule` | ✅ |
| `UnorderedOrGreaterThan` | `ugt` | ✅ |
| `UnorderedOrGreaterThanOrEqual` | `uge` | ✅ |

**Methods:**

| Cranelift | Cot | Status |
|-----------|-----|--------|
| `complement()` | `complement()` | ✅ |
| `swap_args()` | `swapArgs()` | ✅ |
| `to_static_str()` | `toStr()` | ✅ |

**Coverage**: 14/14 variants, 3/3 methods (100%)

### TrapCode

| Cranelift | Cot | Status |
|-----------|-----|--------|
| `STACK_OVERFLOW` | `stack_overflow` | ✅ |
| `INTEGER_OVERFLOW` | `integer_overflow` | ✅ |
| `HEAP_OUT_OF_BOUNDS` | `heap_out_of_bounds` | ✅ |
| `INTEGER_DIVISION_BY_ZERO` | `integer_division_by_zero` | ✅ |
| `BAD_CONVERSION_TO_INTEGER` | `bad_conversion_to_integer` | ✅ |
| User codes | `user1`, `user2` | ✅ Simplified |

**Coverage**: 5/5 reserved codes (100%)

### Opcode (Essential Opcodes)

| Category | Opcodes | Status |
|----------|---------|--------|
| Control Flow | jump, brif, br_table, return, call, call_indirect | ✅ 6/6 |
| Traps | trap, trapnz, trapz | ✅ 3/3 |
| Integer Arith | iconst, copy, iadd, isub, ineg, imul, udiv, sdiv, urem, srem, *_overflow | ✅ 12/~30 |
| Bitwise | band, bor, bxor, bnot, ishl, ushr, sshr, rotl, rotr | ✅ 9/9 |
| Comparison | icmp | ✅ 1/1 |
| Float Arith | f32const, f64const, fadd, fsub, fmul, fdiv, fneg, fabs, sqrt, fcmp | ✅ 10/~20 |
| Conversions | uextend, sextend, ireduce, bitcast, fcvt_*, fpromote, fdemote | ✅ 10/~15 |
| Memory | load, store, stack_load, stack_store | ✅ 4/~8 |
| Select | select | ✅ 1/1 |
| Misc | nop, func_addr | ✅ 2/~5 |

**Coverage**: 58 opcodes ported (essential for Wasm translation)

**Note**: Cranelift has ~200 opcodes total. We ported the essential ones for Wasm→native.

## Tests Ported

| Test | Status |
|------|--------|
| IntCC complement | ✅ |
| IntCC swap_args | ✅ |
| FloatCC complement | ✅ |
| FloatCC swap_args | ✅ |
| Opcode properties | ✅ |
| TrapCode to_str | ✅ |

**Test Coverage**: 6/6 tests (100%)

## Differences from Cranelift

1. **TrapCode**: Cranelift uses `NonZeroU8` with runtime user code construction. We use an enum with explicit user codes for simplicity.

2. **Opcode**: Cranelift generates ~200 opcodes from meta. We manually define the essential ~60 opcodes needed for Wasm translation.

3. **Naming**: Zig uses camelCase (swapArgs) instead of Rust snake_case (swap_args).

4. **No serde**: Serialization not needed.

## Verification

- [x] All 6 unit tests pass
- [x] IntCC complements verified against Cranelift
- [x] FloatCC complements verified against Cranelift
- [x] TrapCode values match Cranelift reserved range
- [x] Essential opcodes cover Wasm translation needs
