# Wasm Backend Execution Plan

This document details how we will implement the Wasm backend for the Cot compiler.

---

## Overview

**Input:** Cot IR (from `compiler/frontend/ir.zig`)
**Output:** WebAssembly binary (`.wasm` file)

```
Cot Source → Scanner → Parser → Checker → Lowerer → IR → [Wasm Codegen] → .wasm
                                                              ↑
                                                         THIS DOCUMENT
```

---

## Wasm Binary Format

A Wasm module consists of sections, each with a specific ID:

```
┌────────────────────────────────────────┐
│  Magic Number (0x00 0x61 0x73 0x6D)    │  4 bytes
│  Version (0x01 0x00 0x00 0x00)         │  4 bytes
├────────────────────────────────────────┤
│  Section 1: Type (0x01)                │  Function signatures
│  Section 2: Import (0x02)              │  External functions
│  Section 3: Function (0x03)            │  Function index → type index
│  Section 5: Memory (0x05)              │  Linear memory declaration
│  Section 7: Export (0x07)              │  Public functions
│  Section 10: Code (0x0A)               │  Function bodies (bytecode)
│  Section 11: Data (0x0B)               │  Static data (strings, etc.)
└────────────────────────────────────────┘
```

---

## File Structure

```
compiler/codegen/
├── wasm.zig           # Main Wasm codegen (orchestrates everything)
├── wasm_encode.zig    # Binary encoding helpers (LEB128, sections)
├── wasm_opcodes.zig   # Wasm instruction constants
└── wasm_runtime.zig   # ARC runtime functions (future)
```

---

## Implementation Phases

### Phase 1: Binary Format Foundation

**Goal:** Emit a valid but minimal `.wasm` file

**Files to create:**
- `compiler/codegen/wasm_opcodes.zig` - Opcode constants
- `compiler/codegen/wasm_encode.zig` - Binary encoding

**Key tasks:**

