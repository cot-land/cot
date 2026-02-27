# Cot Self-Hosting Trajectory

**Goal:** Cot compiles itself. The Zig dependency becomes bootstrap-only.

This document tracks Cot's path to self-hosting, benchmarked against Zig and other languages that achieved self-hosting. It exists to maintain focus and momentum.

---

## The Inspiration: Zig's Self-Hosting Journey

Zig is the closest parallel — a systems language that bootstrapped from C++ to self-hosted over 5 years:

| Date | Zig Version | Milestone | Time from 0.3 |
|------|-------------|-----------|---------------|
| Sep 2018 | 0.3.0 | comptime, @typeInfo, Wasm experimental | — |
| Apr 2019 | 0.4.0 | `zig cc`, SIMD, bundled libc | 7 months |
| Sep 2019 | 0.5.0 | Async redesign, WASI Tier 2 | 1 year |
| Apr 2020 | 0.6.0 | Tuples, `@as`, ZLS repo created | 1.5 years |
| Nov 2020 | 0.7.0 | ZLS 0.1.0, macOS cross-compilation | 2 years |
| Jun 2021 | 0.8.0 | **Self-hosted compiler major push begins** | 2.7 years |
| Dec 2021 | 0.9.0 | WASI Tier 1, continued self-hosting work | 3.2 years |
| **Oct 2022** | **0.10.0** | **Self-hosted compiler becomes DEFAULT** | **4 years** |
| Aug 2023 | 0.11.0 | Package manager, C++ compiler deleted | 5 years |

**Key insight:** Zig started serious self-hosting work at 0.8 and shipped it as default at 0.10. The actual compiler rewrite took **~16 months** (Jun 2021 → Oct 2022). Everything before 0.8 was building the language to the point where it *could* self-host.

### Other Languages' Self-Hosting Timelines

| Language | Bootstrap from | Time to self-host | Strategy |
|----------|---------------|-------------------|----------|
| **Go** | C | 1.5 years (Go 1.4→1.5) | Automated C→Go translator, then manual cleanup |
| **Rust** | OCaml (`rustboot`) | 11 months | Manual rewrite of core, not full compiler |
| **Inko** | Ruby | ~6 months (parser→bootstrap) | Iterative: parsed itself first, then compiled |
| **8cc** | C | 40 days | Tiny C subset, minimum viable |
| **Zig** | C++ | ~16 months (active rewrite) | Parallel development, switched default at 0.10 |

**Pattern:** Most languages self-host in **6-18 months** of focused work once the language is capable enough. The prerequisite is always the same: the language needs file I/O, collections, string handling, and enough type system maturity to express a compiler.

---

## Where Cot Is Now (0.3.2)

### Self-Hosting Infrastructure: Ready

Cot already has everything a compiler needs:

| Requirement | Status | Used by |
|-------------|--------|---------|
| File I/O | `std/fs` — readFile, writeFile, openFile | Reading source, writing output |
| String manipulation | `std/string` — 25+ functions, StringBuilder | Parsing, error messages |
| Hash maps | `Map(K,V)` with splitmix64 | Symbol tables, type registries |
| Dynamic arrays | `List(T)` with 35+ methods | AST nodes, IR instructions |
| Sets | `Set(T)` | Scope lookups, dedup |
| Binary output | `@intToPtr`, `@ptrCast`, raw memory | Wasm bytecode emission |
| Error handling | Error unions, try/catch, errdefer | Compiler diagnostics |
| Enums + tagged unions | Full support | AST node types, IR opcodes |
| Generics | Monomorphized `fn(T)(...)` | Generic data structures |
| Pattern matching | Switch on enums/unions | AST visitor, IR lowering |
| Comptime | `@typeInfo`, `inline for`, `comptime {}` | Compile-time tables |
| Closures | First-class with capture | Visitor callbacks |

### Self-Hosted Code: 81% Complete

The `self/` directory contains a nearly-complete compiler frontend in Cot:

