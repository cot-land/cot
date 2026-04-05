# CIR Developer Experience — Errors, Diagnostics, Debugging

**Date:** 2026-04-05
**Purpose:** Design best-of-class error messages and debugging infrastructure for COT.
**Standard:** Rust-quality errors. MLIR-native diagnostics. Consistent from frontend to backend.

---

## The Bar: Rust Error Messages

Rust's compiler errors are the industry gold standard. Example:

```
error[E0308]: mismatched types
 --> src/main.rs:4:24
  |
3 | fn add(a: i32, b: i32) -> i32 {
  |                            --- expected `i32` because of return type
4 |     return a + b + "hello";
  |                    ^^^^^^^ expected `i32`, found `&str`
  |
help: if you meant to write a string literal, use double quotes
  |
4 |     return a + b + "hello";
  |                    ~~~~~~~
```

Key qualities:
1. **File, line, column** — exact source location
2. **Source context** — shows the offending line with underline
3. **Multi-span** — points to both the expected and actual types
4. **Suggestions** — "did you mean?" with concrete fix
5. **Error codes** — E0308 links to detailed explanation
6. **Color** — severity-based coloring (red=error, yellow=warning, blue=note)

COT must match this quality. MLIR provides the infrastructure — we just need to use it.

---

## Architecture: MLIR Diagnostic Pipeline

MLIR has a complete diagnostic system built in. We are currently not using it properly.

### Current State (broken)

```
Frontend → UnknownLoc on every op → "error at byte N" → useless
```

### Target State (Rust-quality)

```
Frontend (libac/libzc/libtc)
  │ Creates FileLineColLoc(filename, line, col) for every op
  │ Frontend parse errors → cirDiagnosticEmit(loc, Error, "message")
  ▼
CIR Ops
  │ Every op carries source location from the frontend
  │ Verifiers use emitOpError() → auto-includes location
  ▼
Sema Pass
  │ Type errors → op.emitError() << "expected i32, got f64"
  │ Attaches notes: op.emitError().attachNote(otherLoc) << "declared here"
  ▼
CIR→LLVM Lowering
  │ Lowering failures → rewriter.notifyMatchFailure(op, "reason")
  ▼
DiagnosticHandler (cot driver)
  │ Receives ALL diagnostics from ALL stages
  │ Reads source file, formats with context and colors
  │ Consistent output regardless of which stage produced the error
  ▼
Beautiful error messages
```

---

## 1. Source Locations — The Foundation

### MLIR Location Types

MLIR provides several location types. We should use them all:

```cpp
// Exact source position (PRIMARY — use for every op)
auto loc = FileLineColLoc::get(ctx, "src/main.ac", 4, 24);

// Fused location (multiple source positions for one op)
auto loc = FusedLoc::get(ctx, {declLoc, useLoc});

// Named location (adds semantic context)
auto loc = NameLoc::get(StringAttr::get(ctx, "variable 'x'"), innerLoc);

// Call site location (for inlined code — shows call chain)
auto loc = CallSiteLoc::get(calleeLoc, callerLoc);

// Opaque location (carries frontend-specific metadata)
auto loc = OpaqueLoc::get<FrontendData*>(data, fallbackLoc);
```

### What Each Frontend Must Do

**ac (C++):**
```cpp
// In codegen.cpp — create location from token position
mlir::Location locFromToken(const Token &tok) {
    auto [line, col] = sourceLineCol(tok.start);
    return FileLineColLoc::get(b.getContext(),
        StringRef(filename_), line, col);
}
```

**Zig (Zig):**
```zig
// In astgen.zig — create location from AST node
fn locFromNode(self: *Gen, node: Node.Index) mlir.Location {
    const tok = self.tree.nodeMainToken(node);
    const loc = self.tree.tokenLocation(tok);
    return mlir.mlirLocationFileLineColGet(self.ctx,
        mlir.StringRef.fromSlice(self.filename),
        loc.line, loc.column);
}
```

