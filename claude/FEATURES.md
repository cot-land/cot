# COT Feature Implementation Plan

**Date:** 2026-04-03
**Rule:** Each feature adds CIR ops + ac syntax + lowering + test. Nothing ships without a test.

---

## Test Framework

**Pattern: MLIR lit + FileCheck** (industry standard for LLVM-based compilers)

Tests are `.ac` files with inline directives:
```ac
// RUN: cot build %s -o %t && %t | FileCheck %s
// CHECK: exit: 42

fn main() -> i32 {
    return 42
}
```

Until lit/FileCheck are wired up, we use a simpler pattern — test files that return specific exit codes:
```bash
./cot build test/001_int_literal.ac -o /tmp/t && /tmp/t; echo $?
# Expected: 42
```

Test directory: `test/` with numbered files matching this table.

---

## Feature Table

Each row is one deliverable. For each feature:
1. Add CIR op(s) to `libcir/include/CIR/CIROps.td`
2. Add lowering pattern to `cot/main.cpp` CIRToLLVMPass
3. Add ac syntax to `libac/` (scanner + parser + codegen)
4. Add Zig handling to `libzc/astgen.zig`
5. Add lit test for BOTH frontends (`test/lit/ac/` and `test/lit/zig/`)
6. Add inline test if feature supports assert
7. Update `claude/AC_SYNTAX.md`

Status: `-` not started, `~` in progress, `✓` done.

### Phase 1 — Minimal Viable Compiler

| # | Feature | CIR Op(s) | ac Syntax | Zig Syntax | LLVM Lowering | Status |
|---|---------|-----------|-----------|------------|---------------|--------|
| 001 | Integer constants | `cir.constant` | `42` | `42` | `llvm.mlir.constant` | ✓ |
| 002 | Integer add/sub/mul | `cir.add/sub/mul` | `a + b` | `a + b` | `llvm.add/sub/mul` | ✓ |
| 003 | Function declaration | `func.func` | `fn f(a: i32) -> i32 { }` | `fn f(a: i32) i32 { }` | `func-to-llvm` | ✓ |
| 004 | Function calls | `func.call` | `add(19, 23)` | `add(19, 23)` | `func-to-llvm` | ✓ |
| 005 | Integer div/mod | `cir.div/rem` | `a / b`, `a % b` | `a / b`, `a % b` | `llvm.sdiv/srem` | ✓ |
| 006 | Boolean constants | `cir.constant` i1 | `true`, `false` | `true`, `false` | `llvm.mlir.constant` | ✓ |
| 007 | Comparisons | `cir.cmp` | `==` `!=` `<` `<=` `>` `>=` | same | `llvm.icmp` | ✓ |
| 008 | Negation | `cir.neg` | `-x` | `-x` | `llvm.sub(0,x)` | ✓ |
| 009 | Bitwise ops | `cir.bit_and/or/xor/not` | `&` `\|` `^` `~` | same | `llvm.and/or/xor` | ✓ |
| 010 | Shift ops | `cir.shl/shr` | `<<` `>>` | same | `llvm.shl/lshr` | ✓ |

### Phase 2 — Variables and Control Flow

| # | Feature | CIR Op(s) | ac Syntax | Zig Syntax | LLVM Lowering | Status |
|---|---------|-----------|-----------|---------------|------|--------|
| 011 | Let bindings (immutable) | `cir.alloca`, `cir.store`, `cir.load` | `let x: i32 = 10` | `llvm.alloca/store/load` | Bind and use local | ✓ |
| 012 | Var bindings (mutable) | `cir.alloca`, `cir.store`, `cir.load` | `var x: i32 = 0` | `llvm.alloca/store/load` | Mutate and read | ✓ |
| 013 | Assignment | `cir.store` | `x = 42` | `llvm.store` | Assign to var | ✓ |
| 014 | Compound assignment | `cir.load`, `cir.add`, `cir.store` | `x += 1` | load+add+store | Increment variable | ✓ |
| 015 | If/else statement | `cir.condbr`, `cir.br` | `if x > 0 { } else { }` | `llvm.cond_br`, `llvm.br` | Branch on condition | ✓ |
| 016 | If/else expression | `cir.condbr` + block value | `let x = if a > b { a } else { b }` | Phi node or select | Ternary-style | - |
| 017 | While loop | `cir.condbr`, `cir.br` | `while x < 10 { }` | Loop with back-edge | Sum 1..10 = 55 | ✓ |
| 018 | Break/continue | `cir.break`, `cir.repeat` | `break`, `continue` | `llvm.br` to exit/header | Break from loop | - |
| 019 | For loop (range) | `cir.loop` + counter | `for i in 0..10 { }` | Desugared while | Sum range | - |
| 020 | Nested functions/calls | (multiple `func.func`) | Functions calling functions | Already works | Call chain 3 deep | - |

