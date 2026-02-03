# Phase 7: Integration Execution Plan

**Last Updated**: 2026-02-03 (Full Audit + Root Cause Analysis)
**Status**: In Progress - Root Cause Identified

---

## Executive Summary

The native codegen pipeline is wired but crashes on simple programs. Root cause: `toBasicOperator()` skips global variable operations (`global.get`, `global.set`), causing stack underflow when translating Wasm functions that use stack pointer manipulation.

---

## Part 1: Root Cause Analysis

### The Crash

```bash
$ echo 'fn main() i32 { return 42; }' | cot -
panic: integer overflow in stack.zig:289 (stack underflow in peek1)
```

### Why It Happens

1. Cot generates Wasm that uses `global.get 0` (stack pointer)
2. `decoder.zig` decodes `global.get` into WasmOp
3. `toBasicOperator()` returns `null` for `global.get` (not implemented)
4. The operator is skipped in driver.zig line 407
5. Subsequent operators expect a value on stack → **underflow**

### Proof

```
[codegen] driver: translating function 0
[codegen] driver: decoded 26 operators
panic: stack underflow
```

Function 0 (likely ARC runtime) uses globals. When globals are skipped, the stack state is corrupted.

---

## Part 2: Cranelift Port Audit (Verified)

### Line Counts (Actual vs Documented)

| Component | Actual LOC | Old Doc LOC | Difference |
|-----------|------------|-------------|------------|
| CLIF IR | 5,149 | 4,954 | +195 |
| Wasm→CLIF | 2,950 | 1,962 | +988 |
| MachInst | 9,365 | ~9,000 | +365 |
| ARM64 | 12,283 | ~8,500 | +3,783 |
| x64 | 11,957 | ~8,400 | +3,557 |
| Regalloc | 11,011 | ~6,400 | +4,611 |
| Frontend | 1,628 | ~1,200 | +428 |
| **TOTAL** | **~55,089** | ~41,135 | **+13,954** |

### Parity Status

| Component | Status | Blocking Issues |
|-----------|--------|-----------------|
| CLIF IR | 100% ✅ | None |
| Wasm→CLIF | **~40%** ❌ | Missing: globals, memory, calls, floats, i64 |
| MachInst | 95% ✅ | Placeholder prologue/epilogue |
| ARM64 | 90% ✅ | Call lowering placeholders |
| x64 | 85% ✅ | Regalloc handling incomplete |
| Regalloc | 100% ✅ | None |

---

## Part 3: Systematic Task Execution

### Task 7.1: Add Global Variable Support [BLOCKING]

**Status**: ❌ Not Started
**Priority**: P0 - Must fix first
**Estimated Scope**: ~50 lines

#### Cranelift Reference

**File**: `~/learning/wasmtime/crates/cranelift/src/translate/code_translator.rs`

```rust
// Lines 202-213
Operator::GlobalGet { global_index } => {
    environ.translate_global_get(builder, srcloc, *global_index)?;
}
Operator::GlobalSet { global_index } => {
    environ.translate_global_set(builder, srcloc, *global_index)?;
}
```

**File**: `~/learning/wasmtime/crates/cranelift/src/translate/environ/spec.rs`

```rust
fn translate_global_get(&mut self, ...) -> ... {
    // Load from global memory location
}
```

#### Implementation Steps

**Step 1.1**: Add to `toBasicOperator()` in `decoder.zig`

```zig
// Line ~296, after local_tee
.global_get => |d| WasmOperator{ .global_get = d },
.global_set => |d| WasmOperator{ .global_set = d },
```

**Step 1.2**: Add to `WasmOperator` enum in `func_translator.zig`

```zig
// In WasmOperator union
global_get: u32,
global_set: u32,
```

**Step 1.3**: Add translation case in `func_translator.zig:translateOperator()`

```zig
.global_get => |idx| try translator.translateGlobalGet(idx),
.global_set => |idx| try translator.translateGlobalSet(idx),
```

**Step 1.4**: Implement in `translator.zig`

```zig
pub fn translateGlobalGet(self: *Self, global_index: u32) !void {
    // For now, treat globals as memory locations
    // Load from global address = global_base + global_index * 8
    const global_addr = try self.builder.ins().iconst(Type.I64, @intCast(global_index * 8));
    const value = try self.builder.ins().load(Type.I64, .{}, global_addr, 0);
    try self.state.push1(value);
}

pub fn translateGlobalSet(self: *Self, global_index: u32) !void {
    const value = self.state.pop1();
    const global_addr = try self.builder.ins().iconst(Type.I64, @intCast(global_index * 8));
    _ = try self.builder.ins().store(.{}, value, global_addr, 0);
}
```

#### Verification

```bash
# Should no longer crash with stack underflow
echo 'fn main() i32 { return 42; }' | cot -
```

---

### Task 7.2: Add Memory Instructions [HIGH PRIORITY]

**Status**: ❌ Not Started
**Priority**: P1
**Estimated Scope**: ~150 lines

#### Cranelift Reference