```
self/
  cot.json              # Project config (safe: true)
  main.cot              # CLI entry point — parse/check/lex/help/version (318 lines)
  frontend/
    token.cot           # Token enum + keyword lookup (436 lines)
    scanner.cot         # Full lexer (736 lines)
    source.cot          # Source positions + spans (111 lines)
    errors.cot          # Error reporter (203 lines)
    ast.cot             # AST nodes + 54 builtins (1,259 lines)
    parser.cot          # Recursive descent parser (2,691 lines)
    types.cot           # TypeRegistry + type structs (1,287 lines)
    checker.cot         # Type checker + SharedCheckerState (4,112 lines)
  total: 11,153 lines
```

**What's done:** Scanner, token, AST, parser, type registry, checker, and multi-file import resolution — all complete. The checker alone is 4,112 lines, covering scope/symbol table, type inference, function/struct/enum/union checking, generics (monomorphization), traits, closures, .variant shorthand, exhaustiveness checking, binary operators, @safe coercion, struct field validation, ErrorSet variant storage, and per-builtin validation. The self-hosted native binary can parse all 9 of its own source files (414KB total). 142 self-hosted tests pass on native.

**What's next:** IR/SSA lowerer port. wasm32 target is broken (multi-file compilation `error.MissingValue`).

---

## The Path Forward

### Phase 1: Scanner + Token + AST + Source + Errors (DONE)

| Component | Lines | Status |
|-----------|-------|--------|
| Token enum + keyword lookup | 436 | Done |
| Full lexer | 736 | Done |
| Source positions + spans | 111 | Done |
| Error reporter | 203 | Done |
| AST nodes + 54 builtins | 1,259 | Done |

**Milestone achieved:** All source files lex correctly.

### Phase 2: Parser (DONE — 2,691 lines)

| Component | Status |
|-----------|--------|
| Expression parsing (precedence climbing) | Done |
| Statement parsing | Done |
| Type parsing | Done |
| Declaration parsing (fn, struct, enum, union, trait, impl) | Done |
| Pattern matching (switch) | Done |
| Error recovery | Done |

**Milestone achieved:** `cot build self/main.cot -o /tmp/selfcot` produces a native binary. Parser self-parses all 9 source files (414KB total).

### Phase 3: Type Registry + Type Checker (DONE — 5,399 lines)

| Component | Lines | Status |
|-----------|-------|--------|
| TypeRegistry + type structs | 1,287 | Done |
| Scope/symbol table | ~600 | Done |
| Type inference | ~800 | Done |
| Function/struct/enum/union checking | ~1,000 | Done |
| Generic instantiation (monomorphization) | ~500 | Done |
| Trait resolution | ~400 | Done |
| Closures, .variant shorthand, exhaustiveness | ~400 | Done |
| @safe coercion, struct field validation | ~300 | Done |

**Milestone achieved:** Full type checking with multi-file import resolution works. Next: IR/SSA lowerer.

### Phase 4: IR + SSA (est. 2,000-3,000 lines)

| Component | Est. Lines |
|-----------|------------|
| AST → IR lowering | ~800 |
| SSA construction | ~600 |
| SSA passes (decompose, schedule, layout) | ~800 |
| Tests | ~800 |

**Milestone:** Lowers checked AST to SSA IR.

### Phase 5: Wasm Codegen (est. 2,000-3,000 lines)

| Component | Est. Lines |
|-----------|------------|
| SSA → Wasm ops | ~600 |
| Wasm bytecode emission | ~800 |
| Linking (functions, memory, exports) | ~400 |
| Tests | ~400 |

**Milestone:** Produces valid `.wasm` from Cot source. **Self-hosting achieved** when this compiles `self/` itself.

### Total Estimate

| Phase | Lines | Cumulative | Status |
|-------|-------|------------|--------|
| Scanner + AST + Source + Errors | 2,745 | 2,745 | **Done** |
| Parser | 2,691 | 5,436 | **Done** |
| Type Registry + Checker | 5,399 | 10,835 | **Done** |
| CLI (main.cot) | 318 | 11,153 | **Done** |
| IR + SSA | ~2,500 | ~13,650 | Planned |
| Wasm Codegen | ~2,000 | ~15,650 | Planned |

