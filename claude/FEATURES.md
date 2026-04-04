# COT Feature Implementation Plan

**Date:** 2026-04-05
**Rule:** Each feature adds CIR ops + ac syntax + Zig syntax + TypeScript syntax + lowering + test. All three frontends must stay in sync. Nothing ships without a test.

**Progress: ~50 of ~120 features implemented (42%). 55 CIR ops, 8 types, 134 tests.**
Cross-referenced with `claude/CONSTRUCT_MASTER_LIST.md` for Zig (84 constructs) and TypeScript (93 constructs) coverage.

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

Test directory: `test/` with numbered files matching this table.

---

## Feature Table

Each row is one deliverable. For each feature:
1. Add CIR op(s) to `libcir/include/CIR/CIROps.td`
2. Add lowering pattern to `libcot/lib/CIRToLLVM.cpp`
3. Add ac syntax to `libac/` (scanner + parser + codegen)
4. Add Zig handling to `libzc/astgen.zig`
5. Add lit test for BOTH frontends (`test/lit/ac/` and `test/lit/zig/`)
6. Add inline test (`test/inline/`) for runtime correctness
7. Update `claude/AC_SYNTAX.md`

Status: `-` not started, `~` in progress, `✓` done.

### Phase 1 — Minimal Viable Compiler

| # | Feature | CIR Op(s) | ac Syntax | Zig Syntax | LLVM Lowering | Status |
|---|---------|-----------|-----------|------------|---------------|--------|
| 001 | Integer constants | `cir.constant` | `42` | `42` | `llvm.mlir.constant` | ✓ |
| 002 | Integer add/sub/mul | `cir.add/sub/mul` | `a + b` | `a + b` | `llvm.add/sub/mul` | ✓ |
| 003 | Function declaration | `func.func` | `fn f(a: i32) -> i32 { }` | `pub fn f(a: i32) i32 { }` | `func-to-llvm` | ✓ |
| 004 | Function calls | `func.call` | `add(19, 23)` | `add(19, 23)` | `func-to-llvm` | ✓ |
| 005 | Integer div/mod | `cir.div/rem` | `a / b`, `a % b` | `@divTrunc(a, b)`, `@mod(a, b)` | `llvm.sdiv/srem` | ✓ |
| 006 | Boolean constants | `cir.constant` i1 | `true`, `false` | `true`, `false` | `llvm.mlir.constant` | ✓ |
| 007 | Comparisons | `cir.cmp` | `==` `!=` `<` `<=` `>` `>=` | same | `llvm.icmp` | ✓ |
| 008 | Negation | `cir.neg` | `-x` | `-%x` or `0 - x` | `llvm.sub(0,x)` | ✓ |
| 009 | Bitwise ops | `cir.bit_and/or/xor/not` | `&` `\|` `^` `~` | `&` `\|` `^` `~` | `llvm.and/or/xor` | ✓ |
| 010 | Shift ops | `cir.shl/shr` | `<<` `>>` | `<<` `>>` | `llvm.shl/lshr` | ✓ |

### Phase 2 — Variables and Control Flow

| # | Feature | CIR Op(s) | ac Syntax | Zig Syntax | LLVM Lowering | Status |
|---|---------|-----------|-----------|------------|---------------|--------|
| 011 | Let bindings (immutable) | `cir.alloca`, `cir.store`, `cir.load` | `let x: i32 = 10` | `const x: i32 = 10;` | `llvm.alloca/store/load` | ✓ |
| 012 | Var bindings (mutable) | `cir.alloca`, `cir.store`, `cir.load` | `var x: i32 = 0` | `var x: i32 = 0;` | `llvm.alloca/store/load` | ✓ |
| 013 | Assignment | `cir.store` | `x = 42` | `x = 42;` | `llvm.store` | ✓ |
| 014 | Compound assignment | `cir.load`, `cir.add`, `cir.store` | `x += 1` | `x += 1;` | load+op+store | ✓ |
| 015 | If/else statement | `cir.condbr`, `cir.br` | `if x > 0 { } else { }` | `if (x > 0) { } else { }` | `llvm.cond_br/br` | ✓ |
| 016 | If/else expression | `cir.select` | `let x = if a > b { a } else { b }` | `const x = if (a > b) a else b;` | `llvm.select` | ✓ |
| 017 | While loop | `cir.condbr`, `cir.br` | `while x < 10 { }` | `while (x < 10) { }` | Loop with back-edge | ✓ |
| 018 | Break/continue | `cir.br` to exit/header | `break`, `continue` | `break`, `continue` | `llvm.br` | ✓ |
| 019 | For loop (range) | Desugared to while | `for i in 0..10 { }` | `while` (Zig has no range for) | Desugared while | ✓ |
| 020 | Nested functions/calls | (multiple `func.func`) | Functions calling functions | Same | Already works | ✓ |