### Phase 3 — Types and Aggregates

| # | Feature | CIR Op(s) | ac Syntax | LLVM Lowering | Test | Status |
|---|---------|-----------|-----------|---------------|------|--------|
| 021 | Multiple int types | `cir.constant` typed | `i8`, `i16`, `i32`, `i64`, `u8`..`u64` | MLIR integer types | Type-specific arithmetic | - |
| 022 | Float types | `cir.constant` (f32/f64) | `f32`, `f64`, `3.14` | `llvm.fadd/fsub/fmul/fdiv` | Float arithmetic | - |
| 023 | Type casts | `cir.cast` | `x as i64` | `llvm.sext/trunc/sitofp/fptosi` | Cast between types | - |
| 024 | Struct declaration | `cir.struct_type` | `struct Point { x: i32, y: i32 }` | LLVM struct type | Declare struct | - |
| 025 | Struct construction | `cir.struct_init` | `Point { x: 1, y: 2 }` | `llvm.insertvalue` | Create struct value | - |
| 026 | Struct field access | `cir.field_val`, `cir.field_ptr` | `p.x`, `p.y` | `llvm.extractvalue`, GEP | Read struct fields | - |
| 027 | Struct method syntax | Desugar to call | `p.distance()` | Regular function call | Method call | - |
| 028 | Array type | `cir.array_type` | `[4]i32` | LLVM array type | Fixed-size array | - |
| 029 | Array literal | `cir.array_init` | `[1, 2, 3, 4]` | `llvm.insertvalue` chain | Create array | - |
| 030 | Array indexing | `cir.elem_val`, `cir.elem_ptr` | `arr[i]` | GEP + load | Read/write elements | - |

### Phase 4 — Pointers and Strings

| # | Feature | CIR Op(s) | ac Syntax | LLVM Lowering | Test | Status |
|---|---------|-----------|-----------|---------------|------|--------|
| 031 | Pointer type | `cir.ptr_type` | `*i32`, `*Point` | LLVM pointer type | Pointer declaration | - |
| 032 | Address-of | `cir.ref` | `&x` | Alloca address | Take address | - |
| 033 | Dereference | `cir.deref` | `*p` | `llvm.load` | Deref pointer | - |
| 034 | Pointer to struct field | `cir.field_ptr` | `&p.x` | GEP | Field pointer | - |
| 035 | String type | `cir.slice<u8>` | `string` | `{ptr, len}` struct | String as fat pointer | - |
| 036 | String literal | `cir.constant` (global) | `"hello"` | Global constant + slice | String in data section | - |
| 037 | Slice type | `cir.slice_type` | `[]i32` | `{ptr, len}` struct | Slice from array | - |
| 038 | Slice indexing | `cir.slice_elem` | `s[i]` | GEP on ptr field | Index into slice | - |
| 039 | Slice from array | `cir.array_to_slice` | `arr[1..3]` | Build `{ptr+off, len}` | Subslice | - |
| 040 | Slice length | `cir.slice_len` | `s.len` | Extract len field | Get slice length | - |

### Phase 5 — Error Handling and Optionals

