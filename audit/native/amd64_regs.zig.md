# Audit: amd64_regs.zig

## Status: VERIFIED CORRECT

| Metric | Value |
|--------|-------|
| 0.2 lines | 218 |
| 0.3 lines | 218 |
| Reduction | 0% (direct copy) |
| Tests | 3/3 pass |

---

## Purpose

AMD64/x86-64 register definitions and utilities. Provides register enum with encoding values for instruction generation.

---

## Key Components

### Reg Enum

| Category | Registers | Encoding |
|----------|-----------|----------|
| Accumulator | rax, eax, ax, al | 0 |
| Counter | rcx, ecx, cx, cl | 1 |
| Data | rdx, edx, dx, dl | 2 |
| Base | rbx, ebx, bx, bl | 3 |
| Stack Pointer | rsp, esp, sp, spl | 4 |
| Base Pointer | rbp, ebp, bp, bpl | 5 |
| Source Index | rsi, esi, si, sil | 6 |
| Dest Index | rdi, edi, di, dil | 7 |
| Extended | r8-r15 | 8-15 |

### Helper Methods

| Method | Description |
|--------|-------------|
| encoding | Returns 3-bit register encoding (0-7) |
| needsREX | Returns true if register needs REX prefix |
| isExtended | Returns true for r8-r15 |

### Calling Convention (System V AMD64 ABI)

| Usage | Registers |
|-------|-----------|
| Arguments | rdi, rsi, rdx, rcx, r8, r9 |
| Return | rax |
| Callee-saved | rbx, rbp, r12-r15 |
| Caller-saved | rax, rcx, rdx, rsi, rdi, r8-r11 |

---

## Verification

```bash
zig build test
# Tests pass
```

**VERIFIED: Logic 100% identical. 3 tests pass.**