### Phase 3 — Types and Aggregates

| # | Feature | CIR Op(s) | ac Syntax | Zig Syntax | LLVM Lowering | Status |
|---|---------|-----------|-----------|------------|---------------|--------|
| 021 | Multiple int types | `cir.constant` typed | `i8`, `i16`, `i32`, `i64`, `u8`..`u64` | `i8`, `i16`, `i32`, `i64`, `u8`..`u64` | MLIR integer types | ✓ |
| 022 | Float types | `cir.constant` (f32/f64) | `f32`, `f64`, `3.14` | `f32`, `f64`, `3.14` | `llvm.fadd/fsub/fmul/fdiv` | ✓ |
| 023 | Type casts | `cir.extsi/trunci/sitofp/fptosi/extf/truncf` | `x as i64` | `@intCast(x)`, `@floatCast(x)` | `llvm.sext/trunc/sitofp/fptosi/fpext/fptrunc` | ✓ |
| 024 | Struct declaration | `!cir.struct<"Name", fields...>` | `struct Point { x: i32, y: i32 }` | `const Point = struct { x: i32, y: i32 };` | LLVM struct type | ✓ |
| 025 | Struct construction | `cir.struct_init` | `Point { x: 1, y: 2 }` | `Point{ .x = 1, .y = 2 }` | `llvm.insertvalue` | ✓ |
| 026 | Struct field access | `cir.field_val`, `cir.field_ptr` | `p.x`, `p.y` | `p.x`, `p.y` | `llvm.extractvalue`, GEP | ✓ |
| 027 | Struct method syntax | Desugar to call | `p.distance()` | `p.distance()` | Regular function call | ✓ |
| 028 | Array type | `!cir.array<N x T>` | `[4]i32` | `[4]i32` | LLVM array type | ✓ |
| 029 | Array literal | `cir.array_init` | `[1, 2, 3, 4]` | `.{ 1, 2, 3, 4 }` | `llvm.insertvalue` chain | ✓ |
| 030 | Array indexing | `cir.elem_val`, `cir.elem_ptr` | `arr[i]` | `arr[i]` | extractvalue / GEP + load | ✓ |
| 030a | For-each (array/slice) | Desugared to while + index | `for item in arr { }` | `for (items) \|item\| { }` | Index loop | - |

### Phase 4 — Pointers and Strings

| # | Feature | CIR Op(s) | ac Syntax | Zig Syntax | LLVM Lowering | Status |
|---|---------|-----------|-----------|------------|---------------|--------|
| 031 | Pointer type | `!cir.ref<T>` | `*i32`, `*Point` | `*i32`, `*Point` | LLVM pointer type | ✓ |
| 032 | Address-of | `cir.addr_of` | `&x` | `&x` | Identity (ptr→ref) | ✓ |
| 033 | Dereference | `cir.deref` | `*p` | `p.*` | `llvm.load` | ✓ |
| 034 | Pointer to struct field | auto-deref + `cir.field_ptr` | `p.x` (auto-deref) | `p.x` (auto-deref) | deref + extractvalue | ✓ |
| 035 | String type | `!cir.slice<i8>` | `string` | `[]const u8` | `!llvm.struct<(ptr, i64)>` | ✓ |
| 036 | String literal | `cir.string_constant` | `"hello"` | `"hello"` | `llvm.mlir.global` + addressof + struct | ✓ |
| 037 | Slice ptr/len | `cir.slice_ptr`, `cir.slice_len` | `s.ptr`, `s.len` | `s.ptr`, `s.len` | `llvm.extractvalue [0]/[1]` | ✓ |
| 038 | Slice indexing | `cir.slice_elem` | `s[i]` | `s[i]` | extractvalue + GEP + load | ✓ |
| 039 | Slice from array | `cir.array_to_slice` | `arr[lo..hi]` | — | GEP + sub + struct | ✓ |
| 040 | Slice type syntax | — | `[]i32` param/return | `[]const u8` | — (type exists) | ✓ |

### Phase 5 — Error Handling and Optionals