| # | Feature | CIR Op(s) | ac Syntax | LLVM Lowering | Test | Status |
|---|---------|-----------|-----------|---------------|------|--------|
| 041 | Optional type | `cir.optional_type` | `?i32` | `{tag, payload}` or null-ptr | Optional declaration | - |
| 042 | Optional wrap/unwrap | `cir.wrap_optional`, `cir.optional_payload` | `?x`, `x!` | Tag check + extract | Wrap and unwrap | - |
| 043 | Null literal | `cir.constant` (null) | `null` | Zero-initialized optional | Null value | - |
| 044 | If-let optional | `cir.is_non_null` + branch | `if x \| val \| { }` | Branch on tag | Optional check | - |
| 045 | Error union type | `cir.error_union_type` | `!i32` or `Error!i32` | `{error_code, payload}` | Error union | - |
| 046 | Try expression | `cir.try` | `try foo()` | Branch on error code | Propagate error | - |
| 047 | Catch expression | `cir.catch` | `foo() catch \|e\| { }` | Branch + error handler | Handle error | - |
| 048 | Error set declaration | `cir.error_set` | `error { OutOfMemory, NotFound }` | Integer enum | Named errors | - |

### Phase 6 — Enums, Unions, Match

| # | Feature | CIR Op(s) | ac Syntax | LLVM Lowering | Test | Status |
|---|---------|-----------|-----------|---------------|------|--------|
| 049 | Enum declaration | `cir.enum_type` | `enum Color { Red, Green, Blue }` | Integer type | Enum values | - |
| 050 | Enum value | `cir.enum_literal` | `Color.Red` | Integer constant | Use enum | - |
| 051 | Match statement | `cir.switch_br` | `match x { ... }` | `llvm.switch` | Match on enum | - |
| 052 | Match expression | `cir.switch_br` + value | `let y = match x { ... }` | Switch + phi | Match as expression | - |
| 053 | Tagged union | `cir.union_type` | `union { i32, f64, string }` | Tag + payload | Tagged union | - |
| 054 | Union match + payload | `cir.get_union_tag`, `cir.union_payload` | `match u { .Int \|v\| => ... }` | Tag switch + extract | Pattern match union | - |

### Phase 7 — Generics and Traits

| # | Feature | CIR Op(s) | ac Syntax | LLVM Lowering | Test | Status |
|---|---------|-----------|-----------|---------------|------|--------|
| 055 | Generic function | `cir.func` + type params | `fn max[T](a: T, b: T) -> T` | Monomorphize (Rust pattern) | Generic max | - |
| 056 | Generic struct | `cir.struct_type` + params | `struct Pair[T] { a: T, b: T }` | Monomorphize | Generic pair | - |
| 057 | Trait declaration | `cir.trait_decl` | `trait Hashable { fn hash(self) -> u64 }` | Witness table | Declare trait | - |
| 058 | Trait implementation | `cir.trait_impl` | `impl Hashable for Point { }` | Generate witness | Implement trait | - |
| 059 | Trait bounds | `cir.trait_bound` | `fn foo[T: Hashable](x: T)` | Monomorphize with witness | Bounded generic | - |
| 060 | Trait objects | `cir.existential` | `dyn Hashable` | Existential container | Dynamic dispatch | - |

### Phase 8 — Memory Management (ARC from Swift)

| # | Feature | CIR Op(s) | ac Syntax | LLVM Lowering | Test | Status |
|---|---------|-----------|-----------|---------------|------|--------|
| 061 | Heap allocation | `cir_arc.alloc` | `new Point { x: 1, y: 2 }` | Malloc + refcount header | Allocate on heap | - |
| 062 | Automatic retain/release | `cir_arc.retain`, `cir_arc.release` | (implicit) | Atomic inc/dec | Pass/return heap objects | - |
| 063 | ARC optimization | (pass removes redundant pairs) | (implicit) | Eliminate retain+release | Optimize away copies | - |
| 064 | Weak references | `cir_arc.weak_retain/release` | `weak *Point` | Side-table alloc | Weak reference cycle | - |
| 065 | Move semantics | `cir_arc.move` | `move x` | Transfer without retain | Move ownership | - |

### Phase 9 — Concurrency (from Swift)

