# WebAssembly 3.0 Reference for Cot Compiler

**Source:** WebAssembly Specification, Release 3.0 (September 2025)
**Full spec:** `docs/specs/wasm-3.0-full.txt` (25,919 lines)
**Binary format detail:** `docs/specs/wasm-3.0-binary-format.txt`

This document extracts the parts of Wasm 3.0 that matter for the Cot compiler. Read this instead of the full spec.

---

## What's New in Wasm 3.0 vs 2.0

10 proposals merged:

| # | Feature | Key for Cot? | Why |
|---|---------|-------------|-----|
| 1 | Tail calls | YES | `return_call` for recursive patterns |
| 2 | Exception handling | YES | `try_table`/`throw` for defer interop, error propagation |
| 3 | Typed function references | YES | `call_ref` for faster closures, no table indirection |
| 4 | Multiple memories | MAYBE | Separate heap/stack/metadata memories |
| 5 | 64-bit address space | MAYBE | >4GB linear memory for server workloads |
| 6 | GC types | NO (interop only) | Cot uses ARC, not GC |
| 7 | Extended constant expressions | LOW | Arithmetic in initializers |
| 8 | Relaxed SIMD | NO | Not for target audience |
| 9 | Profiles | LOW | Deterministic mode |
| 10 | Custom annotations | LOW | Text format only |

---

## New Opcodes — Compiler Implementation Reference

### Cot currently emits Wasm 1.0. These opcodes can be adopted incrementally.

### Tail Calls (Priority: HIGH)

Cot should detect tail-position calls in `lower.zig` and emit these instead of `call` + `return`.

| Instruction | Opcode | Semantics |
|-------------|--------|-----------|
| `return_call x` | `0x12` | Tail call function x (reuses stack frame) |
| `return_call_indirect x y` | `0x13` | Tail call through table y with type x |
| `return_call_ref x` | `0x15` | Tail call through typed function reference |

**Binary encoding:**
```
return_call:          0x12 funcidx:u32
return_call_indirect: 0x13 tableidx:u32 typeidx:u32
return_call_ref:      0x15 typeidx:u32
```

**Implementation in Cot:**
- `lower.zig`: When last statement is `return f(args)`, emit `wasm_return_call` SSA op
- `gen.zig`: Map `wasm_return_call` to opcode `0x12`
- `wasm_parser.zig`: Parse `0x12`, `0x13`, `0x15` in native AOT path
- `translator.zig`: Lower to CLIF `return_call` → ARM64 `b` / x64 `jmp`

### Exception Handling (Priority: HIGH)

Enables structured error propagation and defer-across-calls cleanup.

| Instruction | Opcode | Semantics |
|-------------|--------|-----------|
| `throw x` | `0x08` | Throw exception with tag x |
| `throw_ref` | `0x0A` | Re-throw exception reference |
| `try_table bt catch* instr* end` | `0x1F` | Exception handler block |

**Catch clause encoding (inside try_table):**
```
catch x l:       0x00 tagidx:u32 labelidx:u32
catch_ref x l:   0x01 tagidx:u32 labelidx:u32
catch_all l:     0x02 labelidx:u32
catch_all_ref l: 0x03 labelidx:u32
```

**Tag section (NEW section id 13):**
```
tagsec ::= section_13(tag*)
tag    ::= 0x00 typeidx:u32
```

**New heap types:**
```
exn   = 0x69 (-23 as s7)   -- exception reference
noexn = 0x74 (-12 as s7)   -- bottom of exception hierarchy
```

**Import/export extension:**
```
tag import: 0x04 typeidx:u32
tag export: 0x04 tagidx:u32
```

**Implementation in Cot:**
- `link.zig`: Add tag section (section 13) after global section
- `gen.zig`: Emit `try_table` around calls that need defer cleanup
- `wasm_parser.zig`: Parse section 13, parse `0x08`, `0x0A`, `0x1F`
- Could use for: panic propagation, defer cleanup across call boundaries

### Typed Function References (Priority: HIGH)

Eliminates table indirection for closures and function pointers.