| # | Feature | CIR Op(s) | ac Syntax | Zig Syntax | LLVM Lowering | Status |
|---|---------|-----------|-----------|------------|---------------|--------|
| 041 | Optional type | `!cir.optional<T>` | `?i32` | `?i32` | `!llvm.struct<(T, i1)>` or null-ptr | ✓ |
| 042 | Optional wrap | `cir.wrap_optional` | `let x: ?i32 = 42` | implicit | insertvalue {val, true} | ✓ |
| 043 | Null literal | `cir.none` | `null` | `null` | undef + insertvalue {_, false} | ✓ |
| 044 | is_non_null + payload | `cir.is_non_null`, `cir.optional_payload` | — | — | extractvalue [1], extractvalue [0] | ✓ |
| 045 | Error union type | `!cir.error_union<T>`, `cir.wrap_result`, `cir.wrap_error` | `!i32` | `E!i32` | `!llvm.struct<(T, i16)>` | ✓ |
| 046 | Try expression | `cir.is_error` + `cir.error_payload` + `cir.error_code` | `try foo()` | `try foo()` | Branch on error code | ✓ |
| 047 | Catch expression | `cir.is_error` + `cir.error_payload` + handler | `foo() catch \|e\| { }` | `foo() catch \|e\| { }` | Branch + error handler | ✓ |
| 048 | Error set declaration | Frontend assigns i16 codes | `error(1)` | `error { OutOfMemory, NotFound }` | Integer constants | ✓ |

### Phase 6 — Enums, Unions, Match

| # | Feature | CIR Op(s) | ac Syntax | Zig Syntax | LLVM Lowering | Status |
|---|---------|-----------|-----------|------------|---------------|--------|
| 049 | Enum declaration | `!cir.enum<"Name", TagType, ...>`, `cir.enum_constant` | `enum Color { Red, Green, Blue }` | `const Color = enum(u8) { red, green, blue };` | TagType integer | ✓ |
| 050 | Enum value | `cir.enum_value` | `Color.Red` | `.red` or `Color.red` | Identity (enum = integer) | ✓ |
| 051 | Match/switch statement | `cir.switch_br` | `match x { ... }` | `switch (x) { ... }` | `llvm.switch` | - |
| 052 | Match/switch expression | `cir.switch_br` + value | `let y = match x { ... }` | `const y = switch (x) { ... };` | Switch + phi | - |
| 053 | Tagged union | `cir.union_type` | `union { i32, f64, string }` | `const U = union(enum) { int: i32, float: f64 };` | Tag + payload | - |
| 054 | Union match + payload | `cir.get_union_tag`, `cir.union_payload` | `match u { .Int \|v\| => ... }` | `switch (u) { .int => \|v\| ... }` | Tag switch + extract | - |
| 054a | Short-circuit && \|\| | `cir.condbr` chain | `a and b`, `a or b` | `a and b`, `a or b` | Branch chain | - |
| 054b | Orelse / ?? | `cir.is_non_null + select` | `x orelse 0` | `x orelse 0` / TS `x ?? 0` | Null check + select | - |
| 054c | Force unwrap .? / x! | `cir.optional_payload + trap` | `x!` | `x.?` / TS `x!` | Payload + trap on null | - |

### Phase 7 — Generics and Traits

| # | Feature | CIR Op(s) | ac Syntax | Zig Syntax | LLVM Lowering | Status |
|---|---------|-----------|-----------|------------|---------------|--------|
| 055 | Generic function | `cir.func` + type params | `fn max[T](a: T, b: T) -> T` | `fn max(comptime T: type, a: T, b: T) T` | Monomorphize | - |
| 056 | Generic struct | `cir.struct_type` + params | `struct Pair[T] { a: T, b: T }` | `fn Pair(comptime T: type) type { return struct { a: T, b: T }; }` | Monomorphize | - |
| 057 | Trait declaration | `cir.trait_decl` | `trait Hashable { fn hash(self) -> u64 }` | (no Zig equivalent — use `anytype`) | Witness table | - |
| 058 | Trait implementation | `cir.trait_impl` | `impl Hashable for Point { }` | (no Zig equivalent — duck typing via `anytype`) | Generate witness | - |
| 059 | Trait bounds | `cir.trait_bound` | `fn foo[T: Hashable](x: T)` | `fn foo(x: anytype) ...` | Monomorphize | - |
| 060 | Trait objects | `cir.existential` | `dyn Hashable` | (no Zig equivalent) | Existential container | - |
| 060a | Do-while loop | `cir.condbr` (post-test) | `do { } while cond` | (no Zig equiv) / TS `do {} while()` | Loop with post-test | - |
| 060b | Increment/decrement | load + add/sub + store | `x++`, `++x` | (no Zig equiv) / TS `x++` | Desugar to load+op+store | - |
| 060c | Indirect call | `cir.call_indirect` | `fn_ptr(args)` | callback pattern | LLVM indirect call | - |
| 060d | Optional chaining | `cir.is_non_null + condbr` | `x?.y` | (no Zig equiv) / TS `x?.y` | Null check + field/null | - |
| 060e | Non-null assert | `cir.optional_payload` | `x!` | (no Zig equiv) / TS `x!` | Payload extract | - |
| 060f | Type assertion | noop / cast | `x as T` | (no Zig equiv) / TS `x as T` | Cast or noop | - |

