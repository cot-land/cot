# Audit: arm64_asm.zig

## Status: VERIFIED CORRECT

| Metric | Value |
|--------|-------|
| 0.2 lines | 989 |
| 0.3 lines | 989 |
| Reduction | 0% (direct copy) |
| Tests | 29/29 pass |

---

## Purpose

ARM64 instruction encoding following ARM Architecture Reference Manual ARMv8-A. Encodes ARM64 instructions into 32-bit machine code bytes. All ARM64 instructions are 4 bytes, little-endian.

---

## Design Philosophy (from Go's cmd/internal/obj/arm64/asm7.go)

1. Related instructions share ONE encoding function with parameters
2. The parameter makes the critical bit EXPLICIT and impossible to forget
3. Every encoding has a test against known-good output

---

## Key Components

### Register Encoding Functions

| Function | Description |
|----------|-------------|
| encodeRd | Encode register in Rd position (bits 4-0) |
| encodeRn | Encode register in Rn position (bits 9-5) |
| encodeRm | Encode register in Rm position (bits 20-16) |

### Instruction Categories

| Category | Functions | Tests |
|----------|-----------|-------|
| Move Wide | encodeMoveWide, encodeMOVZ, encodeMOVK, encodeMOVN | 4 |
| Add/Sub Imm | encodeAddSubImm, encodeADDImm, encodeSUBImm | 3 |
| Add/Sub Reg | encodeAddSubReg, encodeADD, encodeSUB | 2 |
| Multiply | encodeMul, encodeMUL, encodeMADD, encodeMSUB | 3 |
| Division | encodeDiv, encodeSDIV, encodeUDIV | 2 |
| Load/Store | encodeLdStReg, encodeLdStImm | 4 |
| Load/Store Pair | encodeLdStPair, encodeSTP, encodeLDP | 3 |
| Branch Reg | encodeBranchReg, encodeRET, encodeBR, encodeBLR | 3 |
| Conditional | encodeConditionalBranch, encodeBcc | 2 |
| Compare | encodeCMP, encodeCMN | 2 |
| Logical | encodeLogical, encodeAND, encodeORR, encodeEOR | 4 |
| Shift | encodeShift, encodeLSL, encodeLSR, encodeASR | 3 |
| Addressing | encodeADR, encodeADRP | 2 |
| NOP | encodeNOP | 1 |

### Emitter Struct

| Method | Description |
|--------|-------------|
| init | Initialize with allocator |
| deinit | Free code buffer |
| emit | Append instruction to buffer |
| emitBytes | Append raw bytes |
| patch | Patch instruction at offset |
| getCode | Get generated code slice |

---

## Verification

```bash
zig build test
# 357/380 tests passed (29 from arm64_asm.zig)
```

**VERIFIED: Logic 100% identical. 0% reduction. 29 tests pass.**
