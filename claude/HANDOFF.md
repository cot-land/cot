# Handoff — COT Compiler Toolkit

**Date:** 2026-04-04

---

## What COT Is

A compiler toolkit built on MLIR/LLVM. Frontends produce CIR (universal IR). Passes transform CIR. LLVM produces native/wasm. Think: the layer above MLIR that Lattner designed MLIR to enable.

## What Works

```bash
cd cot/build && ./cot test                                    # Gate test: 42 ✓
cd cot/build && ./cot build ../../test/001_int_literal.ac -o /tmp/t && /tmp/t   # Build ac → native
cd cot/build && ./cot test ../../test/inline/005_inline_test.ac                  # Inline tests: 3 pass
```

**Pipeline proven:** ac source → scanner → parser → AST → CIR ops → LLVM dialect → LLVM IR → ARM64 .o → link → native binary.

**CIR ops working:** `cir.constant`, `cir.add`, `cir.sub`, `cir.mul`, `cir.div`, `cir.rem`, `cir.cmp`, `cir.trap`

**ac features working:** functions, arithmetic (`+` `-` `*` `/` `%`), comparisons (`==` `!=` `<` `<=` `>` `>=`), function calls, `if/else`, `assert()`, `test "name" { }` blocks

## Project Structure

```
libcir/        CIR MLIR dialect (C++/TableGen) — 8 ops, builds clean
libac/         ac frontend (C++) — scanner, parser, codegen
cot/           CLI driver + CIR→LLVM lowering
test/          4 build tests + 3 inline tests (all pass)
claude/        Docs
```

## Key Documents

| Doc | What |
|-----|------|
| `CLAUDE.md` | Project rules — TWO LAWS: study references for compiler logic, invent for ac syntax |
| `claude/ARCHITECTURE.md` | Full design, multi-frontend plan, CIR op inventory |
| `claude/REFERENCES.md` | Component-to-reference mapping with justifications |
| `claude/FEATURES.md` | 80 features across 11 phases, implementation order, test plan |
| `claude/AC_SYNTAX.md` | ac language syntax reference (updated per feature) |

## Next Steps

### Immediate: libzc (Zig frontend)

Write a Zig frontend that produces the same CIR as libac. Uses `std.zig.Ast` parser. Two modes: C ABI link or `.cir` bytecode file. Test with the same features ac already supports.

### Then: Continue Phase 1-2 features

Features #006, #008-#020 in FEATURES.md. Each adds CIR ops + ac syntax + lowering + tests in BOTH ac and Zig.

## Build Commands

```bash
cd libcir/build && cmake --build .     # CIR dialect
cd cot/build && cmake --build .        # Driver + ac frontend
cd test && bash run.sh ../cot/build/cot  # Build tests
cd cot/build && ./cot test ../../test/inline/005_inline_test.ac  # Inline tests
```

## Rules

1. **Study reference before writing.** See REFERENCES.md.
2. **ac syntax = LLM bias.** Whatever Claude would predict.
3. **NEVER** git checkout/restore/reset/clean. Edit manually.
4. **NEVER** git add . — stage by name.