### Phase 8 — Memory Management (ARC from Swift)

| # | Feature | CIR Op(s) | ac Syntax | Zig Syntax | LLVM Lowering | Status |
|---|---------|-----------|-----------|------------|---------------|--------|
| 061 | Heap allocation | `cir_arc.alloc` | `new Point { x: 1, y: 2 }` | `allocator.create(Point)` | Malloc + refcount header | - |
| 062 | Automatic retain/release | `cir_arc.retain`, `cir_arc.release` | (implicit) | (manual — Zig has no ARC) | Atomic inc/dec | - |
| 063 | ARC optimization | (pass removes redundant pairs) | (implicit) | (N/A for Zig) | Eliminate retain+release | - |
| 064 | Weak references | `cir_arc.weak_retain/release` | `weak *Point` | (N/A for Zig) | Side-table alloc | - |
| 065 | Move semantics | `cir_arc.move` | `move x` | (Zig moves by default) | Transfer without retain | - |
| 065a | Wrapping arithmetic | `cir.add_wrap/sub_wrap/mul_wrap` | `a +% b` | `a +% b` (Zig) | LLVM add nsw/nuw | - |
| 065b | Saturating arithmetic | `cir.add_sat/sub_sat` | `a +\| b` | `a +\| b` (Zig) | LLVM sadd.sat | - |
| 065c | Tuple type + init | `!cir.tuple + cir.tuple_init` | `(i32, f64)` | (no TS equiv) | LLVM struct | - |
| 065d | Destructuring | desugar to field/elem | `let (a, b) = tup` | TS `const {a, b} = obj` | Multiple stores | - |
| 065e | Spread operator | desugar | `[...arr, x]` | TS `[...arr]` | Copy + append | - |
| 065f | Labeled blocks | block names + args | `blk: { break :blk val }` | TS labels | Block args | - |
| 065g | instanceof / in | runtime type check | — | TS `x instanceof C` | Runtime check call | - |

### Phase 9 — Concurrency (from Swift)

| # | Feature | CIR Op(s) | ac Syntax | Zig Syntax | LLVM Lowering | Status |
|---|---------|-----------|-----------|------------|---------------|--------|
| 066 | Async function | `cir_conc.async_frame` | `async fn fetch() -> string` | `fn fetch() callconv(.Async) []u8` | LLVM coroutine intrinsics | - |
| 067 | Await expression | `cir_conc.async_suspend/resume` | `await fetch()` | `await @asyncCall(...)` | Coroutine suspend/resume | - |
| 068 | Task spawn | `cir_conc.task_spawn` | `spawn fetch()` | `_ = async fetch()` | Create task + schedule | - |
| 069 | Channels | `cir_conc.channel_*` | `chan[i32]` | (no Zig equivalent) | Ring buffer + sync | - |
| 070 | Actors | `cir_conc.actor_*` | `actor Counter { }` | (no Zig equivalent) | Mailbox + isolation | - |

### Phase 10 — Comptime (from Zig)

| # | Feature | CIR Op(s) | ac Syntax | Zig Syntax | LLVM Lowering | Status |
|---|---------|-----------|-----------|------------|---------------|--------|
| 071 | Comptime block | `cir.comptime_block` | `comptime { }` | `comptime { }` | Evaluate at compile time | - |
| 072 | Comptime params | `cir.param_comptime` | `fn foo(comptime T: type)` | `fn foo(comptime T: type)` | Monomorphize | - |
| 073 | Type reflection | `cir.type_info` | `@typeInfo(T)` | `@typeInfo(T)` | Compile-time struct | - |
| 074 | Inline for | `cir.inline_for` | `inline for` | `inline for` | Unroll at comptime | - |
| 075 | Static assert | `cir.comptime_assert` | `comptime assert(...)` | `comptime { assert(...); }` | Error if false | - |

### Phase 11 — Standard Library and I/O

