# CIR Construct Master List — v1.0 Target

**Date:** 2026-04-05
**Purpose:** Definitive list of language constructs CIR must support for 1:1 Zig + TypeScript compatibility.
**Status:** Living document. Updated as constructs are implemented.

---

## Summary

| Category | Zig Constructs | TS Constructs | CIR Ops Needed | Implemented | % |
|----------|---------------|---------------|----------------|-------------|---|
| Arithmetic & Math | 12 | 8 | 7 | 7 | 100% |
| Comparison | 6 | 8 | 1 (cmp) | 1 | 100% |
| Bitwise | 6 | 7 | 6 | 6 | 100% |
| Constants & Literals | 5 | 8 | 4 | 4 | 100% |
| Variables & Assignment | 4 | 6 | 3 | 3 | 100% |
| Control Flow (if/while/for) | 6 | 8 | 4 | 4 | 100% |
| Functions & Calls | 4 | 4 | 2 (func+call) | 2 | 100% |
| Structs / Interfaces | 4 | 3 | 4 | 4 | 100% |
| Arrays | 3 | 2 | 3 | 3 | 100% |
| Pointers & References | 3 | 0 | 4 | 4 | 100% |
| Strings & Slices | 4 | 2 | 5 | 5 | 100% |
| Optionals | 4 | 2 | 4 | 4 | 100% |
| Error Unions (Zig/Rust) | 5 | 0 | 5 | 5 | 100% |
| Exceptions (TS/C++) | 0 | 3 | 3 | 3 | 100% |
| Enums | 3 | 3 | 2 | 2 | 100% |
| Switch / Match | 3 | 4 | 1 | 0 | 0% |
| Tagged Unions | 3 | 2 | 3 | 0 | 0% |
| Type Casts | 7 | 3 | 7 | 7 | 100% |
| Generics / Comptime | 6 | 8 | TBD | 0 | 0% |
| Traits / Interfaces (dynamic) | 0 | 4 | TBD | 0 | 0% |
| Classes | 0 | 12 | TBD | 0 | 0% |
| ARC / Memory Management | 0 | 0 | TBD (ac-only) | 0 | 0% |
| Async / Await | 4 | 3 | TBD | 0 | 0% |
| Defer / Cleanup | 2 | 0 | TBD | 0 | 0% |
| Modules / Imports | 2 | 8 | TBD | 0 | 0% |
| Extern / FFI | 2 | 0 | TBD | 0 | 0% |
| **TOTAL** | **~96** | **~108** | **~90+** | **55** | **~61%** |

---

## Detailed Construct Map

### Tier 1 — Core (DONE)

These are implemented. All 3 frontends + lowering + tests.