**TypeScript (Go):**
```go
// In codegen.go — create location from AST node
func (g *Gen) locFromNode(node *ast.Node) MlirLocation {
    pos := g.sourceFile.LineAndCharacterOfPosition(node.Pos())
    return MlirLocationFileLineColGet(g.b.ctx,
        g.filename, pos.Line, pos.Character)
}
```

### C API Addition

```c
// Create a file:line:col location
MlirLocation cirLocationFileLineCol(MlirContext ctx,
                                     MlirStringRef filename,
                                     unsigned line,
                                     unsigned col);
```

This wraps `mlir::FileLineColLoc::get`. Frontends call it for every op they create.

---

## 2. Diagnostic Handler — Formatting Engine

### Registration

```cpp
// In cot/main.cpp — register handler before running any passes
mlir::SourceMgrDiagnosticHandler diagHandler(sourceMgr, &context);
```

MLIR's `SourceMgrDiagnosticHandler` already formats diagnostics with source context
if you give it the source file. This is the simplest path to Rust-quality errors.

### Custom Handler (for maximum control)

```cpp
class CotDiagnosticHandler {
    llvm::SourceMgr &srcMgr;
    bool useColors;

    void handleDiagnostic(mlir::Diagnostic &diag) {
        auto loc = diag.getLocation();
        auto severity = diag.getSeverity();

        // Print severity with color
        printSeverity(severity);  // "error:" in red, "warning:" in yellow

        // Print location
        if (auto fileLoc = dyn_cast<FileLineColLoc>(loc))
            llvm::errs() << fileLoc.getFilename() << ":"
                         << fileLoc.getLine() << ":"
                         << fileLoc.getColumn() << ": ";

        // Print message
        llvm::errs() << diag.str() << "\n";

        // Print source context with underline
        printSourceContext(loc);

        // Print attached notes
        for (auto &note : diag.getNotes()) {
            llvm::errs() << "note: ";
            handleDiagnostic(note);  // recursive
        }

        // Print suggestions (if attached as metadata)
        printSuggestions(diag);
    }
};
```

### What This Produces

```
error: type mismatch in return
 --> src/main.ac:4:12
  |
3 | fn add(a: i32, b: i32) -> i32 {
  |                            --- expected `i32` because of return type
4 |     return "hello"
  |            ^^^^^^^ found `string`

error: undefined variable 'xyz'
 --> src/main.ac:7:5
  |
7 |     xyz + 1
  |     ^^^ not found in this scope
  |
note: did you mean 'x'?
 --> src/main.ac:6:9
  |
6 |     let x: i32 = 10
  |         ^ defined here
```

---

## 3. Structured Diagnostics — Sema Pass

### Current Sema (minimal)

```cpp
// Today: bare string errors
return op.emitError() << "type mismatch";
```

### Target Sema (Rust-quality)

```cpp
// Multi-span error with notes and suggestions
auto diag = op.emitError() << "mismatched types";

// Point to the expected type
diag.attachNote(funcReturnTypeLoc)
    << "expected `" << expectedType << "` because of return type";

// Point to the actual value
diag.attachNote(valueLoc)
    << "found `" << actualType << "`";

// Suggest a fix if possible
if (canCast(actualType, expectedType))
    diag.attachNote(valueLoc)
        << "help: use `" << actualValue << " as "
        << expectedType << "` to cast";
```

### Error Categories

Each error should have a code for documentation:

| Code | Category | Example |
|------|----------|---------|
| E001 | Type mismatch | `expected i32, found f64` |
| E002 | Undefined variable | `'xyz' not found in scope` |
| E003 | Undefined function | `'foo' not found` |
| E004 | Argument count | `expected 2 arguments, got 3` |
| E005 | Argument type | `argument 1: expected i32, found string` |
| E006 | Invalid cast | `cannot cast string to i32` |
| E007 | Missing return | `function must return i32` |
| E008 | Unreachable code | `code after return is unreachable` |
| E009 | Duplicate definition | `'x' already defined at line 3` |
| E010 | Invalid field | `struct 'Point' has no field 'z'` |

---

## 4. Frontend Error Protocol — C API

Frontends need to emit their own errors (parse errors, name resolution) through
the same diagnostic system. Add to CIR C API:

```c
/// Emit a diagnostic through MLIR's diagnostic engine.
/// Severity: 0=Error, 1=Warning, 2=Note, 3=Remark
void cirDiagnosticEmit(MlirContext ctx, MlirLocation loc,
                       int severity, MlirStringRef message);