| # | Feature | CIR Op(s) | ac Syntax | LLVM Lowering | Test | Status |
|---|---------|-----------|-----------|---------------|------|--------|
| 066 | Async function | `cir_conc.async_frame` | `async fn fetch() -> string` | LLVM coroutine intrinsics | Async declaration | - |
| 067 | Await expression | `cir_conc.async_suspend/resume` | `await fetch()` | Coroutine suspend/resume | Await result | - |
| 068 | Task spawn | `cir_conc.task_spawn` | `spawn fetch()` | Create task + schedule | Spawn task | - |
| 069 | Channels | `cir_conc.channel_*` | `chan[i32]` | Ring buffer + sync | Send/receive | - |
| 070 | Actors | `cir_conc.actor_*` | `actor Counter { }` | Mailbox + isolation | Actor message passing | - |

### Phase 10 — Comptime (from Zig)

| # | Feature | CIR Op(s) | ac Syntax | LLVM Lowering | Test | Status |
|---|---------|-----------|-----------|---------------|------|--------|
| 071 | Comptime block | `cir.comptime_block` | `comptime { }` | Evaluate at compile time | Comptime arithmetic | - |
| 072 | Comptime params | `cir.param_comptime` | `fn foo(comptime T: type)` | Monomorphize | Comptime generic | - |
| 073 | Type reflection | `cir.type_info` | `@typeInfo(T)` | Compile-time struct | Reflect on type | - |
| 074 | Inline for | `cir.inline_for` | `inline for` | Unroll at comptime | Compile-time loop | - |
| 075 | Static assert | `cir.comptime_assert` | `comptime assert(...)` | Error if false | Compile-time check | - |

### Phase 11 — Standard Library and I/O

| # | Feature | CIR Op(s) | ac Syntax | LLVM Lowering | Test | Status |
|---|---------|-----------|-----------|---------------|------|--------|
| 076 | Extern function | `cir.extern` | `extern fn write(...)` | LLVM external func | Call libc | - |
| 077 | Print string | (uses extern write) | `print("hello")` | Syscall or libc | Hello world | - |
| 078 | Import module | `cir.import` | `import "std"` | Link module | Use std lib | - |
| 079 | Defer statement | `cir.defer` | `defer close(fd)` | Cleanup block on scope exit | Resource cleanup | - |
| 080 | Multiple return values | (tuple or struct return) | `fn divmod(a, b) -> (i32, i32)` | LLVM struct return | Return two values | - |

---

## Implementation Order Rationale

**Phase 1 (001-010):** Proves the full pipeline works. Every reference compiler starts here.

**Phase 2 (011-020):** Variables and control flow are the minimum for useful programs. Every IR has alloc/load/store and branch/loop.

**Phase 3 (021-030):** Types and aggregates. Structs are how all C-style languages organize data.

**Phase 4 (031-040):** Pointers and strings. Required for any real program. Strings are slices.

**Phase 5 (041-048):** Error handling. This is where ac diverges from C — Zig-style error unions instead of exceptions.

**Phase 6 (049-054):** Enums and pattern matching. Rust/Swift pattern — tagged unions are the safe alternative to C unions.

**Phase 7 (055-060):** Generics. Monomorphized (Rust pattern) not erased (Java pattern).

**Phase 8 (061-065):** ARC from Swift. This is where ac gets memory safety without a garbage collector.

**Phase 9 (066-070):** Concurrency from Swift. Structured concurrency, actors, channels.

**Phase 10 (071-075):** Comptime from Zig. Compile-time evaluation as a first-class feature.

**Phase 11 (076-080):** Standard library. Makes ac useful for real programs.

---

## ac Syntax Documentation

Syntax is documented as it's implemented. Each feature adds to `claude/AC_SYNTAX.md`.

Current ac (agentic cot) syntax — Phase 1:

```ac
// Functions
fn name(param: type, param: type) -> return_type {
    body
}

// Expressions
42                    // integer literal
a + b                 // addition
a - b                 // subtraction
a * b                 // multiplication
name(arg1, arg2)      // function call
-x                    // negation
(expr)                // grouping

// Statements
return expr           // return from function

// No semicolons — Go-style automatic insertion on newlines
// Line comments: // ...
```
