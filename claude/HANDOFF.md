# Handoff — COT Compiler Toolkit

**Date:** 2026-04-04

---

## What COT Is

A compiler toolkit built on MLIR/LLVM. CIR (Cot Intermediate Representation) is a universal IR that any language frontend can target. Passes transform CIR. LLVM produces native/wasm. Think: the layer above MLIR that Lattner designed MLIR to enable.

**ac (agentic cot)** is our dogfood language — syntax designed by AI agents. **libzc** is a Zig frontend proving CIR is language-agnostic.

---

## What Works Right Now

```bash
# Build everything
cd libcir/build && cmake --build .                          # CIR dialect
cd libcot/build && cmake --build .                          # Compiler passes
cd libzc && ~/bin/zig-nightly build -Doptimize=ReleaseSafe  # Zig frontend
cd cot/build && cmake --build .                             # Driver + ac frontend

# Test everything (run all three before committing)
cd cot/build && ./cot test                                  # Gate test: 42 ✓
cd test && bash run.sh ../cot/build/cot                     # 4 build tests pass
cd cot/build && ./cot test ../../test/inline/005_inline_test.ac  # 3 inline tests pass
bin/lit test/lit/ -v                                        # 11 lit+FileCheck tests pass
```

**Total: 16 tests, all passing.**

**Two frontends produce identical CIR:**
```
ac:   fn add(a: i32, b: i32) -> i32 { return a + b }    → cir.add → 42
zig:  pub fn add(a: i32, b: i32) i32 { return a + b; }  → cir.add → 42
```

**Pipeline stages you can inspect:**
```bash
./cot emit-cir file.ac     # Print CIR MLIR text
./cot emit-cir file.zig    # Same for Zig
./cot emit-llvm file.ac    # Print LLVM dialect (after lowering)
./cot build file.ac -o out # Full compile to native
./cot build file.zig -o out # Same for Zig
./cot test file.ac          # Run inline test blocks
```

---

## CIR Ops Implemented

| Op | TableGen | LLVM Lowering |
|----|----------|---------------|
| `cir.constant` | CIR_ConstantOp | `llvm.mlir.constant` |
| `cir.add` | CIR_AddOp (SameOperandsAndResultType) | `llvm.add` |
| `cir.sub` | CIR_SubOp | `llvm.sub` |
| `cir.mul` | CIR_MulOp | `llvm.mul` |
| `cir.div` | CIR_DivOp | `llvm.sdiv` |
| `cir.rem` | CIR_RemOp | `llvm.srem` |
| `cir.cmp` | CIR_CmpOp (predicate attr, returns i1) | `llvm.icmp` |
| `cir.neg` | CIR_NegOp | `llvm.sub(0, x)` |
| `cir.bit_and` | CIR_BitAndOp | `llvm.and` |
| `cir.bit_or` | CIR_BitOrOp | `llvm.or` |
| `cir.xor` | CIR_XorOp | `llvm.xor` |
| `cir.bit_not` | CIR_BitNotOp | `llvm.xor(x, -1)` |
| `cir.shl` | CIR_ShlOp | `llvm.shl` |
| `cir.shr` | CIR_ShrOp | `llvm.lshr` |
| `cir.trap` | CIR_TrapOp (Terminator) | `llvm.trap` + `llvm.unreachable` |

Functions use MLIR's built-in `func.func` / `func.return` / `func.call`. CIR-specific `cir.func` will be added when we need CIR function semantics (comptime params, error returns, etc.).

---

## Project Structure

```
libcir/          CIR MLIR dialect (C++/TableGen) — 15 ops
  include/CIR/   CIRDialect.td, CIROps.td, CIROps.h
  lib/           CIRDialect.cpp
  c-api/         CIRCApi.h/cpp — C API for dialect registration
  build/         CMake build dir (cmake --build .)

libcot/          Compiler passes (C++ MLIR passes)
  include/COT/   Passes.h — public API (createCIRToLLVMPass, future passes)
  lib/           CIRToLLVM.cpp — CIR → LLVM lowering (15 ConversionPatterns)
  build/         CMake build dir (cmake --build .)

libac/           ac frontend (C++) — scanner, parser, codegen → CIR
  scanner.h/cpp  Zig tokenizer state machine + Go insertSemi pattern
  parser.h/cpp   Go recursive descent + Zig precedence table
  codegen.h/cpp  Zig AstGen dispatch → CIR ops via MLIR C++ API

libzc/           Zig frontend (Zig) — uses std.zig.Ast parser → CIR
  mlir.zig       MLIR C API bindings (ported from cot-failed, proven code)
  astgen.zig     AST → CIR ops via MLIR C API
  lib.zig        C ABI entry: zc_parse()
  build.zig      Zig build (~/bin/zig-nightly build -Doptimize=ReleaseSafe)

cot/             CLI driver (C++)
  main.cpp       Commands: build, test, emit-cir, emit-llvm, version
                 CIR→LLVM lowering patterns (ConversionPattern per op)
  CMakeLists.txt Links libcir + libzc + MLIR + LLVM

test/            Test suite
  *.ac           Build tests (exit code 42 = pass)
  inline/        Inline test files (cot test file.ac)
  lit/           lit+FileCheck tests
    lit.cfg.py   Configuration
    ac/          ac frontend CIR verification
    zig/         Zig frontend CIR verification
    lowering/    CIR → LLVM lowering verification
  run.sh         Build test runner

bin/
  lit            Symlink to ~/Library/Python/3.9/bin/lit

claude/          Internal docs
  ARCHITECTURE.md    Full design, multi-frontend plan, CIR op inventory
  REFERENCES.md      Component-to-reference mapping (CRITICAL — read before coding)
  FEATURES.md        80 features across 11 phases, implementation order
  AUDIT.md           MLIR/LLVM standards compliance — open issues, reference patterns
  AC_SYNTAX.md       ac language syntax reference
  LLVM_MLIR_CODING_STANDARDS.md  C++ style guide (LLVM conventions)
  HANDOFF.md         THIS FILE
```