/// Attach a note to the most recent diagnostic.
void cirDiagnosticNote(MlirContext ctx, MlirLocation loc,
                       MlirStringRef message);
```

Frontend usage:

```zig
// Zig frontend — parse error
cirDiagnosticEmit(self.ctx, loc, 0,  // 0 = Error
    StringRef.fromSlice("expected ';' after statement"));
```

```go
// TS frontend — type error
CirDiagnosticEmit(g.b.ctx, loc, 0,
    "cannot assign 'string' to variable of type 'number'")
```

---

## 5. Pipeline Debugging — Development Experience

### MLIR Built-in Tools

MLIR provides powerful debugging infrastructure that we should expose:

**IR Printing (after each pass):**
```bash
# Print CIR after every pass — shows the transformation pipeline
cot emit-llvm file.ac --mlir-print-ir-after-all

# Print only after failures
cot emit-llvm file.ac --mlir-print-ir-after-failure

# Print IR before and after a specific pass
cot emit-llvm file.ac --mlir-print-ir-before=cir-sema --mlir-print-ir-after=cir-sema
```

**Pass Statistics:**
```bash
# Show timing and statistics for each pass
cot build file.ac --mlir-pass-statistics

# Output:
#   SemanticAnalysis  - 0.3ms, 5 casts inserted
#   CIRToLLVM         - 1.2ms, 45 ops converted
```

**Verification:**
```bash
# Run verifier after every pass (default in debug builds)
cot build file.ac --mlir-verify-each

# Disable verification (release builds)
cot build file.ac --mlir-disable-verify
```

### CIR-Specific Debug Commands

```bash
# Show the pipeline stages
cot emit-cir file.ac          # CIR after frontend
cot emit-cir-sema file.ac     # CIR after Sema pass
cot emit-llvm file.ac          # LLVM dialect after lowering
cot emit-llvm-ir file.ac       # LLVM IR (text)
cot emit-asm file.ac           # Assembly