**~15,650 lines total for MVP self-hosting.** 11,153 done (~71% by lines). ~4,500 to go.

---

## Timeline: Cot vs Zig

| Milestone | Zig (from 0.3) | Cot (from 0.3) | Cot Speedup |
|-----------|---------------|----------------|-------------|
| LSP | +19 months (ZLS, Apr 2020) | Already done | >19 months ahead |
| Formatter | Already had at 0.3 | Already done | — |
| Async/await | +12 months (0.5) | Already done | >12 months ahead |
| Package manager | +59 months (0.11) | 0.5 (planned) | — |
| Self-hosting start | +33 months (0.8) | Now (0.3.2) | 33 months ahead |
| Self-hosting default | +49 months (0.10) | 0.10 (target) | — |

**Cot is starting self-hosting work 33 months earlier in its lifecycle than Zig did.** This is possible because:
1. LLM-assisted development compresses implementation time
2. Cot's simpler type system (no full comptime) makes the compiler easier to write
3. The @safe mode (auto-ref, implicit self, colon init) makes Cot feel like TypeScript
4. All infrastructure (collections, I/O, error handling) is already in place

---

## The Self-Hosting Payoff

### Why it matters

1. **Proves the language.** A compiler is the ultimate stress test — complex data structures, error handling, file I/O, string processing, binary output. If Cot can compile itself, it can build anything.

2. **Removes the Zig dependency.** Currently, changing Cot's compiler requires knowing Zig. Self-hosting means contributors only need to know Cot.

3. **Accelerates development.** Every improvement to Cot (better error messages, faster compilation, new features) immediately benefits the compiler itself.

4. **Credibility.** Self-hosting is the universally recognized milestone that separates "toy language" from "real language." Every major language has done it: C, Go, Rust, Zig, OCaml, Haskell.

### The bootstrap chain

```
Stage 0: Zig compiler (current)
  ↓ compiles
Stage 1: Cot compiler written in Cot (compiled by Stage 0)
  ↓ compiles
Stage 2: Cot compiler written in Cot (compiled by Stage 1)
  ↓ verify: Stage 1 output == Stage 2 output
```

When Stage 1 and Stage 2 produce identical binaries, self-hosting is verified. The Zig compiler becomes bootstrap-only (frozen, rarely touched).

---

## Tracking Progress

| Version | Date | Self-Hosting Milestone | Status |
|---------|------|----------------------|--------|
| 0.3.2 | Feb 2026 | Full frontend in Cot (11,153 LOC) — scanner, parser, types, checker, multi-file imports | **Done** |
| 0.4 | TBD | IR lowerer begins | Planned |
| 0.5-0.6 | TBD | IR + SSA in Cot (~13,400 LOC) | Planned |
| 0.7-0.9 | TBD | Wasm codegen in Cot (~15,400 LOC) | Planned |
| 0.10 | TBD | **Self-hosted compiler becomes default** | Goal |

---

## Velocity: 8 Weeks to 0.3

For perspective, here's what Cot achieved in its first 8 weeks:

- Complete compiler pipeline (Cot → SSA → Wasm → native ARM64/x64)
- ARC memory management with automatic cleanup
- Generics, closures, traits, error unions, tagged unions, optionals
- 31 stdlib modules (list, map, set, string, json, fs, os, time, crypto, regex, http, ...)
- LSP server with 7 features
- VS Code/Cursor extension
- 67 test files, ~1,623 tests
- CLI with 11 subcommands
- @safe mode for TypeScript-style DX
- Comptime infrastructure (@typeInfo, inline for, dead branch elimination)
- MCP server written in Cot
- Self-hosted frontend (scanner, parser, types, checker, multi-file imports — 11,153 lines)

Zig took 3 years and 36 contributors to reach a comparable 0.3. The LLM-assisted development model compresses implementation dramatically. The same velocity advantage applies to the self-hosting work ahead — the full frontend was ported in under 2 weeks.

**The only question is focus. This document exists to maintain it.**