| Instruction | Opcode | Semantics |
|-------------|--------|-----------|
| `call_ref x` | `0x14` | Call function through typed reference |
| `ref.as_non_null` | `0xD4` | Assert non-null reference |
| `br_on_null l` | `0xD5` | Branch if null |
| `br_on_non_null l` | `0xD6` | Branch if non-null |

**Reference type encoding:**
```
(ref null ht) = 0x63 heaptype    -- nullable reference
(ref ht)      = 0x64 heaptype    -- non-nullable reference
```

**Heap type encoding (extended):**
```
func     = 0x70 (-16)
extern   = 0x6F (-17)
any      = 0x6E (-18)
eq       = 0x6D (-19)
i31      = 0x6C (-20)
struct   = 0x6B (-21)
array    = 0x6A (-22)
exn      = 0x69 (-23)
noexn    = 0x74 (-12)
nofunc   = 0x73 (-13)
noextern = 0x72 (-14)
none     = 0x71 (-15)
typeidx  = u32         -- concrete type index (positive = type defined in module)
```

**Implementation in Cot:**
- Closures: carry `(ref $closure_type)` instead of table index
- Function pointers: `call_ref` instead of `call_indirect` — no table lookup
- `gen.zig`: Emit `0x14` for typed function calls
- Requires type section to define function reference types

### Multiple Memories (Priority: LOW)

| Instruction change | Encoding |
|-------------------|----------|
| All load/store ops | Now take `memidx:u32` before `memarg` |
| `memory.size x` | `0x3F memidx:u32` |
| `memory.grow x` | `0x40 memidx:u32` |
| `memory.fill x` | `0xFC 0x0B memidx:u32` |
| `memory.copy x y` | `0xFC 0x0A memidx:u32 memidx:u32` |
| `memory.init x y` | `0xFC 0x08 dataidx:u32 memidx:u32` |
| `data.drop x` | `0xFC 0x09 dataidx:u32` |

**Note:** For backward compatibility with Wasm 1.0/2.0, if only one memory exists, the memory index is implicitly 0 and can be omitted (Cot currently does this).

### 64-bit Address Space (Priority: LOW)

Memory types now include address type:
```
memtype ::= addrtype limits
addrtype ::= 0x00 (i32) | 0x04 (i64)
```

When a memory has `i64` address type:
- All memory instruction addresses are `i64` instead of `i32`
- `memory.size` returns `i64`
- `memory.grow` takes `i64`

### GC Types (Priority: NONE for Cot's own objects, FUTURE for interop)

All under `0xFB` prefix:

| Instruction | Opcode | Type |
|-------------|--------|------|
| `struct.new x` | `0xFB 0x00` | Create GC struct |
| `struct.new_default x` | `0xFB 0x01` | Create zero-initialized struct |
| `struct.get x y` | `0xFB 0x02` | Get field y from struct type x |
| `struct.get_s x y` | `0xFB 0x03` | Get signed packed field |
| `struct.get_u x y` | `0xFB 0x04` | Get unsigned packed field |
| `struct.set x y` | `0xFB 0x05` | Set field y on struct type x |
| `array.new x` | `0xFB 0x06` | Create GC array |
| `array.new_default x` | `0xFB 0x07` | Create zero-initialized array |
| `array.new_fixed x n` | `0xFB 0x08` | Create array from n stack values |
| `array.new_data x y` | `0xFB 0x09` | Create array from data segment |
| `array.new_elem x y` | `0xFB 0x0A` | Create array from element segment |
| `array.get x` | `0xFB 0x0B` | Get array element |
| `array.get_s x` | `0xFB 0x0C` | Get signed packed element |
| `array.get_u x` | `0xFB 0x0D` | Get unsigned packed element |
| `array.set x` | `0xFB 0x0E` | Set array element |
| `array.len` | `0xFB 0x0F` | Get array length |
| `array.fill x` | `0xFB 0x10` | Fill array range |
| `array.copy x y` | `0xFB 0x11` | Copy between arrays |
| `array.init_data x y` | `0xFB 0x12` | Init array from data segment |
| `array.init_elem x y` | `0xFB 0x13` | Init array from element segment |
| `ref.test (ref t)` | `0xFB 0x14` | Test reference type (non-null) |
| `ref.test (ref null t)` | `0xFB 0x15` | Test reference type (nullable) |
| `ref.cast (ref t)` | `0xFB 0x16` | Cast reference (non-null) |
| `ref.cast (ref null t)` | `0xFB 0x17` | Cast reference (nullable) |
| `br_on_cast` | `0xFB 0x18` | Branch on successful cast |
| `br_on_cast_fail` | `0xFB 0x19` | Branch on failed cast |
| `any.convert_extern` | `0xFB 0x1A` | Convert externref to anyref |
| `extern.convert_any` | `0xFB 0x1B` | Convert anyref to externref |
| `ref.i31` | `0xFB 0x1C` | Box i32 as i31ref |
| `i31.get_s` | `0xFB 0x1D` | Unbox i31ref (signed) |
| `i31.get_u` | `0xFB 0x1E` | Unbox i31ref (unsigned) |

