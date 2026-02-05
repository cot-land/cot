# Gap Analysis: Current Cot vs Bootstrap-0.2

## Executive Summary

**Bootstrap-0.2** was a working compiler with **619 test cases** covering expressions, control flow, functions, types, arrays, memory, and variables. It compiled to native (AMD64/ARM64) directly.

**Current Cot** is a Wasm-first rewrite with **107 test case files** and **793 total tests** (including unit tests). It has a more robust architecture (Wasm → CLIF → native AOT) but has **not yet reached feature parity** with bootstrap-0.2.

**The gap: ~512 missing test cases and several missing language features.**

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

### Current Cot: 107 test files

| Category | Count | What It Covers |
|----------|-------|----------------|
| Functions | 16 | Basic calls, params, recursion, fibonacci, chaining |
| Control flow | 14 | if/else, while, break, continue, comparisons |
| Arithmetic | 10 | add, sub, mul, div, mod, precedence, negation |
| Strings | 9 | Length, concat, indexing |
| Compound assign | 8 | +=, -=, *=, /=, %=, &=, \|=, ^= |
| ARC | 7 | new, retain, release, destructor, ownership |
| Arrays | 6 | Literal, sum, index, update, append |
| Bitwise | 6 | AND, OR, XOR, NOT, shifts |
| Memory | 5 | Locals, reassign, swap, accumulator |
| Structs | 5 | Simple, field access, field update, nested, pass to fn |
| Builtins | 4 | @sizeOf, @alignOf, @intCast |
| Optional | 3 | Basic, coalesce, null coalesce |
| Loops | 3 | for-range sum, index, index+value |
| Chars | 2 | Simple, escape sequences |
| Enum | 2 | Simple, explicit values |
| Switch | 2 | Integer, enum |
| Types | 2 | Type alias, struct alias |
| Methods | 1 | Simple method call |
| Union | 1 | Simple tagged union |
| Extern | 1 | Extern function declaration |

### Gap by Category

| Category | Bootstrap-0.2 | Current Cot | Gap |
|----------|--------------|-------------|-----|
| Expressions/Arithmetic | 160 | 10 + 6 bitwise | **~144 missing** |
| Functions | 115 | 16 | **~99 missing** |
| Control flow | 100 | 14 | **~86 missing** |
| Types | 65 | 2 + 2 enum + 1 union | **~60 missing** |
| Arrays | 60 | 6 | **~54 missing** |
| Memory | 53 | 5 | **~48 missing** |
| Variables | 47 | 0 (inline in others) | **~47 missing** |
| **Total** | **600 parity** | **107** | **~493 missing** |

---

## Missing Language Features

### Tier 1: Features in Bootstrap-0.2 IR But Missing in Current Cot

These were working in bootstrap-0.2 and need to be ported.

| Feature | Bootstrap-0.2 IR Nodes | Current Status | Priority |
|---------|----------------------|----------------|----------|
| **Dynamic lists** | list_new, list_push, list_get, list_set, list_len, list_free | Array literals + append exist, no dynamic list type | HIGH |
| **Maps/dictionaries** | map_new, map_set, map_get, map_has, map_free | Not started | HIGH |
| **Union payloads** | union_init, union_tag, union_payload | Simple tags only, no associated values | HIGH |
| **Float types** | const_float, f32, f64 operations | Tokens exist, not lowered to Wasm | MEDIUM |
| **Function pointers** | func_addr, call_indirect | Not in current pipeline | MEDIUM |
| **Global variables** | global_ref, global_store, addr_global | Only locals supported | MEDIUM |
| **Slice operations** | slice_local, slice_value, slice_ptr, slice_len | rewritedec exists, no `arr[start:end]` syntax | MEDIUM |
| **Full pointer ops** | ptr_field, ptr_field_store, ptr_load_value, ptr_store_value | Partial (off_ptr for structs) | LOW |
| **Address arithmetic** | addr_offset, addr_index | Partial (off_ptr, add_ptr) | LOW |

### Tier 2: Features Planned in VISION.md/DESIGN.md But Not Started

| Feature | Description | Blocks |
|---------|-------------|--------|
| **Closures** | Nested functions with captured variables | Standard library, callbacks |
| **Generics** | `fn max<T>(a: T, b: T) T` | Standard library, collections |
| **Traits/Interfaces** | Abstract type contracts | Polymorphism, std lib |
| **Defer** | `defer cleanup()` - execute at scope exit | Resource management |
| **String interpolation** | `"Hello, {name}"` | Developer experience |
| **Error handling** | Zig-style error unions (`!T`), `try`, `catch \|err\|` (no throw) | Robust applications |
| **Pattern matching** | Full match on union payloads | Idiomatic union handling |

### Tier 3: Features Partially Implemented

