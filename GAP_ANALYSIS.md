# Gap Analysis: Current Cot vs Bootstrap-0.2

## Executive Summary

**Bootstrap-0.2** was a working compiler with **619 test cases** covering expressions, control flow, functions, types, arrays, memory, and variables. It compiled to native (AMD64/ARM64) directly.

**Current Cot** is a Wasm-first rewrite with **114 test case files**, **42 Wasm E2E tests**, **24 native E2E tests**, and **832 total tests** (including unit tests). It has surpassed bootstrap-0.2 in language features and architecture quality, but still has a test coverage gap.

**The gap: ~493 missing test cases. Most language features are now complete.**

---

## Test Coverage Comparison

### Bootstrap-0.2: 619 test files

| Category | Count | What It Covers |
|----------|-------|----------------|
| Expressions | 160 | All arithmetic, bitwise, comparison, logical, precedence, parenthesization |
| Functions | 115 | Calls, recursion, many params, chaining, mutual recursion, math functions |
| Control flow | 100 | if/else chains, while, break, continue, nested, complex conditions |
| Types | 65 | Locals, booleans, consts, structs, pointers, sized ints (i8-u64) |
| Arrays | 60 | Indexing, iteration, function params, modification, copying, search, sort |
| Memory | 53 | Stack locals, heap allocation, struct fields, references, pointer arithmetic |
| Variables | 47 | Declaration, type annotations, reassignment, scope, mutability |
| Bugs | 4 | Regression tests for string params, struct literals, large structs |
| Integration | 1 | Full pipeline test |
| Golden | 2 | Reference SSA/codegen output |

### Current Cot: 114 test files + 66 E2E tests

| Category | Files | E2E | What It Covers |
|----------|-------|-----|----------------|
| Functions | 16 | - | Basic calls, params, recursion, fibonacci, chaining, mutual |
| Control flow | 14 | - | if/else, while, break, continue, comparisons |
| Arithmetic | 10 | - | add, sub, mul, div, mod, precedence, negation |
| Strings | 9 | - | Length, concat, indexing |
| Compound assign | 8 | - | +=, -=, *=, /=, %=, &=, \|=, ^= |
| ARC | 7 | 4+4 | new, retain, release, destructor, ownership (Wasm+native E2E) |
| Arrays | 6 | - | Literal, sum, index, update, append |
| Bitwise | 6 | - | AND, OR, XOR, NOT, shifts |
| Memory | 5 | - | Locals, reassign, swap, accumulator |
| Structs | 5 | - | Simple, field access, field update, nested, pass to fn |
| Float | 4 | 1+1 | Basic, arithmetic, comparison, negation (Wasm+native E2E) |
| Builtins | 4 | - | @sizeOf, @alignOf, @intCast |
| Union | 4 | 4+4 | Simple, mixed, payload, switch capture (Wasm+native E2E) |
| Optional | 3 | - | Basic, coalesce, null coalesce |
| Loops | 3 | - | for-range sum, index, index+value |
| Chars | 2 | - | Simple, escape sequences |
| Enum | 2 | - | Simple, explicit values |
| Switch | 2 | - | Integer, enum |
| Types | 2 | - | Type alias, struct alias |
| Methods | 1 | - | Simple method call |
| Extern | 1 | - | Extern function declaration |
| Error unions | - | 2+2 | catch, try (Wasm+native E2E) |
| Defer | - | 3+3 | basic, loop_break, lifo (Wasm+native E2E) |
| Function ptrs | - | 3+3 | basic, param, reassign (Wasm+native E2E) |
| Closures | - | 4+4 | no_capture, capture, multi_capture, passed (Wasm+native E2E) |
| Global vars | - | 3 | read, write, multi-function (Wasm E2E) |
| Native baseline | - | 1+1 | baseline + phase3_all + func_call (native E2E) |

### Gap by Category

| Category | Bootstrap-0.2 | Current Cot | Gap |
|----------|--------------|-------------|-----|
| Expressions/Arithmetic | 160 | 10 + 6 bitwise | **~144 missing** |
| Functions | 115 | 16 | **~99 missing** |
| Control flow | 100 | 14 | **~86 missing** |
| Types | 65 | 2 + 2 enum + 4 union | **~57 missing** |
| Arrays | 60 | 6 | **~54 missing** |
| Memory | 53 | 5 | **~48 missing** |
| Variables | 47 | 0 (inline in others) | **~47 missing** |
| **Total** | **600 parity** | **114 files** | **~486 missing** |

