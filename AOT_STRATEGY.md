# AOT Compiler Strategy

## Overview

The `cot` CLI has **two compilation backends**:

1. **Wasm backend** (default): Cot source → Wasm bytecode
2. **Native backend** (via `--target=native`): Cot source → Wasm → Native binary

Both backends live in the same `cot` binary. The native backend internally runs AOT compilation on the Wasm output.

---

## Architecture

```
                         ┌──────────────────┐
                         │   Cot Source     │
                         │   or .wasm       │
                         └────────┬─────────┘
                                  │
                                  ▼
┌───────────────────────────────────────────────────────────────────────────┐
│                            cot CLI                                        │
│                                                                           │
│  ┌─────────────────────────────────────────────────────────────────────┐  │
│  │                    FRONTEND (Cot source only)                       │  │
│  │        Scanner → Parser → Checker → Lowerer → IR → SSA              │  │
│  └─────────────────────────────────┬───────────────────────────────────┘  │
│                                    │                                      │
│            ┌───────────────────────┴───────────────────────┐              │
│            │                                               │              │
│            ▼                                               ▼              │
│  ┌─────────────────────────┐                 ┌─────────────────────────┐  │
│  │    WASM BACKEND         │                 │    NATIVE BACKEND       │  │
│  │    (default)            │                 │    (--target=native)    │  │
│  │                         │                 │                         │  │
│  │  lower_wasm → wasm_gen  │ ──────────────▶ │  wasm_parser → wasm_ssa │  │
│  │                         │   (internal)    │  → regalloc → codegen   │  │
│  │  NO REGALLOC            │                 │                         │  │
│  │  (stack machine)        │                 │  USES REGALLOC          │  │
│  │                         │                 │  (real registers)       │  │
│  └───────────┬─────────────┘                 └───────────┬─────────────┘  │
│              │                                           │                │
└──────────────┼───────────────────────────────────────────┼────────────────┘
               │                                           │
               ▼                                           ▼
        ┌─────────────┐                            ┌──────────────┐
        │   .wasm     │                            │ Native Binary│
        └─────────────┘                            │ (ELF/Mach-O) │
               │                                   └──────────────┘
               │
    ┌──────────┴──────────┐
    ▼                     ▼
┌─────────┐        ┌─────────────┐
│ Browser │        │ Wasm Runtime│
│ (V8)    │        │ (wasmtime)  │
└─────────┘        └─────────────┘
```

---

## Directory Structure (Proposed)

```
cot/
├── compiler/
│   ├── core/               # Shared: types, errors, target
│   │
│   ├── frontend/           # Cot source → IR
│   │   ├── scanner.zig
│   │   ├── parser.zig
│   │   ├── checker.zig
│   │   ├── lower.zig
│   │   ├── ir.zig
│   │   └── ssa_builder.zig
│   │
│   ├── ssa/                # SSA infrastructure (shared by both backends)
│   │   ├── op.zig          # SSA operations
│   │   ├── value.zig       # SSA values
│   │   ├── block.zig       # SSA blocks
│   │   ├── func.zig        # SSA functions
│   │   └── passes/
│   │       ├── schedule.zig     # Used by both
│   │       ├── layout.zig       # Wasm backend
│   │       └── lower_wasm.zig   # Wasm backend
│   │
│   ├── codegen/
│   │   ├── wasm/           # WASM BACKEND: SSA → Wasm
│   │   │   ├── wasm.zig         # Package index
│   │   │   ├── constants.zig    # Opcodes, registers
│   │   │   ├── prog.zig         # Instruction chain
│   │   │   ├── preprocess.zig   # High→low transform
│   │   │   ├── assemble.zig     # Prog→bytes
│   │   │   ├── link.zig         # Module assembly
│   │   │   └── gen.zig          # SSA codegen
│   │   │
│   │   └── native/         # NATIVE BACKEND: Wasm → Native (AOT)
│   │       ├── wasm_parser.zig  # Parse .wasm binary (NEW)
│   │       ├── wasm_to_ssa.zig  # Stack → SSA (NEW)
│   │       ├── liveness.zig     # From bootstrap-0.2
│   │       ├── regalloc.zig     # From bootstrap-0.2
│   │       ├── stackalloc.zig   # From bootstrap-0.2
│   │       ├── abi.zig          # From bootstrap-0.2
│   │       ├── arm64.zig        # From bootstrap-0.2
│   │       ├── amd64.zig        # From bootstrap-0.2
│   │       ├── elf.zig          # From bootstrap-0.2
│   │       ├── macho.zig        # From bootstrap-0.2
│   │       └── dwarf.zig        # From bootstrap-0.2
│   │
│   ├── driver.zig          # Orchestrates both backends
│   └── main.zig            # CLI entry point
│
└── runtime/                # Cot runtime (ARC, allocator)
    ├── wasm/               # Runtime for Wasm target
    └── native/             # Runtime for native target
```

