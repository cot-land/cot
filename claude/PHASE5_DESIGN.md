# Phase 5 — Optionals and Error Handling Design

**Date:** 2026-04-04
**Status:** Design document. Read before implementing #041-048.

---

## Reference Study

Three reference compilers handle optionals/errors differently. CIR ports the **Zig
pattern** (tagged union) for semantics, with the **Rust niche optimization** available
as a future lowering pass.

### Zig — Primary Reference

**Source:** `~/claude/references/zig/src/Sema.zig`, `InternPool.zig`, `Zir.zig`

Zig represents `?T` and `E!T` as first-class types in the IR:

**Optional (`?T`) layout:**
- Pointer-like (`?*T`, `?[*]T`): null-pointer optimization — single pointer, null = none
- Non-pointer (`?i32`): `{payload: T, tag: u1}` — tag after payload, aligned

**Error union (`E!T`) layout:**
- `{error_code: u16, payload: T}` — ordered by alignment
- Error code 0 = no error (success), nonzero = error value

**ZIR instructions (frontend-emitted):**
```
optional_type           construct ?T type
is_non_null             test optional != null → i1
is_non_null_ptr         test *?T != null → i1
optional_payload_safe   unwrap ?T → T (with safety check)
optional_payload_unsafe unwrap ?T → T (no check, post-branch)
error_union_type        construct E!T type
is_non_err              test E!T is success → i1
is_non_err_ptr          test *E!T is success → i1
err_union_code          extract error code from E!T
err_union_payload_unsafe extract payload from E!T (no check)
```

**Control flow pattern (if-unwrap):**
```
%is_some = is_non_null %opt
condbr %is_some, ^then, ^else
^then:
  %val = optional_payload_unsafe %opt   // safe because we branched
  ...
^else:
  ...
```

### Rust — Layout Reference

**Source:** `~/claude/references/rust/compiler/rustc_middle/src/ty/layout.rs` (lines 1070-1103)

Rust's `Option<T>` and `Result<T,E>` are plain enums. The key insight is **niche
optimization**: `Option<&T>` uses zero bytes overhead because null is a niche value.

**MIR instructions:**
```
SetDiscriminant { place, variant_index }     set enum tag
Aggregate(Adt, variant, [fields])            construct enum variant
Downcast(place, variant_index)               project to variant
SwitchInt { discr, targets }                 branch on discriminant
```

**Niche encoding:** `TagEncoding::Niche { untagged_variant, niche_start }` — the
discriminant is stored in spare bits of the payload (e.g., null pointer for None).

### Swift — SIL Reference

**Source:** `~/claude/references/swift/include/swift/SIL/SILInstruction.h` (lines 7120-7399)

Swift's `Optional<T>` is an enum with special SIL instructions:

**SIL instructions:**
```
inject_enum_addr %addr, #case              tag an enum in memory
init_enum_data_addr %addr, #case           get address of payload
unchecked_enum_data %val, #case            extract payload (no check)
unchecked_take_enum_data_addr %addr, #case extract payload addr
switch_enum %val, case #a: bb1, ...        branch on variant
select_enum %val, case #a: %v1, ...        select value by variant
```

---

## CIR Design Decisions

### Decision 1: Optional type — `!cir.optional<T>`

New CIR type parameterized by the payload type. Not a generic enum — optionals are
so fundamental they deserve first-class IR support (matches Zig, Swift patterns).

```
!cir.optional<i32>         →  !llvm.struct<(i32, i1)>     // {payload, tag}
!cir.optional<!cir.ptr>    →  !llvm.ptr                    // null-pointer optimization
!cir.optional<!cir.ref<T>> →  !llvm.ptr                    // null-pointer optimization
```

**Null-pointer optimization:** When the payload is a pointer type (`!cir.ptr` or
`!cir.ref<T>`), the optional uses null as the none representation — no tag byte.
This is a type converter decision, transparent to CIR ops.

**Reference:** Zig `?*T` uses null-pointer optimization. Rust `Option<&T>` uses niche
encoding. Both produce the same LLVM IR.

### Decision 2: Error union type — `!cir.error_union<T>` (Phase 5b, later)

