# WebAssembly 2.0 Reference for Cot Compiler

**Status:** W3C Candidate Recommendation (March 2025, evergreen model)
**Full spec:** https://www.w3.org/TR/wasm-core-2/
**Browser support:** All features shipped in all major browsers since 2020-2021

Wasm 2.0 merged 6 proposals on top of Wasm 1.0. All are backward-compatible.

---

## Cot's Current Wasm 2.0 Adoption

| Feature | Status in Cot | Notes |
|---------|---------------|-------|
| Sign Extension Ops | **Adopted** | Opcodes in `wasm_opcodes.zig`, decoded in `decoder.zig` |
| Reference Types | **Adopted** | `funcref`/`externref` in tables, `ref.null`/`ref.func` |
| Bulk Memory Ops | **Partial** | Opcodes defined/decoded but gen.zig emits loops instead |
| Multi-Value Returns | **Not used** | Compound returns decomposed to locals |
| Non-Trapping Float Conversions | **Not used** | Cot uses trapping `trunc` ops |
| SIMD (v128) | **Not used** | Not relevant to Cot's audience yet |

---

## Feature 1: Sign Extension Instructions

**Opcodes:** `0xC0`–`0xC4`

| Instruction | Opcode | Semantics |
|-------------|--------|-----------|
| `i32.extend8_s` | `0xC0` | Sign-extend i8 → i32 |
| `i32.extend16_s` | `0xC1` | Sign-extend i16 → i32 |
| `i64.extend8_s` | `0xC2` | Sign-extend i8 → i64 |
| `i64.extend16_s` | `0xC3` | Sign-extend i16 → i64 |
| `i64.extend32_s` | `0xC4` | Sign-extend i32 → i64 |

**Cot status:** Fully adopted. These replace the old shift-pair pattern for sign extension.

**Files:** `wasm_opcodes.zig:256-260`, `decoder.zig:784-788`

---

## Feature 2: Non-Trapping Float-to-Int Conversions

**Opcodes:** `0xFC 0x00`–`0xFC 0x07`

| Instruction | Opcode | Semantics |
|-------------|--------|-----------|
| `i32.trunc_sat_f32_s` | `0xFC 0x00` | f32 → i32 signed (saturating) |
| `i32.trunc_sat_f32_u` | `0xFC 0x01` | f32 → i32 unsigned (saturating) |
| `i32.trunc_sat_f64_s` | `0xFC 0x02` | f64 → i32 signed (saturating) |
| `i32.trunc_sat_f64_u` | `0xFC 0x03` | f64 → i32 unsigned (saturating) |
| `i64.trunc_sat_f32_s` | `0xFC 0x04` | f32 → i64 signed (saturating) |
| `i64.trunc_sat_f32_u` | `0xFC 0x05` | f32 → i64 unsigned (saturating) |
| `i64.trunc_sat_f64_s` | `0xFC 0x06` | f64 → i64 signed (saturating) |
| `i64.trunc_sat_f64_u` | `0xFC 0x07` | f64 → i64 unsigned (saturating) |

Unlike the Wasm 1.0 `trunc` variants, these **never trap**. On out-of-range: saturate to min/max. On NaN: return 0.

**Cot status:** Not adopted. Cot uses trapping `trunc` ops. Should adopt for `@intCast` from floats — saturating is safer and matches user expectations.

**Cot action:** When adding float-to-int casts, emit `trunc_sat` instead of `trunc`. Zero additional complexity.

---

## Feature 3: Multi-Value Returns

Functions and blocks can return **multiple values** (Wasm 1.0 limited to 0 or 1).

**Encoding change:** Block types can now reference a function type via type index (s33) in addition to inline value types.

**Cot status:** Not used directly. Compound types (string = ptr+len) are decomposed to separate locals. The compiler works around this limitation rather than using the feature.

**Cot action:** Could simplify compound return handling significantly. Instead of the current `compound_len_locals` map and separate local.get/set dance, functions returning `string` would declare `(result i64 i64)` and the caller gets both values from the stack directly. **This would eliminate 5+ workarounds in `gen.zig` and `driver.zig`.**

**Impact:**
- `gen.zig`: Simplify `.ret` handler for compound types — push both values, one `return`
- `driver.zig`: Function type declarations use `(result i64 i64)` instead of single `i64`
- `wasm_parser.zig`: Already handles multi-return types
- Native pipeline: `translator.zig` already handles multi-value in `translateCall`