**Key insight:** Both backends live under `compiler/codegen/`. The native backend consumes Wasm (either from file or from the wasm backend's output).

---

## What Goes Where

### Shared Infrastructure

| Component | Purpose | Used By |
|-----------|---------|---------|
| core/* | Types, errors, target | Both backends |
| frontend/* | Cot source → IR | Frontend only |
| ssa/op.zig, value.zig, block.zig, func.zig | Core SSA | Both backends |
| ssa/passes/schedule.zig | Value ordering | Both backends |

### Wasm Backend (codegen/wasm/)

| Component | Purpose | Notes |
|-----------|---------|-------|
| ssa/passes/lower_wasm.zig | Generic → Wasm ops | |
| ssa/passes/layout.zig | Block ordering | Structured control flow |
| codegen/wasm/* | SSA → Wasm bytecode | Go-style package |

### Native Backend (codegen/native/)

| Component | Purpose | Source |
|-----------|---------|--------|
| wasm_parser.zig | Parse .wasm binary | NEW (~400 LOC) |
| wasm_to_ssa.zig | Wasm stack → SSA | NEW (~600 LOC) |
| liveness.zig | Liveness analysis | bootstrap-0.2 |
| regalloc.zig | Register allocation | bootstrap-0.2 |
| stackalloc.zig | Stack slot assignment | bootstrap-0.2 |
| abi.zig | Calling conventions | bootstrap-0.2 |
| arm64.zig | ARM64 code emission | bootstrap-0.2 |
| amd64.zig | AMD64 code emission | bootstrap-0.2 |
| elf.zig | Linux executables | bootstrap-0.2 |
| macho.zig | macOS executables | bootstrap-0.2 |
| dwarf.zig | Debug info | bootstrap-0.2 |

---

## Wasm → SSA Conversion

The key new component for AOT. Mechanical conversion from stack to SSA:

```
Wasm Stack              SSA Form
──────────              ────────
local.get 0      →      v1 = Arg(0)
local.get 1      →      v2 = Arg(1)
i64.add          →      v3 = Add(v1, v2)
i64.const 10     →      v4 = Const(10)
i64.mul          →      v5 = Mul(v3, v4)
return           →      Return(v5)
```

**Algorithm:**
1. Maintain a virtual stack during parsing
2. Each Wasm op pops inputs, creates SSA value, pushes result
3. Wasm locals map to SSA values
4. Wasm control flow (block/loop/if) maps to SSA blocks

This is ~600 LOC of new code. Everything else is reused.

---

## Current State

### What Exists in 0.3 (Current Location → Target Location)

| File | Current | Target | Action |
|------|---------|--------|--------|
| compiler/ssa/regalloc.zig | compiler/ssa/ | codegen/native/ | Move |
| compiler/ssa/liveness.zig | compiler/ssa/ | codegen/native/ | Move |
| compiler/ssa/stackalloc.zig | compiler/ssa/ | codegen/native/ | Move |
| compiler/ssa/abi.zig | compiler/ssa/ | codegen/native/ | Move |
| compiler/ssa/passes/expand_calls.zig | compiler/ssa/passes/ | codegen/native/ | Move |
| compiler/ssa/passes/decompose.zig | compiler/ssa/passes/ | codegen/native/ | Move |
| compiler/ssa/debug.zig | compiler/ssa/ | compiler/ssa/ | Keep |
| compiler/codegen/wasm/* | compiler/codegen/ | compiler/codegen/wasm/ | Keep |
| compiler/obj/elf.zig | compiler/obj/ | codegen/native/ | Move |
| compiler/obj/macho.zig | compiler/obj/ | codegen/native/ | Move |
| compiler/dwarf.zig | compiler/ | codegen/native/ | Move |

### What Exists in bootstrap-0.2 (To Copy)

| File | Lines | Notes |
|------|-------|-------|
| codegen/arm64.zig | 3,589 | Native ARM64 codegen |
| codegen/amd64.zig | 3,946 | Native AMD64 codegen |
| arm64/asm.zig | 989 | ARM64 instruction encoding |
| amd64/asm.zig | 1,628 | AMD64 instruction encoding |
| amd64/regs.zig | 218 | AMD64 register definitions |

### What Needs to Be Written

| File | Estimated LOC | Notes |
|------|---------------|-------|
| codegen/native/wasm_parser.zig | ~400 | Parse Wasm binary format |
| codegen/native/wasm_to_ssa.zig | ~600 | Stack machine → SSA |

---

## Migration Plan

### Phase 1: Current (Wasm Backend) ✅

Focus on Cot → Wasm pipeline. Don't touch native codegen.

**Status:** WORKING (M1-M9 complete)

### Phase 2: Reorganize

1. Create `compiler/codegen/native/` directory
2. Move native-only files there:
   - regalloc.zig, liveness.zig, stackalloc.zig, abi.zig
   - expand_calls.zig, decompose.zig
   - elf.zig, macho.zig, dwarf.zig
3. Remove these from the Wasm compilation path in driver.zig
4. Fix/disable tests that run regalloc (native backend tests)

### Phase 3: AOT Implementation

1. Create `codegen/native/wasm_parser.zig` - parse .wasm files
2. Create `codegen/native/wasm_to_ssa.zig` - convert to SSA
3. Copy arm64.zig, amd64.zig from bootstrap-0.2
4. Wire up in driver.zig: `--target=native` triggers AOT pipeline

### Phase 4: CLI Integration

```bash
# Default: Cot → Wasm
cot build app.cot                      # → app.wasm
cot build app.cot -o app.wasm          # explicit output

# Native target: Cot → Wasm → Native (AOT runs internally)
cot build app.cot --target=native      # → app (native for current platform)
cot build app.cot --target=amd64-linux # → app (cross-compile)
cot build app.cot --target=arm64-macos # → app (cross-compile)

# Direct AOT (user provides .wasm)
cot build app.wasm -o app              # Wasm → Native
```

---

## Key Insight

**Wasm as Universal IR:**

- Cot compiler targets Wasm (simpler than native)
- Browser runs Wasm directly
- Server runs Wasm via AOT to native
- Same semantics everywhere

**Why this architecture:**

1. **Simplifies the main compiler** - no register allocation, single calling convention
2. **Reuses existing work** - native codegen from bootstrap-0.2 isn't wasted
3. **Enables cross-compilation** - compile Wasm once, AOT to any native target
4. **Clean separation** - Wasm is the boundary between compilation phases

---

## Go Reference

Go's Wasm compiler has similar separation:

| Go Component | Purpose | Our Equivalent |
|--------------|---------|----------------|
| cmd/compile/internal/wasm/ssa.go | SSA → Wasm | compiler/codegen/wasm_gen.zig |
| cmd/internal/obj/wasm/wasmobj.go | Wasm assembly | compiler/codegen/wasm/assemble.zig |
| cmd/link/internal/wasm/asm.go | Wasm linking | compiler/codegen/wasm/link.zig |

Go doesn't have an AOT compiler (Go Wasm runs in browser or via wasmtime). We add AOT as a separate tool.

---

## Summary

1. **Single `cot` CLI** with two backends selected by `--target`
2. **Wasm backend** (default) = Cot source → Wasm (no regalloc, stack machine)
3. **Native backend** (`--target=native`) = Cot → Wasm → Native (uses regalloc)
4. **Shared** = Frontend, core SSA types, schedule pass
5. **Native backend reuses** = regalloc, codegen from bootstrap-0.2
6. **New code needed** = Wasm parser + Wasm→SSA converter (~1000 LOC)

```bash
# Usage
cot build app.cot                    # → app.wasm (default)
cot build app.cot --target=native    # → app (native binary via AOT)
cot build app.wasm -o app            # → app (direct AOT on .wasm)
```