| # | Construct | CIR Op(s) | Zig | TS | ac | Status |
|---|-----------|-----------|-----|----|----|--------|
| 1 | Integer constant | `cir.constant` | ✓ | ✓ | ✓ | ✓ |
| 2 | Float constant | `cir.constant` (float) | ✓ | ✓ | ✓ | ✓ |
| 3 | Bool constant | `cir.constant` (i1) | ✓ | ✓ | ✓ | ✓ |
| 4 | String literal | `cir.string_constant` | ✓ | ✓ | ✓ | ✓ |
| 5 | Add/Sub/Mul | `cir.add/sub/mul` | ✓ | ✓ | ✓ | ✓ |
| 6 | Div/Rem | `cir.div/rem` | ✓ | ✓ | ✓ | ✓ |
| 7 | Negation | `cir.neg` | ✓ | ✓ | ✓ | ✓ |
| 8 | Comparison | `cir.cmp` (6 predicates) | ✓ | ✓ | ✓ | ✓ |
| 9 | Bitwise AND/OR/XOR/NOT | `cir.bit_and/or/xor/not` | ✓ | ✓ | ✓ | ✓ |
| 10 | Shift left/right | `cir.shl/shr` | ✓ | ✓ | ✓ | ✓ |
| 11 | Select (ternary) | `cir.select` | ✓ | ✓ | ✓ | ✓ |
| 12 | Let/const binding | `cir.alloca + store` | ✓ | ✓ | ✓ | ✓ |
| 13 | Var/mutable binding | `cir.alloca + store + load` | ✓ | ✓ | ✓ | ✓ |
| 14 | Assignment | `cir.store` | ✓ | ✓ | ✓ | ✓ |
| 15 | If/else statement | `cir.condbr + br` | ✓ | ✓ | ✓ | ✓ |
| 16 | While loop | `cir.condbr + br` (loop) | ✓ | ✓ | ✓ | ✓ |
| 17 | For loop | desugared to while | ✓ | ✓ | ✓ | ✓ |
| 18 | Break/Continue | `cir.br` to exit/header | ✓ | N/A | ✓ | ✓ |
| 19 | Function declaration | `func.func` | ✓ | ✓ | ✓ | ✓ |
| 20 | Function call | `func.call` | ✓ | ✓ | ✓ | ✓ |
| 21 | Return | `func.return` | ✓ | ✓ | ✓ | ✓ |
| 22 | Struct declaration | `!cir.struct` | ✓ | ✓ (interface) | ✓ | ✓ |
| 23 | Struct construction | `cir.struct_init` | ✓ | ✓ | ✓ | ✓ |
| 24 | Field access | `cir.field_val` | ✓ | ✓ | ✓ | ✓ |
| 25 | Field pointer | `cir.field_ptr` | ✓ | — | ✓ | ✓ |
| 26 | Method call | desugar to call | ✓ | ✓ | ✓ | ✓ |
| 27 | Array type + literal | `!cir.array + cir.array_init` | ✓ | ✓ | ✓ | ✓ |
| 28 | Array indexing | `cir.elem_val/elem_ptr` | ✓ | ✓ | ✓ | ✓ |
| 29 | Pointer/Ref type | `!cir.ref<T> + !cir.ptr` | ✓ | — | ✓ | ✓ |
| 30 | Address-of | `cir.addr_of` | ✓ | — | ✓ | ✓ |
| 31 | Dereference | `cir.deref` | ✓ | — | ✓ | ✓ |
| 32 | Auto-deref | desugar (deref + field) | ✓ | — | ✓ | ✓ |
| 33 | Slice type | `!cir.slice<T>` | ✓ | — | ✓ | ✓ |
| 34 | Slice len/ptr/elem | `cir.slice_len/ptr/elem` | ✓ | ✓ | ✓ | ✓ |
| 35 | Array to slice | `cir.array_to_slice` | — | — | ✓ | ✓ |
| 36 | Type casts (7 ops) | `cir.extsi/extui/trunci/sitofp/fptosi/extf/truncf` | ✓ | ✓ | ✓ | ✓ |
| 37 | Optional type | `!cir.optional<T>` | ✓ | — | ✓ | ✓ |
| 38 | Optional wrap/none | `cir.wrap_optional/none` | ✓ | — | ✓ | ✓ |
| 39 | If-unwrap | `cir.is_non_null + optional_payload` | ✓ | — | ✓ | ✓ |
| 40 | Error union type | `!cir.error_union<T>` | ✓ | — | ✓ | ✓ |
| 41 | Error wrap/unwrap | `cir.wrap_result/error/is_error/error_payload/code` | ✓ | — | ✓ | ✓ |
| 42 | Try/catch (error union) | desugar to is_error + condbr | ✓ | — | ✓ | ✓ |
| 43 | Throw (exception) | `cir.throw` | — | ✓ | ✓ | ✓ |
| 44 | Invoke (exception call) | `cir.invoke` | — | ✓ | ✓ | ✓ |
| 45 | Landing pad (catch) | `cir.landingpad` | — | ✓ | ✓ | ✓ |
| 46 | Enum type | `!cir.enum<...>` | ✓ | ✓ | ✓ | ✓ |
| 47 | Enum constant/value | `cir.enum_constant/enum_value` | ✓ | ✓ | ✓ | ✓ |
| 48 | Assert / trap | `cir.trap` | ✓ | — | ✓ | ✓ |

### Tier 2 — In Progress (Phase 6)

| # | Construct | CIR Op(s) | Zig | TS | ac | Status |
|---|-----------|-----------|-----|----|----|--------|
| 49 | Switch/match stmt | `cir.switch` | ✓ | ✓ | ✓ | — |
| 50 | Switch/match expr | `cir.switch` + phi | ✓ | — | ✓ | — |
| 51 | Tagged union type | `!cir.tagged_union<...>` | ✓ | ✓ (discrim) | ✓ | — |
| 52 | Union construction | `cir.union_init` | ✓ | — | ✓ | — |
| 53 | Union tag extract | `cir.union_tag` | ✓ | — | ✓ | — |
| 54 | Union payload extract | `cir.union_payload` | ✓ | — | ✓ | — |

### Tier 3 — Generics & Polymorphism (Phase 7)

| # | Construct | CIR Op(s) | Zig | TS | ac | Status |
|---|-----------|-----------|-----|----|----|--------|
| 55 | Generic function | monomorphize | ✓ (comptime) | ✓ (<T>) | ✓ | — |
| 56 | Generic struct | monomorphize | ✓ (comptime) | ✓ (<T>) | ✓ | — |
| 57 | Comptime block | `cir.comptime_block` | ✓ | — | ✓ | — |
| 58 | Comptime params | `cir.param_comptime` | ✓ | — | ✓ | — |
| 59 | Type reflection | `cir.type_info` | ✓ (@typeInfo) | — | ✓ | — |
| 60 | Inline for | `cir.inline_for` | ✓ | — | ✓ | — |
| 61 | Trait declaration | TBD | — | ✓ (interface) | ✓ | — |
| 62 | Trait implementation | TBD | — | ✓ (implements) | ✓ | — |
| 63 | Trait bounds | TBD | — | ✓ (extends) | ✓ | — |
| 64 | Trait objects (dynamic) | TBD | — | ��� | ✓ | — |