1. **LEB128 encoding** (Wasm's variable-length integers)
   ```zig
   fn encodeULEB128(writer: anytype, value: u64) !void
   fn encodeSLEB128(writer: anytype, value: i64) !void
   ```

2. **Section encoding**
   ```zig
   fn writeSection(writer: anytype, section_id: u8, content: []const u8) !void
   ```

3. **Type encoding**
   ```zig
   const ValType = enum(u8) { i32 = 0x7F, i64 = 0x7E, f32 = 0x7D, f64 = 0x7C };
   fn writeFuncType(writer: anytype, params: []ValType, results: []ValType) !void
   ```

**Test:** Generate minimal valid Wasm, validate with `wasm-validate`

```zig
test "emit minimal wasm module" {
    // Module that exports: fn answer() i64 { return 42; }
    var output = std.ArrayList(u8).init(allocator);
    try emitMinimalModule(&output);
    // Validate with wasmtime or wasm-tools
}
```

---

### Phase 2: IR → Wasm Translation

**Goal:** Translate Cot IR operations to Wasm stack instructions

**File to create:**
- `compiler/codegen/wasm.zig` - Main codegen

**IR to Wasm mapping:**

| Cot IR | Wasm Instruction | Notes |
|--------|------------------|-------|
| `const_int` | `i64.const` | |
| `const_float` | `f64.const` | |
| `const_bool` | `i32.const 0/1` | Bools are i32 in Wasm |
| `load_local` | `local.get` | |
| `store_local` | `local.set` / `local.tee` | |
| `binary(add)` | `i64.add` / `f64.add` | Type-dependent |
| `binary(sub)` | `i64.sub` / `f64.sub` | |
| `binary(mul)` | `i64.mul` / `f64.mul` | |
| `binary(div)` | `i64.div_s` / `f64.div` | Signed for ints |
| `binary(mod)` | `i64.rem_s` | |
| `binary(eq)` | `i64.eq` / `f64.eq` | |
| `binary(lt)` | `i64.lt_s` / `f64.lt` | |
| `unary(neg)` | `i64.const 0` + `i64.sub` | No direct neg in Wasm |
| `unary(not)` | `i32.eqz` | |
| `call` | `call $func_idx` | |
| `ret` | `return` | Or implicit at end |

**Control flow:**

| Cot IR | Wasm | Notes |
|--------|------|-------|
| `jump` | `br` | Branch to label |
| `branch` | `br_if` / `if-else` | |
| `phi` | N/A | Handled via locals |

**Phi elimination strategy:**
Wasm doesn't have phi nodes. Convert to explicit local assignments:

```
IR:                          Wasm:
b1:                          (block $b1
  ...                          ...
  jump b3                      local.set $phi_x
                               br $b3)
b2:                          (block $b2
  ...                          ...
  jump b3                      local.set $phi_x
                               br $b3)
b3:                          (block $b3
  x = phi(b1: v1, b2: v2)      local.get $phi_x
  ...                          ...)
```

**Test:** Compile `fn add(a: i64, b: i64) i64 { return a + b }`, run in wasmtime

---

### Phase 3: Function Compilation

**Goal:** Compile complete functions with locals and control flow

**Key tasks:**

1. **Local variable mapping**
   - Map IR locals to Wasm locals
   - Track types for each local

2. **Function prologue/epilogue**
   ```wasm
   (func $add (param $a i64) (param $b i64) (result i64)
     (local $temp i64)  ;; Any additional locals
     ;; body
   )
   ```

3. **Control flow graph → Wasm structured control**

   Wasm requires structured control flow (no arbitrary gotos). Strategy:
   - Analyze CFG
   - Identify loops (back edges)
   - Convert to nested `block`/`loop`/`if` structure

   ```
   IR CFG:                 Wasm:
   ┌──→ header ──┐         (loop $loop
   │      ↓      │           (block $exit
   │    body ────┘             header...
   │      ↓                    br_if $exit (condition)
   └── latch                   body...
         ↓                     br $loop))
       exit
   ```

**Test:** Compile factorial function, verify correct output

---

### Phase 4: Memory and Data

**Goal:** Handle strings, arrays, and heap allocation

**Memory layout:**
```
┌─────────────────────────────────────────────────┐
│  0x0000: Static data (strings, globals)         │
│  ...                                            │
│  HEAP_START: Dynamic allocations →              │
│                                                 │
│                              ← STACK_START      │
│  STACK grows down (if needed for nested calls)  │
└─────────────────────────────────────────────────┘
```

**String handling:**
- Strings stored in Data section
- Runtime representation: `{ ptr: i32, len: i32 }`

**Data section encoding:**
```zig
fn emitDataSection(strings: []const []const u8) ![]u8 {
    // For each string:
    // - Offset in linear memory
    // - Bytes
}
```

**Test:** Compile program with string literal, verify in memory

---

### Phase 5: Imports and Exports

**Goal:** Interface with host environment

**Required imports for runtime:**
```wasm
(import "env" "print_i64" (func $print_i64 (param i64)))
(import "env" "print_str" (func $print_str (param i32 i32)))  ;; ptr, len
```

**Exports:**
```wasm
(export "main" (func $main))
(export "memory" (memory 0))
```

**Test:** Call imported print function from Cot code

---

### Phase 6: ARC Runtime

**Goal:** Automatic reference counting for heap objects

**Runtime functions (compiled into Wasm):**
```
cot_alloc(size: i32) -> i32      // Returns pointer
cot_free(ptr: i32)               // Free memory
cot_retain(ptr: i32)             // Increment refcount
cot_release(ptr: i32)            // Decrement, free if zero
```

**Object header:**
```
┌──────────────────────────────┐
│  refcount: i32               │  4 bytes
│  size: i32                   │  4 bytes
├──────────────────────────────┤
│  payload...                  │
└──────────────────────────────┘
```

**Compiler inserts retain/release:**
```cot
fn example(s: string) {     // retain(s) inserted at entry
    let s2 = s              // retain(s) for copy
    ...
}                           // release(s2), release(s) at exit
```

**Test:** Verify refcount increments/decrements correctly

---

## Milestone Checklist

### Milestone 1: "Hello Wasm"
- [ ] `wasm_opcodes.zig` with basic opcodes
- [ ] `wasm_encode.zig` with LEB128, section encoding
- [ ] Emit valid minimal module (empty function)
- [ ] Validate with `wasm-validate` or `wasmtime`

### Milestone 2: "Return 42"
- [ ] Type section encoding
- [ ] Function section encoding
- [ ] Code section with `i64.const 42` + `return`
- [ ] Export section
- [ ] Run in wasmtime, verify returns 42

### Milestone 3: "Add Two Numbers"
- [ ] Parameter handling (`local.get`)
- [ ] Binary operations (`i64.add`, etc.)
- [ ] Compile: `fn add(a: i64, b: i64) i64 { return a + b }`
- [ ] Run in wasmtime with arguments

### Milestone 4: "Control Flow"
- [ ] If/else → Wasm `if`/`else`/`end`
- [ ] While loops → Wasm `loop`/`block`/`br`
- [ ] Compile: factorial function
- [ ] Verify correct output

### Milestone 5: "Strings"
- [ ] Data section for string literals
- [ ] String runtime representation
- [ ] Import print function
- [ ] Compile: `print("Hello, World!")`

### Milestone 6: "Memory"
- [ ] Heap allocator in Wasm
- [ ] ARC runtime functions
- [ ] Compile program with dynamic allocation
- [ ] Verify no memory leaks

---

## Testing Strategy

**Unit tests:** Each encoding function tested in isolation

**Integration tests:**
1. Compile Cot source
2. Emit `.wasm`
3. Run with wasmtime
4. Verify output

**Test runner:**
```bash
# In CI or locally
zig build test                           # Unit tests
./test_wasm.sh                           # Integration tests
wasmtime run output.wasm --invoke main   # Manual verification
```

---

## Dependencies

**Build time:**
- None (pure Zig)

**Test time:**
- `wasmtime` or `wasmer` for running Wasm
- `wasm-tools` for validation (optional)

**Runtime (for Cot programs):**
- Browser: Native Wasm support
- Server: wasmtime, wasmer, or AOT-compiled native

---

## Reference

- [Wasm Binary Format Spec](https://webassembly.github.io/spec/core/binary/index.html)
- [Wasm Instructions](https://webassembly.github.io/spec/core/syntax/instructions.html)
- [LEB128 Encoding](https://en.wikipedia.org/wiki/LEB128)
- `bootstrap-0.2/DESIGN.md` - Architecture context