| # | Feature | CIR Op(s) | ac Syntax | Zig Syntax | LLVM Lowering | Status |
|---|---------|-----------|-----------|------------|---------------|--------|
| 076 | Extern function | `cir.extern` | `extern fn write(...)` | `extern fn write(...) ...` | LLVM external func | - |
| 077 | Print string | (uses extern write) | `print("hello")` | `std.debug.print("hello", .{})` | Syscall or libc | - |
| 078 | Import module | `cir.import` | `import "std"` | `const std = @import("std");` | Link module | - |
| 079 | Defer statement | `cir.defer` | `defer close(fd)` | `defer close(fd);` | Cleanup block on scope exit | - |
| 079a | Errdefer | `cir.errdefer` | `errdefer cleanup()` | `errdefer cleanup();` | Cleanup on error only | - |
| 080 | Multiple return values | (tuple or struct return) | `fn divmod(a, b) -> (i32, i32)` | `fn divmod(a: i32, b: i32) struct { q: i32, r: i32 }` | LLVM struct return | - |
| 080a | Unreachable | `cir.unreachable` | `unreachable` | `unreachable` | `llvm.unreachable` | - |
| 080b | For-each / iterators | desugar to while | `for item in arr { }` | Zig `for(items) \|item\|` / TS `for (x of arr)` | Index loop | - |
| 080c | Template literals | string concat | — | TS `` `hello ${name}` `` | String ops | - |
| 080d | Inline assembly | passthrough | `asm { }` | Zig `asm volatile` | LLVM inline asm | - |
| 080e | Safety ops | `cir.bounds_check`, `cir.null_check` | (implicit) | (pass-injected) | Branch + trap | - |

### Phase 12 — Classes (TypeScript-specific)

| # | Feature | CIR Op(s) | ac Syntax | Zig Syntax | LLVM Lowering | Status |
|---|---------|-----------|-----------|------------|---------------|--------|
| 081 | Class declaration | vtable struct | `class Foo { }` | (no Zig equiv) / TS `class Foo { }` | Struct + vtable | - |
| 082 | Constructor | init function | `new Foo(args)` | (no Zig equiv) / TS `new Foo()` | Alloc + init call | - |
| 083 | Class methods | function in vtable | `foo.method()` | (no Zig equiv) / TS `foo.method()` | Indirect call | - |
| 084 | Class properties | struct fields | `foo.prop` | (no Zig equiv) / TS `foo.prop` | Field access | - |
| 085 | Getter/Setter | accessor functions | `get x() {}` | (no Zig equiv) / TS `get x() {}` | Function call | - |
| 086 | Static members | module-level | `static foo()` | (no Zig equiv) / TS `static foo()` | Regular function | - |
| 087 | Inheritance (extends) | vtable chain | `class B extends A` | (no Zig equiv) / TS `extends` | Vtable + struct embed | - |
| 088 | Abstract class | interface | `abstract class A` | (no Zig equiv) / TS `abstract` | Vtable with null slots | - |

---

## Implementation Order Rationale

**Phase 1 (001-010):** Proves the full pipeline works. Every reference compiler starts here.

**Phase 2 (011-020):** Variables and control flow are the minimum for useful programs. Every IR has alloc/load/store and branch/loop.

**Phase 3 (021-030):** Types and aggregates. Structs are how all C-style languages organize data. Includes for-each iteration over arrays.

**Phase 4 (031-040):** Pointers and strings. Required for any real program. Strings are slices.

**Phase 5 (041-048):** Error handling. This is where ac diverges from C — Zig-style error unions instead of exceptions.

**Phase 6 (049-054):** Enums and pattern matching. Rust/Swift pattern — tagged unions are the safe alternative to C unions. Zig uses `switch`, ac uses `match`.

**Phase 7 (055-060):** Generics. Monomorphized (Rust pattern) not erased (Java pattern). Zig uses `comptime` + `anytype` instead of traits.

**Phase 8 (061-065):** ARC from Swift. This is where ac gets memory safety without a garbage collector. Zig has manual memory management — ARC is ac-only.

**Phase 9 (066-070):** Concurrency from Swift. Structured concurrency, actors, channels. Zig has async/await but different model.

**Phase 10 (071-075):** Comptime from Zig. Compile-time evaluation as a first-class feature.

**Phase 11 (076-080):** Standard library. Makes ac useful for real programs.

---

## ac Syntax Documentation

Syntax is documented as it's implemented. Each feature adds to `claude/AC_SYNTAX.md`.
