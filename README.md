# Cot Compiler

A Wasm-first language for full-stack web development.

**The pitch:** Write like TypeScript, run like Rust, deploy anywhere, never think about memory.

See **[VISION.md](VISION.md)** for the complete language vision and strategy.

## Quick Start

```bash
# Build the compiler
zig build

# Compile to native executable (default)
./zig-out/bin/cot hello.cot -o hello
./hello

# Compile to WebAssembly
./zig-out/bin/cot --target=wasm32 hello.cot -o hello.wasm

# Run tests
zig build test
```

## Example

```cot
struct Point { x: i64, y: i64 }

fn distance_sq(a: *Point, b: *Point) i64 {
    let dx = b.x - a.x;
    let dy = b.y - a.y;
    return dx * dx + dy * dy;
}

fn main() i64 {
    var a = Point { .x = 0, .y = 0 };
    var b = Point { .x = 3, .y = 4 };
    return distance_sq(&a, &b);  // Returns 25
}
```

## Architecture

All code goes through Wasm first. Native output is AOT-compiled from Wasm via a Cranelift-style backend.

```
Cot Source → Scanner → Parser → Checker → IR → SSA
  → lower_wasm (SSA → Wasm ops) → wasm/ (Wasm bytecode)
      ├── --target=wasm32 → .wasm file
      └── --target=native (default)
          → wasm_parser → wasm_to_clif/ → CLIF IR
          → machinst/lower → isa/{aarch64,x64}/ → emit → .o → linker → executable
```

## Language Features

- Types: `i8`–`u64`, `f32`, `f64`, `bool`, `[]u8` (strings)
- Control flow: `if`/`else`, `while`, `for`-range, `break`, `continue`
- Data: structs, arrays, slices, enums, unions (with payloads), tuples
- Functions: closures, function pointers, generics (monomorphized)
- Error handling: error unions (`E!T`), `try`, `catch`
- Memory: ARC (automatic reference counting), `defer`, `new`/`@alloc`/`@dealloc`
- Traits: `trait`/`impl Trait for Type` (monomorphized, no vtables)
- Stdlib: `List(T)` with generic impl blocks
- Targets: Wasm32, ARM64 (macOS), x64 (Linux)

## Project Status

**Compiler written in Zig. Both Wasm and native AOT targets working.**

All tests passing across Wasm E2E, native E2E, and unit tests.

| Component | Status |
|-----------|--------|
| Frontend (scanner, parser, checker, lowerer) | Complete |
| SSA infrastructure + passes | Complete |
| Wasm backend (bytecode gen + linking) | Complete |
| Native AOT (Cranelift-port: CLIF IR → regalloc2 → ARM64/x64) | Complete |
| ARC runtime (retain/release, heap, destructors) | Complete |

**Next:** Map(K,V), trait bounds, string interpolation, I/O, test parity. See [docs/ROADMAP_1_0.md](docs/ROADMAP_1_0.md).

## Design Decisions

### Why Wasm-First
1. Stack machine eliminates register allocation complexity in the primary path
2. Same binary runs in browser, server, and edge
3. AOT compilation from Wasm provides native performance when needed
4. Previous direct native codegen attempts failed 5 times — Wasm-first succeeded

### Why ARC
- Predictable performance (no GC pauses)
- Simpler than borrow checking
- Same semantics for Wasm and native targets

## Documents

| Document | Purpose |
|----------|---------|
| [VISION.md](VISION.md) | Language vision, design principles |
| [CLAUDE.md](CLAUDE.md) | AI session instructions |
| [TROUBLESHOOTING.md](TROUBLESHOOTING.md) | Debugging methodology |
| [docs/ROADMAP_1_0.md](docs/ROADMAP_1_0.md) | Road to 1.0 |
| [docs/PIPELINE_ARCHITECTURE.md](docs/PIPELINE_ARCHITECTURE.md) | Full pipeline reference map |
| [docs/BR_TABLE_ARCHITECTURE.md](docs/BR_TABLE_ARCHITECTURE.md) | br_table dispatch pattern |
| [docs/specs/WASM_3_0_REFERENCE.md](docs/specs/WASM_3_0_REFERENCE.md) | Wasm 3.0 features |
| [docs/archive/](docs/archive/) | Historical milestones and postmortems |

## Repository Structure

```
cot/
├── compiler/
│   ├── core/              # Types, errors, target config
│   ├── frontend/          # Scanner, parser, checker, IR, lowerer
│   ├── ssa/               # SSA infrastructure + passes
│   ├── codegen/
│   │   ├── wasm/          # Wasm backend (gen, link, preprocess)
│   │   └── native/        # AOT backend (Cranelift-style)
│   │       ├── wasm_to_clif/  # Wasm → CLIF translation
│   │       ├── machinst/      # CLIF → MachInst lowering
│   │       ├── isa/aarch64/   # ARM64 backend
│   │       ├── isa/x64/       # x64 backend
│   │       └── regalloc/      # Register allocator (regalloc2 port)
│   ├── driver.zig         # Pipeline orchestrator
│   └── main.zig           # CLI entry point
├── runtime/               # Native runtime (.o files)
├── test/cases/            # .cot test files
└── docs/                  # Architecture docs, specs, roadmap
```

## For AI Sessions

See [CLAUDE.md](CLAUDE.md) for compiler instructions and reference implementation locations.