**Type definition encoding (new composite types):**
```
struct fieldtype*     = 0x5F (-33)
array fieldtype       = 0x5E (-34)
sub typeidx* comptype = 0x50 (-48)    -- non-final subtype
sub final ...         = 0x4F (-49)    -- final subtype
rec subtype*          = 0x4E (-50)    -- recursive type group
```

**Packed types (for struct/array fields):**
```
i8  = 0x78 (-8)
i16 = 0x77 (-9)
```

### Extended Constant Expressions

These are now valid in constant expressions (global initializers, segment offsets):
```
i32.add (0x6A), i32.sub (0x6B), i32.mul (0x6C)
i64.add (0x7C), i64.sub (0x7D), i64.mul (0x7E)
global.get (any immutable global, not just imports)
```

Plus GC constant instructions: `ref.i31`, `struct.new`, `struct.new_default`, `array.new`, `array.new_default`, `array.new_fixed`, `any.convert_extern`, `extern.convert_any`.

---

## Module Binary Format — Complete Section Layout

```
Module layout (section IDs):
  0  - Custom section (can appear anywhere)
  1  - Type section
  2  - Import section
  3  - Function section
  4  - Table section
  5  - Memory section
  6  - Global section
  7  - Export section
  8  - Start section
  9  - Element section
  10 - Code section
  11 - Data section
  12 - Data count section (Wasm 2.0+)
  13 - Tag section (NEW in Wasm 3.0)
```

**Tag section placement:** After global section (6), before export section (7).

**Import/export kinds:**
```
0x00 - func
0x01 - table
0x02 - mem
0x03 - global
0x04 - tag (NEW in 3.0)
```

---

## Adoption Plan for Cot

### Phase 1: Immediate (within 0.3)
- **Nothing required.** Current Wasm 1.0 output continues to work.
- All 3.0 features are additive — they don't break existing code.

### Phase 2: Near-term (0.3 improvements)
- `return_call` for tail-position calls (opcode 0x12)
- `call_ref` for closure calls (opcode 0x14, requires type section changes)
- Tag section + `try_table` for robust defer-across-calls

### Phase 3: When needed
- Multiple memories (separate heap/metadata)
- 64-bit memory (server workloads >4GB)
- GC types (interop with Kotlin/Wasm, Dart/Wasm)

### Files to modify when adopting 3.0 features:
```
compiler/codegen/wasm/gen.zig         — emit new opcodes
compiler/codegen/wasm/link.zig        — tag section, type section changes
compiler/codegen/wasm/assemble.zig    — new instruction encoding
compiler/codegen/wasm_opcodes.zig     — opcode constants
compiler/codegen/native/wasm_parser.zig — parse new opcodes/sections
compiler/codegen/native/wasm_to_clif/decoder.zig    — decode new instructions
compiler/codegen/native/wasm_to_clif/translator.zig — translate to CLIF
compiler/ssa/op.zig                   — new SSA ops if needed
compiler/ssa/passes/lower_wasm.zig    — new lowering rules
```