---

## Key Documents — Read Order

1. **CLAUDE.md** — Project rules. THE TWO LAWS: study references for compiler logic, invent for ac syntax.
2. **claude/REFERENCES.md** — Which reference to port from for each component. CRITICAL.
3. **claude/FEATURES.md** — What to implement next, in order.
4. **claude/ARCHITECTURE.md** — Design, CIR op inventory, multi-frontend plan.
5. **claude/LLVM_MLIR_CODING_STANDARDS.md** — C++ style (camelBack, LLVM headers, no RTTI).

---

## What To Do Next

### Immediate: Continue Phase 1-2 features (FEATURES.md)

Each feature adds:
1. CIR op(s) in `libcir/include/CIR/CIROps.td`
2. Lowering pattern in `cot/main.cpp` (CIRToLLVMPass)
3. ac syntax in `libac/` (scanner token + parser rule + codegen emission)
4. Zig handling in `libzc/astgen.zig` (AST node → CIR op)
5. Tests: lit test for both frontends + inline test if applicable
6. Update `claude/AC_SYNTAX.md` with new syntax
7. Update `claude/FEATURES.md` status to ✓

**Next features in order:**
- #011 Let bindings (cir.alloc, cir.store, cir.load) — THIS IS THE BIG ONE
- #012 Var bindings (mutable locals)
- #013 Assignment (cir.store)
- #014 Compound assignment (load+op+store)
- #015 If/else as statement (already partially works in ac codegen)

### libcot: compiler passes library (DONE)

CIR→LLVM lowering extracted into `libcot/`. Future passes (TypeResolution, ARCInsertion, etc.) go here. The driver links `libcot/build/libCOT.a`.

---

## How The Lowering Works

CIR ops are lowered to LLVM dialect in a single pass (`CIRToLLVMPass` in main.cpp):

```cpp
struct CIRToLLVMPass : public PassWrapper<CIRToLLVMPass, OperationPass<ModuleOp>> {
  void runOnOperation() override {
    LLVMConversionTarget target(getContext());
    LLVMTypeConverter tc(&getContext());
    RewritePatternSet patterns(&getContext());
    patterns.add<AddOpLowering, SubOpLowering, ...>(tc, &getContext());
    applyPartialConversion(getOperation(), target, std::move(patterns));
  }
};
```

Each op has a `ConversionPattern` that replaces it with LLVM ops. After CIR→LLVM, `func-to-llvm` converts `func.func/call/return` to `llvm.func/call/return`. Then `translateModuleToLLVMIR` → `TargetMachine` → `.o` → `cc` link.

---

## How libzc Works

1. `zc_parse()` C ABI entry receives Zig source bytes
2. `std.zig.Ast.parse()` produces AST (Zig's standard library parser)
3. `astgen.generate()` walks AST nodes, emits CIR ops via MLIR C API
4. `serializeToBytecode()` produces MLIR bytecode
5. Driver loads bytecode with `parseSourceString<ModuleOp>(bytes, config)`
6. Same lowering pipeline as ac

Key Zig AST API patterns (used in astgen.zig):
- `tree.fullFnProto(&buf, node)` — get function prototype
- `proto.iterate(tree)` — iterate parameters
- `tree.fullCall(&buf, node)` — get call args
- `tree.nodeData(node).opt_node` — return value (optional)
- `tree.nodeData(node).node_and_node` — binary op children

---

## Rules

1. **Study reference before writing.** See REFERENCES.md. Every component traces to Zig/Swift/Rust/Go/MLIR source.
2. **ac syntax = LLM bias.** Whatever Claude would naturally predict.
3. **LLVM coding standards.** camelBack variables, UpperCamelCase types, LLVM headers, no RTTI.
4. **Test every change.** Run all three test layers before committing: `bin/lit test/lit/ -v`, build tests, inline tests.
5. **Never simplify to work around a bug.** Fix the root cause.
6. **NEVER** git checkout/restore/reset/clean. Edit manually.
7. **NEVER** git add . — stage by name.