---

## Feature 4: Reference Types

Two new first-class value types + table generalization.

**New types:**
| Type | Encoding | Description |
|------|----------|-------------|
| `funcref` | `0x70` | Reference to a function |
| `externref` | `0x6F` | Opaque host reference |

**New instructions:**
| Instruction | Opcode | Semantics |
|-------------|--------|-----------|
| `ref.null t` | `0xD0` | Push null reference of heap type t |
| `ref.is_null` | `0xD1` | Test if reference is null |
| `ref.func x` | `0xD2` | Push reference to function x |
| `table.get x` | `0x25` | Get reference from table x |
| `table.set x` | `0x26` | Set reference in table x |
| `table.size x` | `0xFC 0x10` | Get table size |
| `table.grow x` | `0xFC 0x0F` | Grow table |
| `table.fill x` | `0xFC 0x11` | Fill table range |
| `select t*` | `0x1C` | Typed select with explicit type |

**Table changes:** Tables can hold any reference type (not just funcref). Multiple tables per module.

**Cot status:** Partially adopted. `funcref`/`externref` defined in types. Tables use `funcref`. `ref.null`, `ref.func` parsed. But Cot only uses one table for `call_indirect` dispatch.

**Cot action:**
- `externref` becomes important for browser DOM interop (`@client` functions receiving JS objects)
- `table.grow` needed if function pointer table needs dynamic sizing
- Foundation for Wasm 3.0's typed function references

---

## Feature 5: Bulk Memory Operations

Efficient memory/table copying and initialization. Adds passive data/element segments.

**New instructions:**
| Instruction | Opcode | Semantics |
|-------------|--------|-----------|
| `memory.copy` | `0xFC 0x0A` | Copy memory range (like memcpy) |
| `memory.fill` | `0xFC 0x0B` | Fill memory range with byte |
| `memory.init x` | `0xFC 0x08` | Copy data segment x into memory |
| `data.drop x` | `0xFC 0x09` | Drop data segment x (free backing) |
| `table.init x` | `0xFC 0x0C` | Copy element segment to table |
| `elem.drop x` | `0xFC 0x0D` | Drop element segment |
| `table.copy` | `0xFC 0x0E` | Copy table range |

**New section:** Data Count section (ID 12) — declares number of data segments for single-pass validation.

**Segment types:** Active (instantiation), Passive (deferred, used with `memory.init`), Declarative (validates function refs).

**Cot status:** Opcodes defined and decoded, but **gen.zig emits manual loops for memcpy/memfill instead of using the instructions.**

**Cot action (HIGH PRIORITY):**
- Replace the word-by-word copy loop in `gen.zig:997-1013` (`wasm_lowered_move`) with `memory.copy`
- Replace zero-init loops with `memory.fill`
- This is a **direct performance win** — engines optimize these to native `memcpy`/`memset`
- Emit data count section for spec compliance

---

## Feature 6: Fixed-Width SIMD (v128)

236 new instructions under the `0xFD` prefix. Introduces `v128` type (128-bit vector) with lane interpretations: `i8x16`, `i16x8`, `i32x4`, `i64x2`, `f32x4`, `f64x2`.

**Cot status:** Not adopted. Not relevant to Cot's target audience (full-stack web development).

**Cot action:** Defer. If Cot ever targets ML inference or crypto, SIMD becomes relevant. For now, the ROI is too low.

---

## Priority Implementation Order for Cot

| Priority | Feature | Effort | Impact |
|----------|---------|--------|--------|
| 1 | **Bulk memory: `memory.copy`/`memory.fill`** | LOW (swap loop → opcode) | Performance: all memcpy/zero-init |
| 2 | **Multi-value returns** | MEDIUM (refactor compound returns) | Code simplification, correctness |
| 3 | **Non-trapping float conversions** | LOW (swap opcode) | Safety: no trap on float→int |
| 4 | **Data count section** | LOW (add section to linker) | Spec compliance |
| 5 | **`externref` for DOM interop** | MEDIUM (type system + imports) | Browser target requirement |
| 6 | **SIMD** | HIGH (236 opcodes) | Not needed yet |
