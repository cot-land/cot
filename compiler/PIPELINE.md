# Cot Compiler Pipeline

## IMPORTANT: Read This First

This document explains the compiler architecture. **There are TWO backends:**

1. **Wasm Backend** (default) - Cot source → `.wasm`
2. **Native Backend** (`--target=native`) - Cot source → Wasm → Native binary

**Key Rule:** The Wasm backend does NOT use register allocation. Wasm is a stack machine.

---

## Directory Structure

```
compiler/
├── core/                   # Shared utilities
│   ├── target.zig          # Target detection (wasm32, arm64, amd64)
│   ├── types.zig           # Core type definitions
│   └── errors.zig          # Error types
│
├── frontend/               # Cot source → IR (used by both backends)
│   ├── scanner.zig         # Tokenizer
│   ├── parser.zig          # AST construction
│   ├── ast.zig             # AST types
│   ├── checker.zig         # Type checking
│   ├── types.zig           # Type registry
│   ├── lower.zig           # AST → IR
│   ├── ir.zig              # IR types
│   └── ssa_builder.zig     # IR → SSA
│
├── ssa/                    # SSA infrastructure (SHARED - minimal)
│   ├── op.zig              # SSA operations (generic + wasm + native)
│   ├── value.zig           # SSA values
│   ├── block.zig           # SSA blocks
│   ├── func.zig            # SSA functions
│   ├── dom.zig             # Dominator tree (shared)
│   ├── debug.zig           # Debug output (shared)
│   ├── test_helpers.zig    # Test utilities (shared)
│   └── passes/
│       ├── schedule.zig    # Value ordering (SHARED)
│       ├── layout.zig      # Block ordering (WASM BACKEND)
│       └── lower_wasm.zig  # Generic→Wasm ops (WASM BACKEND)
│
├── codegen/
│   ├── wasm/               # WASM BACKEND: SSA → Wasm bytecode
│   │   ├── wasm.zig        # Package index
│   │   ├── constants.zig   # Opcodes, registers
│   │   ├── prog.zig        # Instruction chain
│   │   ├── preprocess.zig  # High→low transform
│   │   ├── assemble.zig    # Prog→bytes
│   │   ├── link.zig        # Module assembly
│   │   └── gen.zig         # SSA codegen
│   │
│   ├── wasm.zig            # Old module builder (CodeBuilder)
│   ├── wasm_gen.zig        # SSA → Wasm (main entry point)
│   │
│   └── native/             # NATIVE BACKEND: Wasm → Native (AOT)
│       │                   # ⚠️ NOT YET IMPLEMENTED
│       │                   # Will contain:
│       ├── wasm_parser.zig     # (TODO) Parse .wasm binary
│       ├── wasm_to_ssa.zig     # (TODO) Stack → SSA
│       ├── liveness.zig        # (MOVED) Liveness analysis
│       ├── regalloc.zig        # (MOVED) Register allocation
│       ├── stackalloc.zig      # (MOVED) Stack slots
│       ├── abi.zig             # (MOVED) Calling conventions
│       ├── expand_calls.zig    # (MOVED) ABI call expansion
│       ├── decompose.zig       # (MOVED) Break large values
│       ├── arm64.zig           # (TODO) From bootstrap-0.2
│       ├── amd64.zig           # (TODO) From bootstrap-0.2
│       ├── elf.zig             # (MOVED) Linux executables
│       ├── macho.zig           # (MOVED) macOS executables
│       └── dwarf.zig           # (MOVED) Debug info
│
├── driver.zig              # Orchestrates compilation
├── main.zig                # CLI entry point
└── pipeline_debug.zig      # Debug logging
```

---

## Pipeline Flows

### Wasm Backend (default)

```
cot build app.cot -o app.wasm

┌─────────────────────────────────────────────────────────────────┐
│  frontend/                                                      │
│  Scanner → Parser → Checker → Lowerer → IR → SSA Builder        │
└─────────────────────────────────┬───────────────────────────────┘
                                  │ SSA (generic ops)
                                  ▼
┌─────────────────────────────────────────────────────────────────┐
│  ssa/passes/                                                    │
│  schedule → layout → lower_wasm                                 │
│                                                                 │
│  NO REGALLOC - Wasm is a stack machine!                        │
└─────────────────────────────────┬───────────────────────────────┘
                                  │ SSA (wasm ops)
                                  ▼
┌─────────────────────────────────────────────────────────────────┐
│  codegen/wasm/                                                  │
│  wasm_gen → preprocess → assemble → link                       │
└─────────────────────────────────┬───────────────────────────────┘
                                  │
                                  ▼
                            .wasm file
```

### Native Backend (--target=native)