**Note:** Current Cot has many features bootstrap-0.2 never had (closures, error unions, defer, ARC, etc.), so the test gap is purely about breadth of edge-case coverage, not missing functionality.

---

## Language Features Status

### Complete (working on both Wasm and native)

| Feature | Status | E2E Tests | Notes |
|---------|--------|-----------|-------|
| **Floats (f32, f64)** | ✅ COMPLETE | 1W+1N | Arithmetic, comparison, negation, native FPU |
| **Union payloads** | ✅ COMPLETE | 4W+4N | switch with payload capture |
| **Error unions (!T)** | ✅ COMPLETE | 2W+2N | `const E = error{...}`, `E!T`, `try`, `catch` |
| **Function pointers** | ✅ COMPLETE | 3W+3N | `let f = add; f(3,4)`, `fn apply(f: fn(...))` |
| **Closures** | ✅ COMPLETE | 4W+4N | Captures, higher-order functions, uniform repr |
| **Defer** | ✅ COMPLETE | 3W+3N | `defer expr`, `defer { block }`, unified cleanup stack |
| **ARC coverage** | ✅ COMPLETE | 4W+4N | call→+1, copy retain, reassignment, field assign |
| **Global variables** | ✅ Wasm only | 3W | read, write, multi-function. Native stubs exist |
| **Sized integers** | ✅ COMPLETE | - | i8-u64 in type system, @intCast works |
| **Slice syntax** | ✅ COMPLETE | - | `arr[start:end]`, decomposition passes (Go port) |
| **Methods** | ✅ COMPLETE | - | `impl` blocks, self parameter |
| **Enums** | ✅ COMPLETE | - | Simple + explicit values |
| **Tagged unions** | ✅ COMPLETE | - | With payloads and switch capture |
| **Switch** | ✅ COMPLETE | - | Integer, enum, union |
| **Type aliases** | ✅ COMPLETE | - | `type Alias = Original` |
| **Imports** | ✅ Wasm only | - | `import "file.cot"` with cycle detection |
| **Extern** | ✅ Wasm only | - | External function declarations |
| **Optional types** | ✅ COMPLETE | - | `?T`, `.?`, `??` |
| **Bitwise ops** | ✅ COMPLETE | - | `&`, `\|`, `^`, `~`, `<<`, `>>` |
| **Compound assign** | ✅ COMPLETE | - | All 8 operators |
| **Char literals** | ✅ COMPLETE | - | `'a'`, `'\n'` |
| **Builtins** | ✅ COMPLETE | - | `@sizeOf`, `@alignOf`, `@intCast` |
| **For-range loops** | ✅ COMPLETE | - | `for x in arr`, `for i in 0..n` |
| **ARC runtime** | ✅ COMPLETE | - | retain/release, destructors, heap |
| **String ops** | ✅ COMPLETE | - | concat, indexing, bounds checks |
| **Array append** | ✅ COMPLETE | - | Dynamic append builtin |

### Missing (blocking standard library)

| Feature | Description | Priority | Blocks |
|---------|-------------|----------|--------|
| **Generics** | `fn max(T)(a: T, b: T) T` | HIGH | Standard library, `List(T)`, `Map(K,V)` |
| **Dynamic lists** | `List(T)` with push/pop/get/set | HIGH | Real applications |
| **Maps/dictionaries** | `Map(K,V)` with set/get/has/delete | HIGH | Real applications |
| **String interpolation** | `"Hello, {name}"` | MEDIUM | Developer experience |
| **Traits/Interfaces** | Abstract type contracts | MEDIUM | Polymorphism |
| **Test runner** | `test "name" {}` blocks parsed, no runner | MEDIUM | Testing framework |
| **Globals on native** | Driver stubs native globals (`_ = globals`) | LOW | Full native parity |
| **Imports on native** | Work on Wasm only | LOW | Full native parity |

### Partially Implemented

| Feature | Status | What's Missing |
|---------|--------|----------------|
| **Bool type** | Works in conditions | Not a distinct runtime type |
| **Labeled break/continue** | Tokens parsed | Checker/lower not implemented |
| **Hex/binary/octal literals** | Scanner handles | Lower/codegen unverified |

---

## What Current Cot Has That Bootstrap-0.2 Never Had