**File**: `~/learning/wasmtime/crates/cranelift/src/translate/code_translator.rs:3680-3724`

```rust
fn translate_load(
    memarg: &MemArg,
    opcode: ir::Opcode,
    result_ty: Type,
    builder: &mut FunctionBuilder,
    environ: &mut FuncEnvironment<'_>,
) -> WasmResult<Reachability<()>> {
    let (flags, wasm_index, base) = prepare_addr(memarg, ...)?;
    let (load, dfg) = builder.ins().Load(opcode, result_ty, flags, Offset32::new(0), base);
    environ.stacks.push1(dfg.first_result(load));
    Ok(Reachability::Reachable(()))
}

fn translate_store(
    memarg: &MemArg,
    opcode: ir::Opcode,
    builder: &mut FunctionBuilder,
    environ: &mut FuncEnvironment<'_>,
) -> WasmResult<()> {
    let val = environ.stacks.pop1();
    let (flags, wasm_index, base) = prepare_addr(memarg, ...)?;
    builder.ins().Store(opcode, val_ty, flags, Offset32::new(0), val, base);
    Ok(())
}
```

#### Implementation Steps

**Step 2.1**: Add MemArg to WasmOperator in `func_translator.zig`

```zig
pub const MemArg = struct {
    align_: u32,
    offset: u32,
};

pub const WasmOperator = union(enum) {
    // ... existing fields ...
    i32_load: MemArg,
    i64_load: MemArg,
    f32_load: MemArg,
    f64_load: MemArg,
    i32_store: MemArg,
    i64_store: MemArg,
    f32_store: MemArg,
    f64_store: MemArg,
    // Add load variants (i32_load8_s, etc.)
};
```

**Step 2.2**: Add to `toBasicOperator()` in `decoder.zig`

```zig
.i32_load => |d| WasmOperator{ .i32_load = .{ .align_ = d.align_, .offset = d.offset } },
.i64_load => |d| WasmOperator{ .i64_load = .{ .align_ = d.align_, .offset = d.offset } },
// ... etc for all memory ops
```

**Step 2.3**: Add translation cases in `func_translator.zig`

```zig
.i32_load => |m| try translator.translateLoad(Type.I32, m),
.i64_load => |m| try translator.translateLoad(Type.I64, m),
.i32_store => |m| try translator.translateStore(Type.I32, m),
// ... etc
```

**Step 2.4**: Implement in `translator.zig`

```zig
pub fn translateLoad(self: *Self, ty: Type, memarg: MemArg) !void {
    const addr = self.state.pop1();
    // Add offset to address
    const offset_val = try self.builder.ins().iconst(Type.I64, @intCast(memarg.offset));
    const effective_addr = try self.builder.ins().iadd(addr, offset_val);
    const value = try self.builder.ins().load(ty, .{}, effective_addr, 0);
    try self.state.push1(value);
}

pub fn translateStore(self: *Self, ty: Type, memarg: MemArg) !void {
    const value = self.state.pop1();
    const addr = self.state.pop1();
    const offset_val = try self.builder.ins().iconst(Type.I64, @intCast(memarg.offset));
    const effective_addr = try self.builder.ins().iadd(addr, offset_val);
    _ = try self.builder.ins().store(.{}, value, effective_addr, 0);
}
```

#### Verification

```bash
# Test with memory operations
echo 'fn main() i32 { var x: i32 = 42; return x; }' | cot -
```

---

### Task 7.3: Add Call Instructions [HIGH PRIORITY]

**Status**: ❌ Not Started
**Priority**: P1
**Estimated Scope**: ~100 lines

#### Cranelift Reference

**File**: `~/learning/wasmtime/crates/cranelift/src/translate/code_translator.rs:654-677`

```rust
Operator::Call { function_index } => {
    let (_, num_args) = environ.translate_call(builder, srcloc, function_index, sig_ref, &args)?;
    // Push results onto stack
}
```

#### Implementation Steps

**Step 3.1**: Add to WasmOperator

```zig
call: u32,  // function index
call_indirect: CallIndirectData,
```

**Step 3.2**: Add to `toBasicOperator()`

```zig
.call => |d| WasmOperator{ .call = d },
.call_indirect => |d| WasmOperator{ .call_indirect = d },
```

**Step 3.3**: Implement translateCall

```zig
pub fn translateCall(self: *Self, func_index: u32) !void {
    // Get function signature from module
    // Pop args from stack
    // Emit call instruction
    // Push results
}
```

---

### Task 7.4: Add i64 Arithmetic [MEDIUM PRIORITY]

**Status**: ❌ Not Started
**Priority**: P2
**Estimated Scope**: ~50 lines

#### Implementation

Add to `toBasicOperator()` and translator:
- i64_add, i64_sub, i64_mul, i64_div_s, i64_div_u
- i64_rem_s, i64_rem_u, i64_and, i64_or, i64_xor
- i64_shl, i64_shr_s, i64_shr_u
- i64_eq, i64_ne, i64_lt_s, etc.

These follow exact same pattern as i32 ops.

---