| Feature | Status | What's Missing |
|---------|--------|----------------|
| **Sized integers** | i32 partially works via @intCast | i8, i16, u8, u16, u32, u64 codegen |
| **Bool type** | Works in conditions | Not a distinct runtime type |
| **Test blocks** | Parser handles `test "name" {}` | No test runner, no test discovery |
| **Labeled break/continue** | Tokens parsed | Checker/lower not implemented |
| **Hex/binary/octal literals** | Scanner handles | Lower/codegen unverified |
| **Imports on native** | Work on Wasm | Not on native AOT target |
| **Extern on native** | Work on Wasm | Not on native AOT target |

---

## What Current Cot Has That Bootstrap-0.2 Didn't

| Feature | Description |
|---------|-------------|
| **Wasm-first architecture** | Universal IR, runs in browser natively |
| **Cranelift-style native AOT** | More robust than direct codegen |
| **ARC runtime** | retain/release, destructors, heap allocation |
| **For-range loops** | `for x in arr`, `for i in 0..n`, `for i, x in arr` |
| **File imports** | `import "other.cot"` with cycle detection |
| **Browser imports** | Wasm import section for JS interop |
| **String operations** | concat, indexing, bounds checking |
| **Array append** | Dynamic append builtin |
| **Switch expressions** | Value-producing switch |
| **Optional types** | `?T`, `.?`, `??` |
| **Compound assignment** | All 8 operators |

---

## Recommended Priority Order

### Phase 3A: Feature Parity (Language Completeness)

Complete the language features needed before standard library work can begin.

| # | Feature | Effort | Why Now |
|---|---------|--------|---------|
| 1 | **Float types (f32, f64)** | Medium | Many algorithms need floats; blocks math stdlib |
| 2 | **Union payloads** | Medium | Needed for error unions, pattern matching |
| 3 | **Closures** | Large | Needed for callbacks, iterators, event handlers |
| 4 | **Function pointers / indirect calls** | Medium | Needed for callbacks, method tables |
| 5 | **Defer** | Small | Needed for resource cleanup patterns |
| 6 | **Error unions (Zig-style `!T`)** | Medium | Needed for any real application |
| 7 | **String interpolation** | Small | Developer experience |
| 8 | **Generics** | Large | Needed for collections, standard library |

### Phase 3B: Test Parity (Robustness)

Port bootstrap-0.2's 619 test cases to verify the current compiler handles edge cases.

| # | Category | Tests to Port | Priority |
|---|----------|---------------|----------|
| 1 | Expressions | ~144 (precedence, edge cases, combinations) | HIGH |
| 2 | Functions | ~99 (many params, complex recursion, chaining) | HIGH |
| 3 | Control flow | ~86 (nested, complex conditions, edge cases) | HIGH |
| 4 | Arrays/Memory | ~102 (pointer arithmetic, heap, sort algorithms) | MEDIUM |
| 5 | Types | ~60 (sized ints, structs, booleans) | MEDIUM |
| 6 | Variables | ~47 (scope, mutability, constants) | LOW |

### Phase 5: Standard Library (After Phase 3 Complete)

| Module | Depends On | Description |
|--------|-----------|-------------|
| `std.core` | Generics, closures | Primitives, math, string utils, array utils |
| `std.collections` | Generics, closures | List, Map, Set, Queue |
| `std.errors` | Error unions, generics | Zig-style error sets and error unions |
| `std.fmt` | String interpolation | Formatting and printing |
| `std.fs` | Extern, closures | File system (server only) |
| `std.net` | Extern, closures | HTTP, WebSocket |
| `std.json` | Generics, string ops | JSON serialization |
| `std.dom` | Extern | Browser DOM API (client only) |

---

## Metrics

| Metric | Bootstrap-0.2 | Current Cot | Target |
|--------|--------------|-------------|--------|
| Test case files | 619 | 107 | 600+ |
| IR operations | 60 | ~45 | 65+ |
| Language features | ~25 | ~20 | 30+ |
| Sized int types | 10 (i8-u64) | 2 (i32, i64) | 10 |
| Collection types | 3 (array, list, map) | 1 (array) | 3+ |
| Float support | Yes | No | Yes |
| Closures | No | No | Yes |
| Generics | No | No | Yes |
| Error unions (!T) | No | No | Yes |
| Standard library | No | No | Yes |

---

## Bottom Line

**Current Cot has a better architecture** (Wasm-first, Cranelift AOT, ARC) **but fewer features** than bootstrap-0.2. The priority is:

1. **Finish Phase 3A** - Complete the language (floats, closures, generics, error unions)
2. **Port Phase 3B tests** - Reach 600+ test cases for robustness
3. **Build Phase 5** - Standard library that proves the language works for real apps
4. **Ship Phase 6** - cot.land package manager, LSP, tooling

The architecture is solid. The gap is in language features and test coverage.