### Tier 4 — Classes (TS-specific, Phase 7b)

| # | Construct | CIR Op(s) | Zig | TS | ac | Status |
|---|-----------|-----------|-----|----|----|--------|
| 65 | Class declaration | TBD | — | ✓ | ✓ | — |
| 66 | Constructor | TBD | — | ✓ | ✓ | — |
| 67 | Class methods | TBD | — | ✓ | ✓ | — |
| 68 | Class properties | TBD | — | ✓ | ✓ | — |
| 69 | Getter/Setter | TBD | — | ✓ | ✓ | — |
| 70 | Static members | TBD | — | ✓ | ✓ | — |
| 71 | Inheritance (extends) | TBD | — | ✓ | ✓ | — |
| 72 | Visibility (public/private) | TBD | — | ✓ | ✓ | — |

### Tier 5 — Memory Management (Phase 8, ac-primary)

| # | Construct | CIR Op(s) | Zig | TS | ac | Status |
|---|-----------|-----------|-----|----|----|--------|
| 73 | Heap allocation | `cir_arc.alloc` | ✓ (allocator) | ✓ (new) | ✓ | — |
| 74 | ARC retain/release | `cir_arc.retain/release` | — | — | ✓ | — |
| 75 | ARC optimization | (pass) | — | — | ✓ | — |
| 76 | Weak references | `cir_arc.weak_*` | — | — | ✓ | — |
| 77 | Move semantics | `cir_arc.move` | ✓ | — | ✓ | — |

### Tier 6 — Async / Concurrency (Phase 9)

| # | Construct | CIR Op(s) | Zig | TS | ac | Status |
|---|-----------|-----------|-----|----|----|--------|
| 78 | Async function | `cir_conc.async_frame` | ✓ | ✓ | ✓ | — |
| 79 | Await expression | `cir_conc.suspend/resume` | ✓ | ✓ | ✓ | — |
| 80 | Task spawn | `cir_conc.task_spawn` | — | — | ✓ | — |

### Tier 7 — Standard Library & I/O (Phase 10-11)

| # | Construct | CIR Op(s) | Zig | TS | ac | Status |
|---|-----------|-----------|-----|----|----|--------|
| 81 | Extern function | `cir.extern` | ✓ | — | ✓ | — |
| 82 | Import module | `cir.import` | ✓ | ✓ | ✓ | — |
| 83 | Defer statement | `cir.defer` | ✓ | — | ✓ | — |
| 84 | Errdefer | `cir.errdefer` | ✓ | — | ✓ | — |
| 85 | Multiple returns | struct return | ✓ | — | ✓ | — |
| 86 | Unreachable | `cir.unreachable` | ✓ | — | ✓ | — |
| 87 | For-each (iterator) | desugar | ✓ | ✓ (for-of) | ✓ | — |
| 88 | Destructuring | desugar | — | ✓ | — | — |
| 89 | Spread operator | TBD | — | ✓ | — | — |
| 90 | Template literals | TBD | — | ✓ | — | — |

---

## CIR Op Count by Status

| Status | Count |
|--------|-------|
| Implemented (working in all applicable frontends) | 55 |
| In progress (Phase 6 — switch, unions) | 4 |
| Planned (Phases 7-11) | ~35 |
| **Total CIR ops at v1.0** | **~90-100** |

## Custom Types by Status

| Status | Count |
|--------|-------|
| Implemented | 8 (!cir.ptr, ref, struct, array, slice, optional, error_union, enum) |
| Phase 6 | 1 (!cir.tagged_union) |
| Phase 7+ | ~5 (trait, class, async_frame, channel, actor) |
| **Total at v1.0** | **~14** |

---

## Notes

- **Zig has ~660 IR constructs** across AST/ZIR/AIR. Many are variants (safe/unsafe/optimized).
  CIR maps ~96 semantic constructs, each covering multiple Zig variants.
- **TypeScript has ~391 AST kinds.** Many are tokens/keywords. ~250 are semantic constructs.
  CIR maps ~108 of those that involve code generation.
- **JSX, decorators, JSDoc** are TypeScript-specific and deferred past v1.0.
- **Comptime** is Zig-specific. CIR provides ops but they're Zig/ac-only.
- **ARC** is ac-specific. Neither Zig nor TypeScript use it.
- **Classes** are TypeScript-specific. Zig has no classes.