### Task 7.5: Add Float Operations [LOW PRIORITY]

**Status**: ❌ Not Started
**Priority**: P3
**Estimated Scope**: ~100 lines

Add f32 and f64 arithmetic, comparison, and conversion operations.

---

### Task 7.6: Fix Object File Generation [MEDIUM PRIORITY]

**Status**: ❌ Not Started
**Priority**: P2
**Estimated Scope**: ~50 lines

**Current State**: `generateMachO()` and `generateElf()` return raw bytes

**Required**:
1. Wire `macho.zig` for proper Mach-O generation
2. Wire `elf.zig` for proper ELF generation
3. Add symbol tables

---

### Task 7.7: End-to-End Tests

**Blocked by**: Tasks 7.1-7.3

| Test | Description | Status |
|------|-------------|--------|
| 7.7a | `return 42` | ❌ Blocked by 7.1 |
| 7.7b | `return 10 + 32` | ❌ Blocked by 7.1 |
| 7.7c | `if (true) { return 1; }` | ❌ Blocked by 7.1 |
| 7.7d | Function calls | ❌ Blocked by 7.3 |

---

### Task 7.8: Remove Legacy Code

**Blocked by**: Task 7.7 (all tests passing)

Remove:
- `codegen/native/arm64_asm.zig`
- `codegen/native/amd64_asm.zig`
- `codegen/native/amd64_regs.zig`
- `codegen/native/abi.zig`

---

## Part 4: Execution Order

```
PHASE 1: UNBLOCK (Task 7.1)
├── Add global_get/global_set to toBasicOperator
├── Add translation methods
├── Verify: no more stack underflow
│
PHASE 2: CORE WASM OPS (Tasks 7.2-7.4)
├── Memory instructions (load/store)
├── Call instructions
├── i64 arithmetic
│
PHASE 3: COMPLETENESS (Tasks 7.5-7.6)
├── Float operations
├── Object file generation
│
PHASE 4: VERIFICATION (Task 7.7)
├── return 42
├── Arithmetic
├── Control flow
├── Function calls
│
PHASE 5: CLEANUP (Task 7.8)
└── Remove legacy code
```

---

## Part 5: Checklist

### Task 7.1: Global Variables - COMPLETE
- [x] Add `global_get` to `toBasicOperator()` in decoder.zig
- [x] Add `global_set` to `toBasicOperator()` in decoder.zig
- [x] Add `global_get` to WasmOperator enum in func_translator.zig
- [x] Add `global_set` to WasmOperator enum in func_translator.zig
- [x] Add translation case for `global_get` in translateOperator
- [x] Add translation case for `global_set` in translateOperator
- [x] Implement `translateGlobalGet()` in translator.zig (with proper type lookup from module)
- [x] Implement `translateGlobalSet()` in translator.zig
- [x] Test: Stack underflow panic fixed, all 7 functions translate to CLIF

**Additional work completed:**
- [x] Added unreachable code handling (translateUnreachableBlock, translateUnreachableIf)
- [x] Added multi-byte opcode (0xFC prefix) handling for memory.copy/memory.fill
- [x] Added WasmGlobalType struct for passing module globals to translator
- [x] Updated driver to convert and pass globals to translator

### Task 7.2: Memory Instructions
- [ ] Add MemArg struct to func_translator.zig
- [ ] Add all load variants to WasmOperator
- [ ] Add all store variants to WasmOperator
- [ ] Add to toBasicOperator() for each memory op
- [ ] Add translation cases
- [ ] Implement translateLoad()
- [ ] Implement translateStore()
- [ ] Test with memory-using code

### Task 7.3: Call Instructions
- [ ] Add call to WasmOperator
- [ ] Add call_indirect to WasmOperator
- [ ] Add to toBasicOperator()
- [ ] Implement translateCall()
- [ ] Implement translateCallIndirect()
- [ ] Test with function calls

### Task 7.4: i64 Arithmetic
- [ ] Add all i64 ops to toBasicOperator()
- [ ] Add translation methods
- [ ] Test

### Task 7.5: Float Operations
- [ ] Add f32/f64 ops to toBasicOperator()
- [ ] Add translation methods
- [ ] Test

### Task 7.6: Object Files
- [ ] Wire macho.zig properly
- [ ] Wire elf.zig properly
- [ ] Add symbol tables

### Task 7.7: End-to-End Tests
- [ ] return 42 works
- [ ] Arithmetic works
- [ ] Control flow works
- [ ] Function calls work

### Task 7.8: Cleanup
- [ ] All tests pass
- [ ] Remove legacy files

---

## Appendix: Cranelift Source References

| Topic | File | Lines |
|-------|------|-------|
| Global get/set | code_translator.rs | 202-213 |
| Memory load | code_translator.rs | 3680-3700 |
| Memory store | code_translator.rs | 3703-3724 |
| Call | code_translator.rs | 654-677 |
| Call indirect | code_translator.rs | 677-714 |
| Stack management | stack.rs | - |
| Function init | func_translator.rs | 71-131 |
