# Phase 4 — Pointers and Strings Design

**Date:** 2026-04-04
**Status:** Design document. Read before implementing #031-040.

---

## Pointer Type Design

### Two pointer types (FIR/Zig/Rust pattern)

```
!cir.ptr         Opaque raw pointer (existing). Nullable, unsafe. C's `void*`.
!cir.ref<T>      Typed safe reference (new). Non-null, valid, known pointee type.
```

**Why two types:**
- `!cir.ref<T>` carries the pointee type → enables verification (load type matches ref type)
- `!cir.ref<T>` is non-null → eliminates null checks for safe languages
- `!cir.ptr` remains for C interop, malloc results, and unsafe code
- Both lower to `!llvm.ptr` (opaque) — zero runtime cost

**Reference:** FIR has `fir.ref<T>` (safe) vs `fir.ptr<T>` (Fortran POINTER). Zig has `*T` (non-null) vs `?*T` (nullable). Rust has `&T` (reference) vs `*T` (raw pointer).

**Frontend mapping:**
| Language | Safe | Unsafe |
|----------|------|--------|
| ac | `&x` → `!cir.ref<T>` | raw pointers (later) |
| Zig | `*T` → `!cir.ref<T>` | `@intFromPtr` → `!cir.ptr` |
| TypeScript | all refs → `!cir.ref<T>` | N/A |
| C (future) | N/A | all → `!cir.ptr` |

### What we DON'T add (yet)
- No lifetime annotations (`'a`) — add when borrow checker pass exists
- No ownership attributes (`@owned`) — add in Phase 8 with ARC
- No `!cir.heap<T>` — heap allocation is Phase 8
- No `?!cir.ref<T>` (nullable ref) — optionals are Phase 5

---

## New CIR Ops (#031-034)

### cir.ref — address-of (get reference to local)
```mlir
%r = cir.ref %alloca : !cir.ptr -> !cir.ref<i32>
```
- Takes an alloca result (raw pointer to stack)
- Returns a typed reference
- Pure, no memory effect (just type-wrapping the address)
- Lowering: identity (both are `!llvm.ptr`)

### cir.deref — dereference (load through reference)
```mlir
%v = cir.deref %r : !cir.ref<i32> to i32
```
- Takes a typed reference, returns the value
- Equivalent to `cir.load` but type-safe (result type matches ref pointee)
- Lowering: `llvm.load`

### cir.field_ptr (already exists)
```mlir
%fp = cir.field_ptr %struct_ptr, 0 {elem_type = !cir.struct<...>} : !cir.ptr to !cir.ptr
```
Already implemented in #026. Used for `&p.x`.

---

## String/Slice Design (#035-040)

### Slice type — fat pointer
```
!cir.slice<T>    →   !llvm.struct<(!llvm.ptr, i64)>
```

A slice is a `{pointer, length}` pair. This is universal:
- Zig: `[]T` = `{ptr: [*]T, len: usize}`
- Rust: `&[T]` = `{ptr: *const T, len: usize}`
- Go: `[]T` = `{ptr, len, cap}`
- Swift: `UnsafeBufferPointer` = `{start, count}`

CIR uses the Zig/Rust model (no capacity — that's a growable array, not a slice).

### String = slice of u8
```
string  →  !cir.slice<i8>
```
No separate string type. A string is just a byte slice. This matches Zig (`[]const u8`), Rust (`&str` = `&[u8]`), and Go (`string` = readonly `[]byte`).

### String literal — global constant
```mlir
// "hello" → global constant + slice construction
llvm.mlir.global constant @str0("hello\00")
%ptr = llvm.mlir.addressof @str0
%len = llvm.mlir.constant(5 : i64)
%s = cir.slice_init %ptr, %len : !cir.slice<i8>
```

### New ops for slices
```
cir.slice_init %ptr, %len         → construct slice from pointer + length
cir.slice_ptr %s                  → extract pointer field
cir.slice_len %s                  → extract length field
cir.slice_elem %s, %i             → GEP on pointer + load (bounds-unchecked)
cir.array_to_slice %arr_ptr, %lo, %hi → build slice from array sub-range
```

All lower to struct field access + GEP. No magic.

---

## Implementation Order

1. **#031 `!cir.ref<T>` type + pointer syntax** — add RefType to CIRTypes.td, update frontends
2. **#032 `cir.ref` op (address-of)** — `&x` in all 3 frontends
3. **#033 `cir.deref` op** — `*p` / `p.*` in all 3 frontends
4. **#034 Pointer to struct field** — `&p.x` using existing `cir.field_ptr`
5. **#035-036 String type + literal** — `!cir.slice<i8>`, global constants, `"hello"`
6. **#037-040 Slice ops** — slice_init, slice_ptr, slice_len, slice_elem, array_to_slice

Features #031-034 are pointer fundamentals. Features #035-040 build on them with fat pointers.

---

## What This Enables (Future Phases)

- **Borrow checker pass** (opt-in CIR→CIR): validate `!cir.ref<T>` lifetimes don't escape their alloca scope
- **Null safety pass**: verify `!cir.ref<T>` is never null (guaranteed by construction)
- **ARC (Phase 8)**: `!cir.ref<T>` becomes the tracked reference type for retain/release insertion
- **Strings in Phase 11**: `print("hello")` just passes a `!cir.slice<i8>` to an extern write

---

## Rules
- `!cir.ref<T>` lowers to `!llvm.ptr` (same as `!cir.ptr`) — zero runtime cost
- Frontends emit `!cir.ref<T>` for safe code, `!cir.ptr` for unsafe/C interop
- All ref ops have verifiers that check pointee type consistency
- Slices are structs at the LLVM level — no special runtime support
