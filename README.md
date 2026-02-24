# Cot Compiler

[![CI](https://github.com/cotlang/cot/actions/workflows/test.yml/badge.svg)](https://github.com/cotlang/cot/actions/workflows/test.yml)
[![Release](https://github.com/cotlang/cot/actions/workflows/release.yml/badge.svg)](https://github.com/cotlang/cot/actions/workflows/release.yml)

A Wasm-first language for full-stack web development.

**The pitch:** Write like TypeScript, run like Rust, deploy anywhere, never think about memory.

See **[VISION.md](VISION.md)** for the complete language vision and strategy.

## Installation

### Quick Install (macOS / Linux)

```sh
curl -fsSL https://raw.githubusercontent.com/cotlang/cot/main/install.sh | sh
```

### From GitHub Releases

Download the latest binary from [GitHub Releases](https://github.com/cotlang/cot/releases).

### Build from Source

Requires [Zig 0.15+](https://ziglang.org/download/).

```sh
git clone https://github.com/cotlang/cot.git
cd cot
git submodule update --init stdlib
zig build
./zig-out/bin/cot version
```

## Quick Start

```bash
# Compile and run
cot run hello.cot

# Build to native executable
cot build hello.cot              # → hello
cot build hello.cot -o myapp     # → myapp

# Build to WebAssembly
cot build --target=wasm32 hello.cot   # → hello.wasm

# Version
cot version                      # → cot 0.3.2 (arm64-macos)

# Run tests
cot test myfile.cot
```

## Example

```cot
import "std/list"

struct Point { x: i64, y: i64 }

fn distance_sq(a: *Point, b: *Point) i64 {
    var dx = b.x - a.x
    var dy = b.y - a.y
    return dx * dx + dy * dy
}

fn main() i64 {
    var a = Point { .x = 0, .y = 0 }
    var b = Point { .x = 3, .y = 4 }
    println(distance_sq(&a, &b))  // Prints 25

    var scores: List(i64) = .{}
    scores.append(100)
    scores.append(200)
    return scores.get(0) + scores.get(1)  // Returns 300
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
- Error handling: error unions (`E!T`), `try`, `catch`, `errdefer`
- Memory: ARC (automatic reference counting), `defer`, `new`/`@alloc`/`@dealloc`
- Async: `async fn` / `await` / `try await` with dual backend (Wasm state machine + native eager eval)
- Traits: `trait`/`impl Trait for Type` (monomorphized, no vtables)
- I/O: `print`, `println`, `eprint`, `eprintln` (native syscalls)
- Imports: `import "std/list"` with cross-file generic instantiation
- Stdlib: `List(T)`, `Map(K,V)`, `Set(T)`, `std/string` (~25 functions + StringBuilder), `std/math`, `std/json` (parser + encoder), `std/sort`, `std/fs`, `std/os`, `std/time`, `std/random`, `std/io` (buffered I/O), `std/encoding` (base64 + hex), `std/url` (URL parser), `std/http` (TCP sockets + HTTP), `std/async` (event loop + async I/O)
- Comptime: `comptime {}` blocks, `@compileError`, const-fold if-expressions, dead branch elimination
- CLI: `cot build`, `cot run`, `cot test`, `cot init`, `cot lsp`, `cot version`
- Targets: Wasm32, WASI (`--target=wasm32-wasi`), ARM64 (macOS), x64 (Linux)

## Project Status

**Compiler written in Zig. Both Wasm and native AOT targets working.**

~1,620 tests passing across 66 files (Wasm E2E, native E2E, and unit tests).

| Component | Status |
|-----------|--------|
| Frontend (scanner, parser, checker, lowerer) | Complete |
| SSA infrastructure + passes | Complete |
| Wasm backend (bytecode gen + linking) | Complete |
| Native AOT (Cranelift-port: CLIF IR → regalloc2 → ARM64/x64) | Complete |
| ARC runtime (retain/release, heap, destructors) | Complete |
| Self-hosted compiler (`self/`) | 81% — 10,896 lines (scanner, parser, types, checker done) |

**Self-hosting:** The `self/` directory contains a Cot compiler written in Cot (10,896 lines across 9 files). The scanner, parser, type registry, and checker are complete. The self-hosted binary can parse all its own source files. Next: multi-file import resolution, then IR/SSA lowerer port. See [claude/VERSION_TRAJECTORY.md](claude/VERSION_TRAJECTORY.md).

**Next:** Distribution polish (Homebrew, VS Code marketplace), package manager. See [claude/ROADMAP.md](claude/ROADMAP.md).

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
| [docs/syntax.md](docs/syntax.md) | Complete language syntax reference |
| [claude/ROADMAP.md](claude/ROADMAP.md) | Roadmap: 0.4→1.0, competitive positioning |
| [claude/VERSION_TRAJECTORY.md](claude/VERSION_TRAJECTORY.md) | Self-hosting trajectory, benchmarked against Zig |
| [claude/PIPELINE_ARCHITECTURE.md](claude/PIPELINE_ARCHITECTURE.md) | Full pipeline reference map |
| [claude/BR_TABLE_ARCHITECTURE.md](claude/BR_TABLE_ARCHITECTURE.md) | br_table dispatch pattern |
| [claude/specs/WASM_3_0_REFERENCE.md](claude/specs/WASM_3_0_REFERENCE.md) | Wasm 3.0 features |
| [claude/archive/](claude/archive/) | Historical milestones and postmortems |

## Repository Structure

```
cot/
├── compiler/
│   ├── cli.zig            # CLI subcommands (build, run, test, version)
│   ├── main.zig           # Entry point, compile+link core
│   ├── driver.zig         # Pipeline orchestrator
│   ├── core/              # Types, errors, target config
│   ├── frontend/          # Scanner, parser, checker, IR, lowerer
│   ├── ssa/               # SSA infrastructure + passes
│   ├── lsp/               # Language server (LSP over stdio)
│   └── codegen/
│       ├── wasm/          # Wasm backend (gen, link, preprocess)
│       ├── print_runtime.zig  # Print/println runtime functions
│       └── native/        # AOT backend (Cranelift-style)
│           ├── wasm_to_clif/  # Wasm → CLIF translation
│           ├── machinst/      # CLIF → MachInst lowering
│           ├── isa/aarch64/   # ARM64 backend
│           ├── isa/x64/       # x64 backend
│           └── regalloc/      # Register allocator (regalloc2 port)
├── self/                  # Self-hosted compiler in Cot (10,896 lines)
│   ├── main.cot           # CLI entry point (parse, check, lex commands)
│   └── frontend/
│       ├── token.cot      # Token enum + keyword lookup
│       ├── scanner.cot    # Full lexer
│       ├── source.cot     # Source positions + spans
│       ├── errors.cot     # Error reporter
│       ├── ast.cot        # AST nodes + 54 builtins
│       ├── parser.cot     # Recursive descent parser (2,769 lines)
│       ├── types.cot      # TypeRegistry + type structs
│       └── checker.cot    # Type checker (3,966 lines)
├── stdlib/                # Standard library (31 modules, git submodule → cotlang/std)
│   ├── list.cot           # List(T) — dynamic array
│   ├── map.cot            # Map(K,V) — hash map with splitmix64
│   ├── set.cot            # Set(T) — thin wrapper over Map
│   ├── string.cot         # ~25 string functions + StringBuilder
│   ├── string_map.cot     # String-keyed hash map
│   ├── math.cot           # Integer/float math utilities
│   ├── json.cot           # JSON parser + encoder
│   ├── sort.cot           # Insertion sort for List(T)
│   ├── fs.cot             # File I/O (File struct, openFile, readFile, etc.)
│   ├── os.cot             # Process args, env, exit
│   ├── process.cot        # Process spawning, pipes
│   ├── time.cot           # Timestamps, Timer struct
│   ├── random.cot         # Random bytes, ints, ranges
│   ├── io.cot             # Buffered reader/writer
│   ├── encoding.cot       # Base64 + hex encode/decode
│   ├── url.cot            # URL parsing
│   ├── http.cot           # TCP sockets + HTTP response builder
│   ├── async.cot          # Event loop (kqueue/epoll) + async I/O wrappers
│   ├── crypto.cot         # SHA-256, HMAC
│   ├── regex.cot          # Regular expressions
│   ├── path.cot           # Path manipulation
│   ├── fmt.cot            # Number formatting (hex, binary, octal, pad)
│   ├── cli.cot            # CLI argument parser
│   ├── log.cot            # Structured logging
│   ├── semver.cot         # Semantic versioning
│   ├── uuid.cot           # UUID generation
│   ├── dotenv.cot         # .env file loading
│   ├── mem.cot            # Memory utilities
│   ├── debug.cot          # Debug assertions
│   ├── testing.cot        # Test utilities
│   └── sys.cot            # Runtime extern fn declarations
├── editors/vscode/        # VS Code/Cursor extension (syntax + LSP client)
├── runtime/               # Native runtime (.o files)
├── test/
│   ├── e2e/               # End-to-end tests (46 files, ~1500 tests)
│   ├── cases/             # Category unit tests (21 files, ~120 tests)
│   └── run_all.sh         # Run all Cot tests (glob discovery)
├── VERSION                # Semantic version (single source of truth)
├── docs/                  # Developer documentation (→ cot.dev)
│   └── syntax.md          # Language syntax reference
├── claude/                # Internal: AI session docs, architecture, specs
└── ...
```

## For AI Sessions

See [CLAUDE.md](CLAUDE.md) for compiler instructions and reference implementation locations.
