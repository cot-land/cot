# @trap Builtin Design

**Date:** February 2026
**Status:** Not implemented
**Priority:** LOW (existing `@assert` covers most use cases)
**Estimated effort:** Small (< 1 hour)

---

## Motivation

Cot currently has `@assert(cond)` which writes an error message to stderr and calls
`exit(1)` on failure. This is fine for user-facing bounds checks.

`@trap` is different: it's an unconditional abort that signals a compiler/runtime
invariant violation. It maps directly to hardware trap instructions.

| | `@assert(cond)` | `@trap` |
|---|---|---|
| **Conditional** | Yes (checks a condition) | No (always traps) |
| **Error message** | Yes (writes to stderr) | No (immediate halt) |
| **Use case** | User input validation, bounds checks | Unreachable code, invariant violations |
| **Wasm** | `call write; call exit` | `unreachable` instruction |
| **Native** | `call write; call exit` | `ud2` (x64) / `brk #1` (ARM64) |
| **Overhead** | Function calls + string formatting | Single instruction |

### Where @trap is needed

```cot
fn getVariant(u: MyUnion) i64 {
    switch u {
        MyUnion.A |val| => { return val },
        MyUnion.B |val| => { return val },
    }
    // Should be unreachable if all variants are covered
    @trap  // <-- compiler invariant: switch was exhaustive
}

fn divmod(a: i64, b: i64) i64 {
    if b == 0 { @trap }  // Division by zero is a hard error, not a recoverable assert
    return a / b
}
```

---

## Reference Implementations

### Zig: `unreachable`

Zig's `unreachable` is a keyword (not a builtin) that:
- In debug/safe modes: calls `@panic("reached unreachable code")`
- In release modes: undefined behavior (optimizer assumes dead code)
- Compiles to `ud2` on x64, trap on ARM64, `unreachable` on Wasm

### Go: no equivalent

Go doesn't have an `unreachable` statement. It uses `panic("unreachable")` by convention.

### Wasm: `unreachable` instruction

Opcode `0x00`. Immediately traps the Wasm instance. Execution cannot continue.
The host runtime decides what happens (JavaScript gets a `RuntimeError`).

### C: `__builtin_unreachable()` / `__builtin_trap()`

- `__builtin_unreachable()`: UB hint to optimizer (no code emitted)
- `__builtin_trap()`: emits trap instruction (`ud2` on x86)

---

## Design

### Syntax

```cot
@trap
```

No arguments. No return value. Control flow does not continue past `@trap`.

### Semantics

- Immediately halts execution
- On Wasm: emits `unreachable` instruction
- On native x64: emits `ud2` (SIGILL)
- On native ARM64: emits `brk #1` (SIGTRAP)
- Marks the current basic block as terminated (no fall-through)

### Why not `unreachable` keyword?

Cot could add `unreachable` as a keyword instead. But:
1. `@trap` is consistent with the `@builtin` pattern
2. A keyword requires scanner/parser changes; a builtin doesn't
3. `@trap` is unambiguous about what it does (traps). `unreachable` has
   conflicting semantics across languages (UB hint vs actual trap).

**Decision:** `@trap` builtin. If we later want `unreachable` as a keyword
with optimizer hints (dead code elimination), that's a separate feature.

---

## Implementation Plan

### 1. Scanner/Parser

No changes. `@trap` uses existing builtin call syntax with 0 arguments.

### 2. Checker (`compiler/frontend/checker.zig`)

Add to `checkBuiltinCall`:

```zig
if (std.mem.eql(u8, bc.name, "trap")) {
    if (bc.args.len != 0) return error.WrongArgCount;
    return TypeRegistry.VOID;
}
```

### 3. Lowerer (`compiler/frontend/lower.zig`)

Add to `lowerBuiltinCall`:

```zig
if (std.mem.eql(u8, bc.name, "trap")) {
    return try fb.emitTrap(bc.span);
}
```

This requires adding `emitTrap` to the IR builder, which emits an `unreachable` SSA op.

### 4. SSA

Add `trap` op to the SSA op enum if it doesn't exist. This op:
- Takes no arguments
- Has no result
- Terminates the block

### 5. Wasm Backend

The `trap` SSA op lowers to Wasm `unreachable` instruction (opcode `0x00`).

Check if this already exists in the Wasm lowering. The Wasm spec's `unreachable`
instruction should already be supported since it's a basic control flow op.

### 6. Native Backend

The `trap` op lowers to:
- ARM64: `brk #1` (breakpoint trap, caught as SIGTRAP)
- x64: `ud2` (undefined instruction, caught as SIGILL)

These are single instructions. Check if the machine instruction types already exist
in `isa/aarch64/inst/mod.zig` and `isa/x64/inst/mod.zig`.

---

## Test Plan

### E2E Tests

```cot
// Test that @trap causes non-zero exit (process killed by signal)
fn test_trap() i64 {
    @trap
    return 0  // unreachable
}
// Expected: exit code != 0 (signal death)

// Test that @trap after condition works
fn test_conditional_trap() i64 {
    let x = 42
    if x == 0 { @trap }
    return 0
}
// Expected: exit code 0 (trap not reached)
```

The native E2E test harness already handles signal-based termination:
```zig
.Signal => |sig| blk: {
    const msg = std.fmt.allocPrint(allocator, "signal {d}", .{sig}) catch "signal";
    break :blk NativeResult.runErr(msg);
},
```

We can test that `@trap` produces a signal exit, or simply verify the non-trap path works.

---

## Files to Modify

| File | Change |
|------|--------|
| `compiler/frontend/checker.zig` | Add `trap` case to `checkBuiltinCall` (~3 lines) |
| `compiler/frontend/lower.zig` | Add `trap` case to `lowerBuiltinCall` (~2 lines) |
| `compiler/frontend/ir.zig` | Add `emitTrap` to IR builder if needed (~5 lines) |
| `compiler/ssa/` | Add `trap` op if not present (~2 lines) |
| `compiler/ssa/passes/lower_wasm.zig` | Lower `trap` to Wasm `unreachable` (~3 lines) |
| `compiler/codegen/native/` | Lower `trap` to `brk`/`ud2` (~5 lines) |
| Test files | Add E2E tests |

**Total code change: ~20 lines of compiler code + test cases**