Error unions are more complex (error set types, propagation). Start with optionals
only (#041-044), then add error unions (#045-048) in a second pass within Phase 5.

### Decision 3: CIR ops for optionals

Port the Zig ZIR instruction set directly:

```
cir.none                    create null optional value
cir.wrap_optional %val      wrap T → ?T (set tag = 1)
cir.is_non_null %opt        test ?T != null → i1
cir.optional_payload %opt   extract T from ?T (unchecked, post-branch)
```

**Why these specific ops:**
- `cir.none` — Zig `null`. Creates the null value for an optional type.
- `cir.wrap_optional` — Zig implicit `T → ?T` coercion. Wraps a value in Some.
- `cir.is_non_null` — Zig `is_non_null`. The branch condition for if-unwrap.
- `cir.optional_payload` — Zig `optional_payload_unsafe`. Extracts the value after
  a branch has established it's non-null. Unchecked (safety pass can add checks later).

**Why NOT a generic `switch_enum`:** Optionals have exactly 2 variants (some/none).
A dedicated `is_non_null` + branch is simpler and maps 1:1 to LLVM `icmp` + `br`.
Generic enum switch comes in Phase 6.

### Decision 4: Lowering strategy

**Non-pointer optionals (`?i32`, `?f64`, `?StructType`):**
```
!cir.optional<i32> → !llvm.struct<(i32, i1)>

cir.none            → undef + insertvalue(0, i1 0)
cir.wrap_optional   → undef + insertvalue(val, 0) + insertvalue(i1 1, 1)
cir.is_non_null     → extractvalue [1] → i1 tag
cir.optional_payload → extractvalue [0] → payload
```

**Pointer optionals (`?*T`, `?cir.ptr`):**
```
!cir.optional<!cir.ptr> → !llvm.ptr

cir.none            → llvm.mlir.zero(ptr)  // null pointer
cir.wrap_optional   → identity (ptr is already the value)
cir.is_non_null     → icmp ne ptr, null
cir.optional_payload → identity (ptr is the payload)
```

The type converter decides which lowering to use based on the payload type.

---

## Frontend Syntax

### ac (Agentic Cot)

```
// Optional type
let x: ?i32 = null
let y: ?i32 = 42           // implicit wrap

// Unwrap
if x |val| {               // Zig-style if-unwrap
    use(val)
}

let v: i32 = x orelse 0    // unwrap with default
let v: i32 = x!            // force unwrap (traps on null)
```

### Zig

```zig
const x: ?i32 = null;
const y: ?i32 = 42;

if (x) |val| {
    use(val);
}

const v: i32 = x orelse 0;
const v: i32 = x.?;        // force unwrap
```

### TypeScript

```typescript
const x: number | null = null;
const y: number | null = 42;

if (x !== null) {
    use(x);                 // TS narrowing
}

const v: number = x ?? 0;  // nullish coalescing
```

---

## New CIR Ops (#041-044)

### `!cir.optional<T>` — type (CIRTypes.td)

```mlir
!cir.optional<i32>
!cir.optional<!cir.ptr>
!cir.optional<!cir.struct<"Point", x: i32, y: i32>>
```

### `cir.none` — null optional constant

```mlir
%n = cir.none : !cir.optional<i32>
```

Produces the null/none value for the given optional type.

### `cir.wrap_optional` — wrap value in optional

```mlir
%opt = cir.wrap_optional %val : i32 to !cir.optional<i32>
```

Wraps a non-optional value into an optional (the "Some" case).

### `cir.is_non_null` — test optional for non-null

```mlir
%b = cir.is_non_null %opt : !cir.optional<i32> to i1
```

Returns i1: true if the optional contains a value, false if null.

### `cir.optional_payload` — extract value from optional (unchecked)

```mlir
%val = cir.optional_payload %opt : !cir.optional<i32> to i32
```

Extracts the payload. **Unchecked** — caller must have already branched on
`cir.is_non_null`. Safety passes can insert checks before this op.

---

## Implementation Order

1. **#041** `!cir.optional<T>` type in CIRTypes.td + type converter + C API
2. **#042** `cir.none` + `cir.wrap_optional` ops + lowering + all 3 frontends
3. **#043** `cir.is_non_null` op + lowering + all 3 frontends
4. **#044** `cir.optional_payload` op + if-unwrap syntax + all 3 frontends

Each step: op → lowering → 3 frontends → C API → lit tests → inline test → docs.

---

## Reference Code to Port

### For CIR type + type converter

| What | Port from | Source |
|------|-----------|--------|
| OptionalType definition | FIR BoxType pattern | `~/claude/references/flang-ref/flang/include/flang/Optimizer/Dialect/FIRTypes.td` |
| Type converter (non-ptr) | Zig layout rules | `~/claude/references/zig/src/InternPool.zig` (abiSize for optionals) |
| Type converter (ptr-opt) | Rust niche encoding | `~/claude/references/rust/compiler/rustc_middle/src/ty/layout.rs:1070` |

### For CIR ops + lowering

| What | Port from | Source |
|------|-----------|--------|
| `cir.none` lowering | Zig null value handling | `~/claude/references/zig/src/Value.zig` (optional none) |
| `cir.wrap_optional` lowering | Zig optional wrap in Sema | `~/claude/references/zig/src/Sema.zig` (search `optionalType`) |
| `cir.is_non_null` lowering | Zig `is_non_null` AIR | `~/claude/references/zig/src/Sema.zig` (search `is_non_null`) |
| `cir.optional_payload` lowering | Zig `optional_payload_unsafe` | `~/claude/references/zig/src/Sema.zig` (search `optional_payload`) |
| Struct-based lowering pattern | LLVM insertvalue/extractvalue | Same pattern as `!cir.slice<T>` lowering |
| Null-pointer lowering | LLVM icmp ne null | Same pattern as `cir.is_non_null` in Zig codegen |

### For frontend syntax

| What | Port from | Source |
|------|-----------|--------|
| ac `?T` type syntax | Zig `?T` parser | `~/claude/references/zig/lib/std/zig/Parse.zig` (search `optional`) |
| ac `if x \|val\|` | Zig if-unwrap | `~/claude/references/zig/lib/std/zig/AstGen.zig` (search `if_simple`) |
| ac `orelse` | Zig orelse | `~/claude/references/zig/lib/std/zig/AstGen.zig` (search `orelse`) |
| Zig frontend | Direct AST mapping | Same Zig nodes — `?T` already parsed by std.zig.Ast |
| TS frontend | `\| null` type union | `~/claude/references/typescript-go/internal/ast/` (UnionType) |

---

## What This Enables

With optionals complete, CIR can express:
- Nullable pointers (`?*T` — zero-cost at LLVM level)
- Nullable values (`?i32` — tagged union, 1 byte overhead)
- Safe null handling (if-unwrap pattern — no null dereference bugs)
- Foundation for error unions (Phase 5b): `E!T` is `?T` plus an error code

---

## Rules

- `!cir.optional<T>` lowers to `!llvm.struct<(T, i1)>` for non-pointer T
- `!cir.optional<!cir.ptr>` lowers to `!llvm.ptr` (null = none) — zero cost
- All optional ops have verifiers that check input/output types
- `cir.optional_payload` is unchecked — safety is a separate pass concern
- Frontend if-unwrap desugars to `is_non_null` + `condbr` + `optional_payload`

---

## Phase 5b — Error Unions (#045-048)

### Reference Study

**Zig (primary):** `Sema.zig` — `zirTry`, `zirCatch`, `analyzeErrUnionPayload`, `analyzeErrUnionCode`.
`InternPool.zig` — `ErrorUnionType { error_set_type, payload_type }`.
`Air.zig` — `unwrap_errunion_payload`, `unwrap_errunion_err`, `is_non_err`, `is_err`,
`wrap_errunion_payload`, `wrap_errunion_err`.

**Rust (layout):** `rustc_abi/src/lib.rs` — `Variants::Multiple` with `TagEncoding::Direct`.
`Result<T,E>` as enum with discriminant. `?` operator desugars to `SwitchInt` on discriminant.

**Key Zig patterns to port:**
- Error code 0 = success (no error), nonzero = error value
- `try expr` desugars to: `is_non_err` + branch + `unwrap_errunion_payload` (success) /
  `unwrap_errunion_err` + return (error propagation)
- `expr catch |e| handler` desugars to: `is_non_err` + branch + `unwrap_errunion_payload`
  (success) / `unwrap_errunion_err` + handler (error path)
- Error sets are integer enums — each error name maps to a unique i16

### Decision 5: Error union type — `!cir.error_union<T>`

New CIR type parameterized by the payload type. Error code is always i16 (Zig uses u16,
matching for simplicity). Error code 0 = success.

```
!cir.error_union<i32>         →  !llvm.struct<(i32, i16)>     // {payload, error_code}
!cir.error_union<f64>         →  !llvm.struct<(f64, i16)>
!cir.error_union<!cir.ptr>    →  !llvm.struct<(ptr, i16)>     // no NPO for error unions
```

**Why no null-pointer optimization:** Unlike optionals (2 states: some/none), error unions
have N+1 states (success + N error codes). Can't encode in a single pointer.

**Why i16 for error codes:** Zig uses u16, supporting up to 65535 unique error values
across a compilation. Sufficient for any realistic error set. Keeps the struct compact.

**Layout:** Payload first, error code second. Follows Zig's alignment-ordered layout.
If payload is smaller than i16, padding may be inserted (LLVM handles this).

### Decision 6: CIR ops for error unions

Port the Zig AIR instruction set. Error union ops parallel the optional ops:

```
cir.wrap_result %val          wrap T → E!T (success, error_code = 0)
cir.wrap_error %code          wrap i16 → E!T (error, payload = undef)
cir.is_error %eu              test E!T has error → i1
cir.error_payload %eu         extract T from E!T (unchecked, post-branch)
cir.error_code %eu            extract i16 error code from E!T
```

**Why these specific ops:**
- `cir.wrap_result` — Zig `wrap_errunion_payload`. Constructs success case.
- `cir.wrap_error` — Zig `wrap_errunion_err`. Constructs error case.
- `cir.is_error` — Zig `is_err`. Branch condition for try/catch.
- `cir.error_payload` — Zig `unwrap_errunion_payload`. Extracts value after success branch.
- `cir.error_code` — Zig `unwrap_errunion_err`. Extracts error code after error branch.

**Why NO dedicated `cir.try` or `cir.catch` ops:** Try and catch are control flow sugar.
They desugar to `is_error` + `condbr` + `error_payload`/`error_code` at the frontend level.
This is the same pattern as optional if-unwrap (which desugars to `is_non_null` + `condbr` +
`optional_payload`). Keeping CIR ops primitive makes the dialect simpler and more composable.

**Error sets** are a frontend concern, not a CIR concept. Frontends assign integer codes
to error names. CIR just sees i16 constants. This follows the "CIR builtins = MLIR types,
language types resolved by frontends" principle.

### Decision 7: Lowering strategy

```
!cir.error_union<T> → !llvm.struct<(T, i16)>

cir.wrap_result %val  → undef + insertvalue(val, 0) + insertvalue(i16 0, 1)
cir.wrap_error %code  → undef + insertvalue(i16 %code, 1)  // payload undef
cir.is_error %eu      → extractvalue [1] → icmp ne i16 0
cir.error_payload %eu → extractvalue [0]
cir.error_code %eu    → extractvalue [1]
```

All patterns match the optional lowering approach (struct with tag), but the tag is i16
instead of i1, and the test is `icmp ne 0` instead of direct boolean.

### Frontend Syntax

**ac:**
```
error { OutOfMemory, NotFound }           // error set declaration

fn read() -> !i32 {                       // !T = error union (any error)
    return error(1)                       // return error code
}

fn safe_read() -> !i32 {
    let val: i32 = try read()             // unwrap or propagate
    return val + 1
}

fn handle() -> i32 {
    let val: i32 = read() catch |e| {     // handle error
        return -1
    }
    return val
}
```

**Zig:**
```zig
const ReadError = error { OutOfMemory, NotFound };

fn read() ReadError!i32 {
    return error.OutOfMemory;
}

fn safe_read() ReadError!i32 {
    const val = try read();
    return val + 1;
}

fn handle() i32 {
    const val = read() catch |e| {
        return -1;
    };
    return val;
}
```

**TypeScript:**
```typescript
type ReadError = "OutOfMemory" | "NotFound";

function read(): i32 | ReadError {
    return "OutOfMemory";
}

function safe_read(): i32 | ReadError {
    const val: i32 = try read();
    return val + 1;
}

function handle(): i32 {
    const val: i32 = read() catch (e) {
        return -1;
    };
    return val;
}
```

### Reference Code to Port

| What | Port from | Source |
|------|-----------|--------|
| ErrorUnionType definition | OptionalType pattern + Zig ErrorUnionType | CIRTypes.td + `~/claude/references/zig/src/InternPool.zig` |
| Type converter | Zig error union layout | Same struct pattern as optional, i16 tag |
| `cir.wrap_result` lowering | Same pattern as `cir.wrap_optional` | MemoryPatterns.cpp |
| `cir.wrap_error` lowering | Zig `wrap_errunion_err` | undef + insertvalue for error code |
| `cir.is_error` lowering | Zig `is_err` | extractvalue [1] + icmp ne 0 |
| `cir.error_payload` lowering | Zig `unwrap_errunion_payload` | extractvalue [0] |
| `cir.error_code` lowering | Zig `unwrap_errunion_err` | extractvalue [1] |
| Try syntax (ac) | Zig `zirTry` control flow | `is_error` + `condbr` + propagation |
| Catch syntax (ac) | Zig `zirCatch` control flow | `is_error` + `condbr` + handler |

---

## Phase 5c — Exception-Based Error Handling (throw/catch)

### Why Both Models

CIR is a universal IR. Languages handle errors differently:
- **Error unions (Phase 5a-b, done):** Zig, Rust. Errors in the type system, zero-cost.
- **Exceptions (Phase 5c):** TypeScript, Java, C#, C++, Python, Swift. Stack unwinding.

Both coexist in CIR. A frontend chooses which model fits. Some (Swift) may use both.

### Reference Study

**LLVM (primary):** `mlir/include/mlir/Dialect/LLVMIR/LLVMOps.td` — InvokeOp, LandingpadOp.
**Swift:** `SILInstruction.h` — `try_apply` (two-successor call, typed error).
**C++ ABI:** `__cxa_allocate_exception`, `__cxa_throw`, `__cxa_begin_catch`, `__cxa_end_catch`.

### Decision 8: Exception CIR ops

Three ops, matching the LLVM pattern:

```
cir.throw %val           throw exception value → stack unwind
cir.invoke @f(%arg)      call with normal/unwind successors
  normal ^ok unwind ^err
cir.landingpad           catch exception in unwind block → value
```

**`cir.throw`** — Terminator. Throws a value and transfers control via stack unwinding.
Lowers to: `__cxa_allocate_exception` + memcpy + `__cxa_throw`. For simple i32 exceptions
(TS throw N), this is a call to a runtime function.

**`cir.invoke`** — Terminator with 2 successors. Like `func.call` but can unwind.
Normal path: call returns, control goes to `normalDest`.
Unwind path: call throws, control goes to `unwindDest` (must start with `cir.landingpad`).
Lowers to: `llvm.invoke` with personality function on parent `llvm.func`.

**`cir.landingpad`** — First op in an unwind block. Catches the thrown value.
Returns the caught exception value (i32 for simple exceptions).
Lowers to: `llvm.landingpad { catch null }` + `__cxa_begin_catch` + extract.

### Decision 9: Lowering strategy

```
cir.throw %val          → call @__cxa_allocate_exception(sizeof(val))
                          + store val to allocated memory
                          + call @__cxa_throw(ptr, typeinfo, null)
                          + unreachable

cir.invoke @f(%args)    → llvm.invoke @f(%args)
  normal ^ok              normal ^ok
  unwind ^catch           unwind ^catch
                          (parent func gets personality = @__gxx_personality_v0)

cir.landingpad : i32    → %lp = llvm.landingpad { catch null }  // catch-all
                          %exc = call @__cxa_begin_catch(%lp[0])
                          %val = load i32, %exc
                          (+ call @__cxa_end_catch at end of handler)
```

### Frontend Syntax

**ac:** `throw expr`, `try { body } catch |e| { handler }` (exception-style, distinct from error union try)
**TypeScript:** `throw expr`, `try { body } catch (e) { handler }` (native TS syntax)
**Zig:** N/A — Zig uses error unions exclusively. Bindings available but not used.
