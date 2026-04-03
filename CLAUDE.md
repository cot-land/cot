# Claude AI Instructions — COT (Compiler Toolkit)

## What COT Is

A compiler platform. Frontends produce CIR (MLIR dialect). Passes transform CIR. LLVM produces native/wasm binaries.

```
Frontend → CIR → passes → LLVM → native/wasm
```

**Read `claude/ARCHITECTURE.md` first.** Full design, op inventory, pass pipeline, gate tests.
**Read `claude/REFERENCES.md` second.** Component-to-reference mapping with justifications.

---

## The Two Laws

### 1. COMPILER LOGIC: Study reference, then port. Never invent.

Before implementing any compiler feature — a scanner state, a parser rule, a codegen pattern, an optimization pass — you MUST:

1. **Find the reference** in `claude/REFERENCES.md` (it maps every component to a source file)
2. **Read the reference source code** at the listed location in `~/claude/references/`
3. **Port the proven pattern** — adapt the architecture to C++/our codebase, not reinvent it
4. **Cite the reference** in a comment at the top of the file

Claude-invented compiler logic creates tech debt. Every bug in the old project came from inventing instead of copying. The reference compilers (Zig, Swift, Rust, Go, MLIR) have millions of hours of testing behind them. Use that.

This project follows Chris Lattner's design principles from MLIR and LLVM:
- **Progressive lowering** — CIR → typed CIR → LLVM dialect → LLVM IR → machine code
- **Clean dialect abstractions** — each dialect has one job, ops are well-defined
- **Reusable infrastructure** — libcir is a library, not monolithic
- **Verify at every level** — MLIR verifier after each pass
- **ConversionPatterns for lowering** — not ad-hoc if/else chains

When in doubt about a design decision, ask: "What would Lattner do?" Then check how MLIR does it.

### 2. AC LANGUAGE SYNTAX: Invent freely. Let LLM bias guide you.

**ac = agentic cot** — syntax designed by AI agents.

The `ac` language syntax should be whatever feels most natural for an LLM to write without thinking. If Claude can guess the syntax, that IS the syntax. The goal is maximum familiarity across all C-style languages — the patterns with the strongest signal in training data.

ac exists to dogfood the compiler toolkit. It is not the product. CIR is the product. ac exercises CIR until real frontends (Zig, TypeScript) are added.

The LLM bias lands on: Rust syntax + Go cleanliness. `fn`, `let`/`var`, `-> type`, `name: type`, `{}` blocks, no semicolons, no parens on conditions.

---

## Rules

1. **CIR is MLIR.** CIR modules are MLIR modules. CIR bytecode is MLIR bytecode.
2. **Study before writing.** Read the reference source. Port the pattern. Cite it.
3. **One backend — LLVM.** All targets through MLIR LLVM dialect.
4. **No stubs, no TODOs.** Every function works or doesn't exist yet.
5. **Start minimal.** Gate test 1 before gate test 2.
6. **C++ for compiler infrastructure.** Frontends can be any language via C ABI or bytecode.
7. **LLVM/MLIR coding standards.** All C++ follows `claude/LLVM_MLIR_CODING_STANDARDS.md`. camelBack variables, UpperCamelCase types, 2-space indent, 80-col, no RTTI/exceptions, LLVM containers. CIR must be upstreamable.
8. **Test every change.** Three test layers: lit+FileCheck (IR verification), inline tests (runtime), build tests (e2e). Run `lit test/lit/` before committing.
9. **NEVER** `git checkout`, `git restore`, `git reset --hard`, `git clean`. Edit manually.
10. **NEVER** `git add .` — stage files by name.

---

## Reference Compilers

| Component | Reference | Source |
|-----------|-----------|--------|
| Scanner | Zig Tokenizer + Go insertSemi | `~/claude/references/zig/lib/std/zig/Tokenizer.zig` + `~/claude/references/go/src/go/scanner/scanner.go` |
| Parser | Go parser + Zig precedence table | `~/claude/references/go/src/go/parser/parser.go` + `~/claude/references/zig/lib/std/zig/Parse.zig` |
| AST | Zig index-based arena | `~/claude/references/zig/lib/std/zig/Ast.zig` |
| AST→CIR | Zig AstGen | `~/claude/references/zig/lib/std/zig/AstGen.zig` |
| CIR dialect | MLIR (Lattner) | `~/claude/references/llvm-project/mlir/` |
| Type resolution | Zig Sema | `~/claude/references/zig/src/Sema.zig` |
| Comptime | Zig Sema | `~/claude/references/zig/src/Sema.zig` |
| ARC | Swift SILOptimizer | `~/claude/references/swift/lib/SILOptimizer/ARC/` |
| Concurrency | Swift SILOptimizer | `~/claude/references/swift/lib/SILOptimizer/Mandatory/` |
| Traits | Rust monomorphization | `~/claude/references/rust/compiler/rustc_monomorphize/` |
| CIR→LLVM | MLIR ConversionPatterns | `~/claude/references/llvm-project/mlir/lib/Conversion/` |

Full justifications in `claude/REFERENCES.md`.

---

## Build

```bash
cd libcir/build && cmake --build .                  # CIR dialect (C++)
cd libzc && ~/bin/zig-nightly build -Doptimize=ReleaseSafe  # Zig frontend
cd cot/build && cmake --build .                     # Driver + ac frontend
```

## Test (run all three layers before committing)

```bash
cd cot/build && ./cot test                          # Gate test: add(19,23) = 42
cd test && bash run.sh ../cot/build/cot             # Build tests (exit code)
cd cot/build && ./cot test ../../test/inline/005_inline_test.ac  # Inline tests
bin/lit test/lit/ -v                                # lit + FileCheck (IR verification)
```

## Inspect pipeline stages

```bash
./cot emit-cir file.ac     # Print CIR MLIR text (what frontend produces)
./cot emit-cir file.zig    # Same for Zig input
./cot emit-llvm file.ac    # Print LLVM dialect text (after lowering)
```

---

## Project Structure

```
libcir/        CIR MLIR dialect (C++ / TableGen)
libcot/        Compiler passes (C++ MLIR passes) [not yet created]
libac/         ac (agentic cot) language frontend (C++) — agent-designed syntax, dogfoods CIR
cot/           CLI driver (C++)
claude/
  ARCHITECTURE.md    THE DESIGN — read first
  REFERENCES.md      Component-to-reference mapping — read second
```
