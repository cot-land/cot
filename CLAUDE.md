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

### 3. CIR supports alternative constructs. Frontends choose.

CIR is a universal IR — it must express what every language needs, even when languages solve the same problem differently. When multiple approaches exist for the same concept, CIR provides ops for **all of them**. A frontend decides which to use (or both).

**Example: Error handling**
- **Error unions** (`cir.wrap_result`, `cir.is_error`, etc.) — Zig `E!T`, Rust `Result<T,E>`. Errors as values, zero-cost, compile-time enforced.
- **Exceptions** (`cir.throw`, `cir.invoke`, `cir.landingpad`) — TypeScript, Java, C#, C++, Python. Stack unwinding, runtime cost, not in the type system.

Both coexist in CIR. A Zig frontend uses error unions. A TypeScript frontend uses exceptions. A language like Swift that has both (`throws` + `Result<T,E>`) can use both. CIR doesn't pick winners — it provides building blocks.

This applies broadly: multiple memory models (ARC, GC, manual), multiple dispatch styles (static, vtable, existential), multiple concurrency models (async/await, actors, goroutines). CIR ops exist for each.

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
9. **Audit regularly.** Read `claude/AUDIT.md` — it tracks compliance with MLIR/LLVM standards, open issues, and reference patterns. Audit CIR against Flang FIR (`~/claude/references/flang-ref/flang/`), MLIR Arith, and ArithToLLVM before each phase milestone. Update AUDIT.md with findings. When implementing a feature that naturally addresses an open audit issue, prompt the user to fix it at the same time.
10. **NEVER** `git checkout`, `git restore`, `git reset --hard`, `git clean`. Edit manually.
11. **NEVER** `git add .` — stage files by name.

---

## Feature Implementation Checklist

Every feature from `claude/FEATURES.md` follows this checklist. Do ALL steps — no exceptions.

1. **Study reference.** Read `claude/REFERENCES.md` for the relevant component. Read the reference source before writing.
2. **Check audit.** Read `claude/AUDIT.md` — fix related open issues NOW, not later.
3. **CIR ops.** Add any new ops to `libcir/include/CIR/CIROps.td`. Use base classes (`CIR_BinaryOp`, `CIR_IntBinaryOp`, `CIR_IntUnaryOp`, `CIR_CastOp`). Add types to `CIRTypes.td` if needed.
4. **Lowering.** Add ConversionPattern in `libcot/lib/CIRToLLVM/`. Register in `populateCIRToLLVMConversionPatterns()`.
5. **ac frontend.** Add syntax to `libac/` — scanner token (if new), parser rule, codegen emission. Update `claude/AC_SYNTAX.md`.
6. **Zig frontend.** Add handling in `libzc/astgen.zig` — map AST node to CIR ops.
7. **TypeScript frontend.** Add handling in `libtc/codegen.go` — map TS AST node to CIR ops.
8. **lit tests — ALL THREE frontends.** Add `test/lit/ac/<feature>.ac` AND `test/lit/zig/<feature>.zig` AND `test/lit/ts/<feature>.ts`. Use `%cot emit-cir` + FileCheck. All three must produce equivalent CIR.
9. **Lowering test.** If feature adds new CIR→LLVM patterns, add `test/lit/lowering/<feature>.ac` to verify LLVM output.
10. **Inline tests.** Add or extend `test/inline/<NNN>_<name>_test.ac` with `test "name" { assert(...) }` blocks to verify runtime correctness.
11. **Build + test ALL.** Run `make all && make test`. All tests must pass.
12. **Update docs.** Mark feature ✓ in `claude/FEATURES.md`. Update `claude/HANDOFF.md` (op count, test count, next features).

**Test-first rule:** Write correct tests FIRST. If a test fails, the test is correct — fix the implementation, not the test. Never modify, simplify, or remove a test to make it pass. The test defines the contract.

**Frontend fidelity rules (until cot 1.0):**
- **libzc must be 1:1 compatible with Zig.** Every Zig test must compile with `zig build`. No new features added to Zig syntax.
- **libtc must be 1:1 compatible with TypeScript.** Every TS test must compile with `tsc`. No new features added to TS syntax.
- **libac (ac) is the kitchen sink.** All CIR features are exercised via ac. New syntax, combined features, experimental constructs — all go in ac.
- **Validate against reference compilers.** Zig tests verified with zig. TS tests verified with tsc/typescript. This guarantees we stay true to the reference languages.
- If a CIR feature has no equivalent in Zig or TS, the Zig/TS test is omitted — only ac tests that feature.

Build order: `make all` (libcir → libcot → libzc → libtc → cot)

---

## Reference Compilers

| Component | Reference | Source |
|-----------|-----------|--------|
| Scanner | Zig Tokenizer + Go insertSemi | `~/claude/references/zig/lib/std/zig/Tokenizer.zig` + `~/claude/references/go/src/go/scanner/scanner.go` |
| Parser | Go parser + Zig precedence table | `~/claude/references/go/src/go/parser/parser.go` + `~/claude/references/zig/lib/std/zig/Parse.zig` |
| AST | Zig index-based arena | `~/claude/references/zig/lib/std/zig/Ast.zig` |
| AST→CIR (Zig) | Zig AstGen | `~/claude/references/zig/lib/std/zig/AstGen.zig` |
| AST→CIR (TS) | TypeScript-Go | `~/claude/references/typescript-go/internal/parser/` |
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
make              # Build everything (libcir → libcot → libzc → cot)
make test         # Run all test layers (lit, gate, inline, build)
```

Individual components (if needed):
```bash
cd libcir/build && cmake --build .                  # CIR dialect (C++)
cd libcot/build && cmake --build .                  # Compiler passes (C++)
cd libzc && ~/bin/zig-nightly build -Doptimize=ReleaseSafe  # Zig frontend
cd libtc && CGO_ENABLED=1 go build -buildmode=c-archive -o libtc.a .  # TypeScript frontend
cd cot/build && cmake --build .                     # Driver + ac frontend
```

## Inspect pipeline stages

```bash
./cot emit-cir file.ac     # Print CIR MLIR text (ac frontend)
./cot emit-cir file.zig    # Same for Zig input
./cot emit-cir file.ts     # Same for TypeScript input
./cot emit-llvm file.ac    # Print LLVM dialect text (after lowering)
```

---

## Project Structure

```
libcir/        CIR MLIR dialect (C++ / TableGen)
libcot/        Compiler passes (C++ MLIR passes) — CIRToLLVM lowering
libac/         ac frontend (C++) — Agentic-Cot, agent-designed syntax
libzc/         zc frontend (Zig) — Zig-Cot, uses std.zig.Ast parser
libtc/         tc frontend (Go) — TypeScript-Cot, uses TypeScript-Go parser
cot/           CLI driver (C++)
claude/
  ARCHITECTURE.md    THE DESIGN — read first
  REFERENCES.md      Component-to-reference mapping — read second
```
