# Audit: amd64_asm.zig

## Status: VERIFIED CORRECT

| Metric | Value |
|--------|-------|
| 0.2 lines | 1,628 |
| 0.3 lines | 1,628 |
| Reduction | 0% (direct copy with import fix) |
| Tests | 13/13 pass |

---

## Purpose

AMD64/x86-64 instruction encoding. Encodes x86-64 instructions into variable-length machine code bytes following Intel's instruction format.

---

## Key Changes

### Import Path Update

```zig
// Old
const regs = @import("regs.zig");

// New
const regs = @import("amd64_regs.zig");
```

---

## Key Components

### REX Prefix Generation

| Function | Description |
|----------|-------------|
| rex | Build REX prefix with W/R/X/B bits |
| rexW | REX.W prefix (64-bit operand) |
| needsREX | Check if instruction needs REX |

### ModR/M Encoding

| Function | Description |
|----------|-------------|
| modrm | Encode ModR/M byte |
| modrmReg | Register-to-register |
| modrmMem | Memory operand |
| modrmDisp | Memory with displacement |

### Instruction Categories

| Category | Functions |
|----------|-----------|
| Move | MOV (reg-reg, reg-imm, reg-mem) |
| Arithmetic | ADD, SUB, IMUL, IDIV, NEG |
| Logic | AND, OR, XOR, NOT |
| Shift | SHL, SHR, SAR |
| Compare | CMP, TEST |
| Control | JMP, Jcc, CALL, RET |
| Stack | PUSH, POP |
| Misc | LEA, NOP, INT3 |

### Emitter Struct

| Method | Description |
|--------|-------------|
| init | Initialize with allocator |
| deinit | Free code buffer |
| emit | Append byte |
| emitU32LE | Append 32-bit little-endian |
| emitU64LE | Append 64-bit little-endian |
| patch | Patch bytes at offset |
| getCode | Get generated code slice |

---

## x86-64 Instruction Format

```
[Legacy Prefixes] [REX] [Opcode] [ModR/M] [SIB] [Displacement] [Immediate]
     0-4 bytes    0-1     1-3      0-1     0-1      0-4           0-8
```

---

## Verification

```bash
zig build test
# 13 tests from amd64_asm.zig pass
```

**VERIFIED: Logic 100% identical. Import path updated. 13 tests pass.**