```
cot build app.cot --target=native -o app

┌─────────────────────────────────────────────────────────────────┐
│  Wasm Backend (same as above)                                   │
│  Cot source → .wasm (in memory)                                │
└─────────────────────────────────┬───────────────────────────────┘
                                  │ .wasm bytes
                                  ▼
┌─────────────────────────────────────────────────────────────────┐
│  codegen/native/                        ⚠️ NOT YET IMPLEMENTED  │
│  wasm_parser → wasm_to_ssa → liveness → regalloc → codegen     │
│                                                                 │
│  USES REGALLOC - native has real registers!                    │
└─────────────────────────────────┬───────────────────────────────┘
                                  │
                                  ▼
                          Native binary (ELF/Mach-O)
```

---

## What Each Pass Does

### Wasm Backend Passes

| Pass | File | Purpose |
|------|------|---------|
| schedule | ssa/passes/schedule.zig | Order values within blocks for deterministic emission |
| layout | ssa/passes/layout.zig | Order blocks for Wasm structured control flow |
| lower_wasm | ssa/passes/lower_wasm.zig | Convert generic ops (add, mul) to wasm ops (wasm_i64_add) |
| wasm_gen | codegen/wasm_gen.zig | Emit Wasm bytecode for each SSA value |

### Native Backend Passes (TODO)

| Pass | File | Purpose |
|------|------|---------|
| wasm_parser | codegen/native/wasm_parser.zig | Parse .wasm binary format |
| wasm_to_ssa | codegen/native/wasm_to_ssa.zig | Convert Wasm stack ops to SSA |
| liveness | codegen/native/liveness.zig | Compute live ranges for regalloc |
| regalloc | codegen/native/regalloc.zig | Assign physical registers |
| stackalloc | codegen/native/stackalloc.zig | Assign stack slots for spills |
| arm64/amd64 | codegen/native/*.zig | Emit native instructions |

---

## Common Mistakes to Avoid

### ❌ DON'T run regalloc for Wasm targets

```zig
// WRONG - regalloc is for native only!
if (target.isWasm()) {
    var regalloc_state = try regalloc(allocator, ssa_func, target);  // NO!
}
```

### ✅ DO check target before using native passes

```zig
// CORRECT
if (target.isWasm()) {
    // Wasm path: no regalloc
    try schedule.schedule(ssa_func);
    try layout.layout(ssa_func);
    try lower_wasm.lower(ssa_func);
    return generateWasmCode(ssa_func);
} else {
    // Native path: use regalloc (via AOT)
    return generateNativeCode(ssa_func, target);
}
```

### ❌ DON'T import native-only modules in Wasm path

```zig
// These are for native backend ONLY:
const regalloc = @import("codegen/native/regalloc.zig");      // Native only
const liveness = @import("codegen/native/liveness.zig");      // Native only
const stackalloc = @import("codegen/native/stackalloc.zig");  // Native only
const abi = @import("codegen/native/abi.zig");                // Native only
```

---

## File Ownership

| File | Belongs To | Notes |
|------|-----------|-------|
| ssa/passes/schedule.zig | SHARED | Used by both backends |
| ssa/passes/layout.zig | WASM | Block ordering for structured control flow |
| ssa/passes/lower_wasm.zig | WASM | Generic → Wasm ops |
| codegen/wasm/* | WASM | Wasm bytecode emission |
| codegen/native/* | NATIVE | AOT compilation (TODO) |

---

## Testing

### Wasm Backend Tests
```bash
zig test compiler/codegen/wasm/wasm.zig     # Wasm package tests
zig test compiler/codegen/wasm_gen.zig      # Codegen tests
zig test compiler/ssa/passes/lower_wasm.zig # Lowering tests
```

### Native Backend Tests (when implemented)
```bash
zig test compiler/codegen/native/regalloc.zig
zig test compiler/codegen/native/liveness.zig
# etc.
```

### E2E Tests
```bash
# Wasm E2E (should pass)
COT_TARGET=wasm32 zig build test

# Native E2E (will fail until native backend is implemented)
COT_TARGET=native zig build test
```

---

## Adding New Features

### Adding a new Wasm feature
1. Add op to `ssa/op.zig` if needed
2. Add lowering in `ssa/passes/lower_wasm.zig`
3. Add codegen in `codegen/wasm_gen.zig`
4. Test with `zig test compiler/codegen/wasm_gen.zig`

### Adding native backend support
1. Implement `codegen/native/wasm_parser.zig`
2. Implement `codegen/native/wasm_to_ssa.zig`
3. Copy arm64.zig, amd64.zig from bootstrap-0.2
4. Wire up in driver.zig for `--target=native`