# Diff between stages
cot emit-cir file.ac > before.mlir
cot emit-cir-sema file.ac > after.mlir
diff before.mlir after.mlir    # Shows what Sema changed
```

### MLIR Debug Actions

MLIR has a debug action framework for breakpoint-like debugging:

```cpp
// In a pass — register a debug action
context.registerActionHandler([](DebugActionManager::ActionTag tag,
                                  const IRUnit &unit) {
    llvm::errs() << "Pass acting on: " << unit << "\n";
    return DebugActionManager::Proceed;
});
```

### Source-Level Debugging (DWARF)

For debugging compiled programs (not the compiler itself), we need to emit
DWARF debug info. MLIR has `mlir::LLVM::DISubprogramAttr` and related ops.

The path is:
1. Frontends attach `FileLineColLoc` to every op (already planned above)
2. During CIR→LLVM lowering, convert locations to LLVM debug metadata
3. LLVM emits DWARF sections in the binary
4. Users debug with `lldb`/`gdb` and see source lines

This is Phase 11+ work but the foundation (source locations) must be built now.

---

## 6. Implementation Plan

### Done (implemented)

| # | Action | Status |
|---|--------|--------|
| 1 | `cirLocationFileLineCol` C API | **DONE** — wraps `mlir::FileLineColLoc::get` |
| 2 | `cirDiagnosticEmit` C API | **DONE** — emits Error/Warning/Remark through MLIR engine |
| 3 | `FileLineColLoc` in ac frontend | **DONE** — `locFromOffset(byte_pos)` computes line:col |
| 4 | `FileLineColLoc` in Zig frontend | **DONE** — `locFromNode` uses `tree.tokenLocation` |
| 5 | `FileLineColLoc` in TS frontend | **DONE** — `locFromPos` binary search over ECMALineMap |
| 6 | MLIR CLI flags in driver | **DONE** — `--mlir-print-debuginfo`, `--mlir-print-ir-after-all`, `--mlir-pass-statistics` |
| 7 | Sema diagnostics with notes | **DONE** — arg count/type mismatch errors include "declared here" note |
| 8 | Graceful error handling | **DONE** — `hasError_` flag, dummy values on error, no more segfaults |
| 9 | Negative tests | **DONE** — 3 tests: arg_count, type_mismatch_return, bad_optional_unwrap |
| 10 | `%not` lit substitution | **DONE** — enables negative test patterns |

### Remaining (implement as compiler advances)

| # | Action | When | Effort | Impact |
|---|--------|------|--------|--------|
| 11 | Error codes (E001-E010) with documentation | Phase 7 | 2 hr | Searchable error codes |
| 12 | "Did you mean?" suggestions for undefined names | Phase 7 | 2 hr | Major DX improvement |
| 13 | SourceMgrDiagnosticHandler for source-context underlines | Phase 7 | 2 hr | Rust-style underlined errors |
| 14 | `cot emit-cir-sema` command | Phase 7 | 30 min | Stage inspection |
| 15 | Sema errors for generic type mismatches | Phase 7 | 4 hr | Generics need rich type errors |
| 16 | Class/trait conformance errors | Phase 7b/12 | 4 hr | "Type does not implement interface" |
| 17 | DWARF debug info emission | Phase 11 | 8 hr | Source-level debugging (lldb/gdb) |
| 18 | Error recovery in parser (continue after error) | Phase 11 | 6 hr | Report multiple errors per file |
| 19 | LSP integration (diagnostics as JSON) | Phase 11+ | 4 hr | IDE red squiggles |
| 20 | Colorized terminal output | Phase 11 | 1 hr | Red=error, yellow=warning |

---

## 7. Reference Implementations

| Feature | Reference | Source |
|---------|-----------|--------|
| Error formatting | Rust `rustc_errors` | `~/claude/references/rust/compiler/rustc_errors/` |
| Source location | MLIR Location | `~/claude/references/llvm-project/mlir/include/mlir/IR/Location.h` |
| Diagnostic engine | MLIR Diagnostics | `~/claude/references/llvm-project/mlir/include/mlir/IR/Diagnostics.h` |
| Source manager handler | MLIR SourceMgr | `~/claude/references/llvm-project/mlir/lib/IR/Diagnostics.cpp` |
| Zig errors | Zig Compilation | `~/claude/references/zig/src/Compilation.zig` |
| Swift diagnostics | Swift DiagnosticEngine | `~/claude/references/swift/include/swift/AST/DiagnosticEngine.h` |
| LLVM debug info | MLIR LLVM DI | `~/claude/references/llvm-project/mlir/include/mlir/Dialect/LLVMIR/LLVMOps.td` (DI attrs) |

---

## 8. Why This Architecture Works

1. **MLIR does the heavy lifting.** Location propagation, diagnostic routing, source
   manager integration — all built-in. We configure it, not build it.

2. **Consistent across all stages.** A type error in Sema and a parse error in the
   frontend use the same diagnostic handler. The user sees one consistent format.

3. **Consistent across all frontends.** ac, Zig, and TS all create `FileLineColLoc`
   and all call `cirDiagnosticEmit`. The handler formats them identically.

4. **Progressive enhancement.** We can start with basic file:line:col (immediate win)
   and add multi-span, suggestions, and error codes incrementally.

5. **Debug info comes free.** Once ops have source locations, DWARF emission during
   CIR→LLVM lowering is mostly mechanical — MLIR has the infrastructure.