| Feature | Description |
|---------|-------------|
| **Wasm-first architecture** | Universal IR, runs in browser natively |
| **Cranelift-style native AOT** | More robust than direct codegen |
| **ARC runtime** | retain/release, destructors, heap allocation |
| **Closures** | Captured variables, higher-order functions |
| **Error unions** | Zig-style `!T`, `try`, `catch` |
| **Defer** | Unified cleanup stack (Swift's CleanupManager) |
| **Function pointers** | First-class, indirect calls, reassignment |
| **Union payloads** | Payload capture in switch |
| **Float types** | f32/f64 on both Wasm and native |
| **For-range loops** | `for x in arr`, `for i in 0..n`, `for i, x in arr` |
| **File imports** | `import "other.cot"` with cycle detection |
| **Browser imports** | Wasm import section for JS interop |
| **String operations** | concat, indexing, bounds checking |
| **Array append** | Dynamic append builtin |
| **Switch expressions** | Value-producing switch |
| **Optional types** | `?T`, `.?`, `??` |
| **Compound assignment** | All 8 operators |
| **Slice syntax** | `arr[start:end]` with Go-style decomposition |
| **Global variables** | Top-level var/const (Wasm) |

---

## Recommended Priority Order

### Next: Generics + Collections

The single biggest unlock is **generics**. Once generics work, `List(T)` and `Map(K,V)` become possible, which enables the standard library.

| # | Feature | Effort | Why Now |
|---|---------|--------|---------|
| 1 | **Generics** | Large | Blocks everything: collections, std lib, real apps |
| 2 | **Dynamic lists** | Medium | Requires generics; was in bootstrap-0.2 |
| 3 | **Maps/dictionaries** | Medium | Requires generics; was in bootstrap-0.2 |
| 4 | **String interpolation** | Small | Developer experience |
| 5 | **Traits/Interfaces** | Medium | Polymorphism for std lib |
| 6 | **Test runner** | Small | Enable proper testing framework |

### Test Parity

Port bootstrap-0.2's 619 test cases to verify edge case coverage.

| # | Category | Tests to Port | Priority |
|---|----------|---------------|----------|
| 1 | Expressions | ~144 (precedence, edge cases, combinations) | HIGH |
| 2 | Functions | ~99 (many params, complex recursion, chaining) | HIGH |
| 3 | Control flow | ~86 (nested, complex conditions, edge cases) | HIGH |
| 4 | Arrays/Memory | ~102 (pointer arithmetic, heap, sort algorithms) | MEDIUM |
| 5 | Types | ~57 (sized ints, structs, booleans) | MEDIUM |
| 6 | Variables | ~47 (scope, mutability, constants) | LOW |

### Phase 5: Standard Library (After Generics)

| Module | Depends On | Description |
|--------|-----------|-------------|
| `std.core` | Generics | Primitives, math, string utils |
| `std.collections` | Generics | List, Map, Set, Queue |
| `std.fmt` | String interpolation | Formatting and printing |
| `std.fs` | Extern | File system (server only) |
| `std.net` | Extern | HTTP, WebSocket |
| `std.json` | Generics, string ops | JSON serialization |
| `std.dom` | Extern | Browser DOM API (client only) |

---

## Metrics

| Metric | Bootstrap-0.2 | Current Cot | Target |
|--------|--------------|-------------|--------|
| Test case files | 619 | 114 | 600+ |
| Total tests (incl. unit) | ~619 | 832 | 1000+ |
| Wasm E2E tests | 0 | 42 | 60+ |
| Native E2E tests | 0 | 24 | 40+ |
| Language features | ~25 | ~35 | 40+ |
| Sized int types | 10 (i8-u64) | 10 (i8-u64) | 10 |
| Collection types | 3 (array, list, map) | 1 (array + append) | 3+ |
| Float support | Yes | Yes | Yes |
| Closures | No | **Yes** | Yes |
| Function pointers | No | **Yes** | Yes |
| Error unions (!T) | No | **Yes** | Yes |
| Defer | No | **Yes** | Yes |
| Generics | No | No | Yes |
| Standard library | No | No | Yes |

---

## Bottom Line

**Current Cot has surpassed bootstrap-0.2 in both architecture and language features.** The Wasm-first pipeline with Cranelift-port native AOT is production-grade. The language now has closures, error unions, defer, function pointers, ARC, floats, and union payloads - none of which bootstrap-0.2 had.

**The remaining gaps are:**
1. **Generics** - The single biggest unlock, blocks standard library
2. **Collections** - `List(T)` and `Map(K,V)` (requires generics)
3. **Test breadth** - ~486 edge-case tests to port from bootstrap-0.2
4. **String interpolation** - Developer experience
5. **Native parity** - Globals, imports, extern on native AOT

The architecture is proven. The language is functional. The next phase is generics → standard library → ecosystem.
