# Cot Compiler

A Wasm-first language for full-stack web development.

**The pitch:** Write like TypeScript, run like Rust, deploy anywhere, never think about memory.

See **[VISION.md](VISION.md)** for the complete language vision and strategy.

## Project Status

**This is the Cot compiler, written in Zig.** Like Deno (Rust) compiling TypeScript, this compiler is a permanent tool, not a bootstrap.

| Phase | Status | Description |
|-------|--------|-------------|
| Frontend | ✅ Done | Scanner, parser, type checker, IR lowering |
| SSA Infrastructure | ✅ Done | Values, blocks, functions, liveness, regalloc, stackalloc |
| Object Files | ✅ Done | ELF, Mach-O, DWARF debug info |
| Pipeline | ✅ Done | Driver, main, debug infrastructure |
| **Wasm Backend** | 🔄 Next | Cot → Wasm emission |
| AOT Native | Planned | Wasm → SSA → Native (reuses existing SSA/codegen) |

**Progress: 37 files, 29,671 → 13,570 lines (54% reduction)**

## Architecture

```
Cot Source → Wasm → Native (via AOT)
     │         │         │
     │         │         └── Browser: runs Wasm directly
     │         │         └── Server:  AOT compiles to native binary
     │         │
     │         └── Wasm Codegen (NEXT PHASE)
     │             - Stack machine (no register allocation needed)
     │             - Single calling convention
     │             - Dramatically simpler than native codegen
     │
     └── Frontend (COMPLETE)
         Scanner → Parser → TypeChecker → Lowerer → IR
```

## Key Design Decisions

### Why Wasm as IR

1. **Simpler compiler**: Stack machine eliminates register allocation
2. **Universal target**: Same binary runs in browser, server, edge
3. **Self-hosting achievable**: Previous attempts at native codegen hit complexity wall
4. **AOT for performance**: Wasm → Native when needed (production servers)

### Why ARC Memory Management

- Predictable (no GC pauses)
- Simpler than borrow checking
- Same semantics for Wasm and native targets

### Target Niche

**Full-stack applications with shared code between server and client.**

Like Node.js unified JavaScript, but:
- Compiled to Wasm (not interpreted)
- Type-safe with ARC memory management
- Native performance via AOT

## Repository Structure

```
cot/
├── compiler/           # Zig compiler
│   ├── core/           # Types, errors, target config
│   ├── frontend/       # Scanner, parser, checker, IR, lowerer
│   ├── ssa/            # SSA infrastructure (for AOT)
│   ├── obj/            # ELF, Mach-O output (for AOT)
│   ├── codegen/        # [NEXT] Wasm codegen
│   ├── main.zig        # Entry point
│   └── driver.zig      # Compilation orchestration
│
├── stdlib/             # Cot standard library (written in Cot)
├── runtime/            # Wasm runtime support (builtins)
├── tools/              # CLI tools (fmt, lint, etc.)
│
├── www/                # Websites
│   ├── land/           # cot.land - package manager
│   └── dev/            # cot.dev - docs & playground
│
├── docs/               # Documentation source
└── audit/              # Compiler verification docs
```

## Reference Code

**bootstrap-0.2** (`../bootstrap-0.2/`) contains:
- Working native compiler (ARM64 + AMD64)
- Existing cot1 self-hosted compiler code
- Reference implementations when debugging

**Key files to reference:**
- `bootstrap-0.2/DESIGN.md` - Full Wasm architecture specification
- `bootstrap-0.2/src/codegen/` - Native codegen (will become AOT)
- `bootstrap-0.2/src/cot1/` - Self-hosted compiler in Cot

## Building & Testing

```bash
# Run all tests
zig build test

# Test specific module
zig test compiler/frontend/parser.zig

# Debug output
COT_DEBUG=parse,lower zig build test
```

## Next Steps

### Phase 2: Wasm Backend

1. Create `compiler/codegen/wasm.zig`
2. Implement Wasm binary format emitter
3. Implement IR → Wasm codegen (stack machine)
4. Basic runtime (print, memory allocation)

### Phase 3: AOT Native

1. Wasm parser
2. Wasm → SSA converter
3. Wire up existing regalloc/codegen
4. Output ELF/Mach-O

### Phase 4: Self-Hosting (Future Goal)

Self-hosting is deferred until the language is mature. See [VISION.md](VISION.md) for rationale.

1. Stabilize language and standard library
2. Build real applications to prove the language
3. Attempt self-hosting when ready
4. Zig dependency becomes optional (not eliminated)

## For Claude AI Sessions

See `CLAUDE.md` for detailed instructions. Key points:
- This is a Wasm-first compiler, not a native codegen refactor
- Reference `bootstrap-0.2/DESIGN.md` for architecture details
- Reference `bootstrap-0.2/src/` for working code when stuck
- The frontend/SSA work is complete; focus is now Wasm emission
