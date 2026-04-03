# COT Reference Model — Component-to-Source Mapping

**Date:** 2026-04-03
**Rule:** Every component is ported from a reference implementation. No invented logic.

---

## Reference Decision Table

| Component | Reference | Source Location | Lines | Justification |
|---|---|---|---|---|
| Scanner | Zig Tokenizer + Go semicolon insertion | `~/claude/references/zig/lib/std/zig/Tokenizer.zig` + `~/claude/references/go/src/go/scanner/scanner.go` | 1,778 + 1,000 | Zig's explicit state machine maps to C++ switch. Go's `insertSemi` is the only proven auto-semicolon pattern. Rust stateless cursor doesn't handle newline significance. Swift's 3,237-line two-phase lexer is overengineered. |
| Parser | Go Parser + Zig precedence table | `~/claude/references/go/src/go/parser/parser.go` + `~/claude/references/zig/lib/std/zig/Parse.zig` | 2,962 + 3,725 | Go's recursive descent + precedence climbing is the cleanest. Zig's `operTable` is more maintainable than Go's method-based precedence. Rust parser is 24K lines. Swift defers precedence to semantic phase. |
| AST | Zig index-based arena | `~/claude/references/zig/lib/std/zig/Ast.zig` | ~2,000 | u32 indices into MultiArrayList. No pointers, cache-friendly, serializable. Same philosophy as MLIR's indexed operations. Go/Rust/Swift all use pointer/heap-based AST. |
| AST→CIR codegen | Zig AstGen | `~/claude/references/zig/lib/std/zig/AstGen.zig` | 13,664 | Single-pass recursive dispatch. Emits unresolved IR (types as refs). Result-location semantics for type coercion. Go requires pre-resolved types. Swift SILGen is 79K lines. Rust HIR lowering outputs another AST. |
| CIR dialect | MLIR (Lattner) | `~/claude/references/llvm-project/mlir/` | — | CIR IS an MLIR dialect. TableGen, traits, regions, progressive lowering. This is what Lattner built MLIR for. |
| Type resolution | Zig Sema type patterns | `~/claude/references/zig/src/Sema.zig` | 34,000 | Only reference that resolves types on an untyped IR. Go/Rust resolve before IR. Swift resolves during SILGen. Zig's pattern matches CIR's design. |
| Comptime | Zig Sema comptime | `~/claude/references/zig/src/Sema.zig` | 34,000 | Only compiler with first-class compile-time evaluation as an IR concept. Rust has const fn (MIRI interpreter). Go/Swift have nothing equivalent. |
| ARC | Swift SILOptimizer/ARC | `~/claude/references/swift/lib/SILOptimizer/ARC/` | ~10,000 | Swift invented compiler ARC. Bidirectional dataflow, retain/release insertion + optimization, copy-on-write. No other reference has ARC as a compiler pass. |
| Concurrency | Swift SILOptimizer/Mandatory | `~/claude/references/swift/lib/SILOptimizer/Mandatory/` | ~4,000 | Swift's structured concurrency is the reference. Async→coroutine transform, actor isolation. Go uses runtime goroutines. Rust uses library Pin/Future. |
| Traits/generics | Rust monomorphization | `~/claude/references/rust/compiler/rustc_monomorphize/` | ~3,000 | Cleanest monomorphization. Go uses runtime interfaces. Swift uses witness tables. Zig uses comptime. Rust's zero-cost generics are proven. |
| CIR→LLVM lowering | MLIR ConversionPatterns | `~/claude/references/llvm-project/mlir/lib/Conversion/` | — | Lattner's ConversionPattern + TypeConverter + ConversionTarget. The canonical MLIR lowering pattern. |
| CIR dialect design | Flang FIR dialect | `~/claude/references/flang-ref/flang/include/flang/Optimizer/Dialect/` | — | Production MLIR dialect: FIROps.td, FIRTypes.td, FIRAttr.td. The closest real-world analogue to CIR. |
| Type philosophy | Swift stdlib + Builtins | `~/claude/references/swift/stdlib/public/core/` + `include/swift/AST/BuiltinTypes.def` | — | Lattner's separation: compiler knows only builtins, stdlib defines Int/Bool/etc. as structs wrapping builtins. CIR adopts this: MLIR types are builtins, language types resolved by frontends. |
| FIR→LLVM codegen | Flang CodeGen | `~/claude/references/flang-ref/flang/lib/Optimizer/CodeGen/` | — | Production FIR→LLVM lowering. ConversionPatterns at scale. |
| Backend | MLIR→LLVM IR→TargetMachine | `~/claude/references/llvm-project/mlir/lib/Target/LLVMIR/` | — | Built into MLIR. translateModuleToLLVMIR → LLVM TargetMachine → native/wasm. Lattner's full pipeline. |

---

## How To Use This Document

Before writing any component:

1. **Find the row** in the table above
2. **Read the reference source** at the listed location
3. **Port the pattern** — adapt the architecture, not the language-specific details
4. **Do NOT invent** logic that the reference doesn't have

If a component isn't in this table, it hasn't been audited yet. Audit before writing.

---

## The Lattner Thread

Chris Lattner designed LLVM (2000), Clang (2007), Swift/SIL (2014), and MLIR (2019). COT builds the next layer:

```
LLVM (backends)  →  MLIR (dialect infrastructure)  →  CIR (universal frontend IR)
     Lattner              Lattner                         COT
```

CIR is what MLIR was designed to enable: a universal IR that any frontend can target, with progressive lowering through best-of-breed passes, all the way down to LLVM machine code.

Design principles inherited from Lattner:
- **Progressive lowering** — CIR ops → typed CIR → LLVM dialect → LLVM IR → machine code
- **Dialect-based extensibility** — ARC, concurrency, traits are separate dialects injected by passes
- **Clean abstractions** — each pass has one job, reads IR in, writes IR out
- **Reusable infrastructure** — libcir is a library any tool can link against
- **Verify at every level** — MLIR verifier runs after each pass
