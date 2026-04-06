# Phase 6 — Enums, Unions, Match Design

**Date:** 2026-04-05
**Status:** Design document. Read before implementing #049-054.
**Prerequisite:** Phase 5 complete (optionals, error unions, exceptions).

---

## Reference Study

Four reference compilers handle enums/unions/match differently. CIR ports the
**Zig pattern** (separate enum types + tagged unions) for type definitions, with
**LLVM switch** for lowering, and **Swift SIL** for the high-level enum ops.

### Zig — Primary Reference

**Source:** `~/claude/references/zig/src/InternPool.zig`, `Sema.zig`, `Zir.zig`

Zig separates enums from tagged unions:
- **Enum:** Named integer constants. `enum { red, green, blue }` → i2 with values 0,1,2.
  Type: `LoadedEnumType { field_names, field_values, int_tag_type }`.
- **Tagged union:** Enum tag + payload. `union(enum) { int: i32, float: f64 }`.
  Type: `LoadedUnionType { field_types, field_names, enum_tag_mode, tag_usage }`.
- **Switch:** `zirSwitchBlock` validates operand type, handles comptime resolution,
  extracts union tag via `unionToTag()`, generates switch on integer discriminant.

### Rust — Layout Reference

**Source:** `~/claude/references/rust/compiler/rustc_abi/src/lib.rs`

Rust unifies all ADTs (struct, enum, union) under `Variants`:
- `Variants::Single { index }` — single variant (struct or single-variant enum)
- `Variants::Multiple { tag, tag_encoding, variants }` — multiple variants
- `TagEncoding::Direct` — tag = discriminant value
- `TagEncoding::Niche { untagged_variant, niche_start }` — niche optimization
- MIR: `SwitchInt { discr, targets }` for branching, `Discriminant(place)` for extraction,
  `SetDiscriminant { place, variant_index }` for construction.

### Swift — SIL Reference

**Source:** `~/claude/references/swift/include/swift/SIL/SILInstruction.h` (lines 7067+)

Swift SIL has dedicated enum instructions:
- `EnumInst` — construct enum value with case + optional payload
- `UncheckedEnumDataInst` — extract payload without safety check
- `SwitchEnumInst` — branch on enum case, pass payload as block args
- `SelectEnumInst` — select value based on enum case (non-branching)
- `InjectEnumAddrInst` — construct enum in memory

### LLVM — Lowering Target

**Source:** `~/claude/references/llvm-project/mlir/include/mlir/Dialect/LLVMIR/LLVMOps.td`

- `llvm.switch` — integer-based multi-way branch with default + case destinations
- Enums lower to integers. Tagged unions lower to `{ tag_int, payload_bytes }`.

---

## CIR Design Decisions

### Decision 1: Enum type — `!cir.enum<"Name", tag_type, variants...>`

New CIR type for named enumerations. Each variant has a name and an integer value.
The tag type is **explicit** — specified by the frontend, not inferred by CIR.

```mlir
!cir.enum<"Color", i8, Red: 0, Green: 1, Blue: 2>      // Zig: enum(u8) { red, green, blue }
!cir.enum<"Status", i32, Ok: 0, Error: 1>               // Zig: enum(u32) { ok, err }
!cir.enum<"Small", i2, A: 0, B: 1, C: 2>                // Zig: enum(u2) { a, b, c }
!cir.enum<"Default", i32, Red: 0, Green: 1, Blue: 2>    // TS: enum Color { Red, Green, Blue }
```

**Why explicit tag type:** Zig supports `enum(u8)`, `enum(u32)`, etc. — the backing
integer type is part of the language semantics, not an optimization choice. TypeScript
enums are always i32. The frontend decides the tag type based on its language rules.
CIR stores it directly.

**Lowering:** `!cir.enum<"Name", TagType, ...>` → `TagType` directly. The enum IS its
tag integer at the LLVM level. Variant names are dropped.

**Reference:** Zig `LoadedEnumType` with `int_tag_type` and `field_values`.

### Decision 2: Tagged union type — `!cir.tagged_union<"Name", variants...>`

New CIR type for discriminated unions. Each variant has a name, a tag value,
and an optional payload type. The tag is an integer, the payload is the largest
variant's type (with padding).

```mlir
!cir.tagged_union<"Shape", Circle: f64, Rect: !cir.struct<"R", w: f64, h: f64>, None: void>
```

**Lowering:** `!cir.tagged_union<...>` → `!llvm.struct<(i8, [max_payload_bytes x i8])>`.
Tag first, then payload bytes (largest variant determines size). This matches
Rust's `Variants::Multiple` with `TagEncoding::Direct`.

**Reference:** Zig `LoadedUnionType`, Rust `Variants::Multiple`.

### Decision 3: Enum ops

```
cir.enum_constant "Red" : !cir.enum<"Color", i8, ...>        // construct enum value
cir.enum_value %e : !cir.enum<"Color", i8, ...> to i8        // extract integer value
```

**`cir.enum_constant`** — Creates an enum value by variant name. Pure constant.
Lowers to `llvm.mlir.constant` with the variant's integer value and the tag type.

**`cir.enum_value`** — Extracts the integer representation (tag type). Used in switch.
Identity lowering (enum IS the integer at LLVM level). Result type must match tag type.

### Decision 4: Tagged union ops

```
cir.union_init "Circle", %radius : f64 -> !cir.tagged_union<"Shape", ...>
cir.union_tag %u : !cir.tagged_union<"Shape", ...> to i8
cir.union_payload "Circle", %u : !cir.tagged_union<"Shape", ...> to f64
```

**`cir.union_init`** — Constructs a tagged union value with a given variant and payload.
Lowers to: set tag + store payload into union struct.
Reference: Swift `EnumInst`, Rust `Aggregate(Adt, variant, [fields])`.

**`cir.union_tag`** — Extracts the tag (discriminant) integer. Used in switch.
Lowers to: `llvm.extractvalue [0]`.
Reference: Rust `Discriminant(place)`, Zig `unionToTag()`.

**`cir.union_payload`** — Extracts the payload for a specific variant. Unchecked.
Lowers to: `llvm.extractvalue [1]` + bitcast to variant payload type.
Reference: Swift `UncheckedEnumDataInst`, Zig `err_union_payload_unsafe`.

### Decision 5: Switch/match

```
cir.switch %val : i32, [
    0: ^bb_red,
    1: ^bb_green,
    2: ^bb_blue
] default ^bb_unreachable
```

**`cir.switch`** — Integer-based multi-way branch. Terminator with N+1 successors
(N cases + default). This is a thin wrapper over `llvm.switch`.

Lowers to: `llvm.switch %val, [case_values...], defaultDest, caseDestinations...`.

**Why integer-based, not semantic:** Enum and union switches desugar at the frontend
level. The frontend emits `cir.enum_value` or `cir.union_tag` to extract the integer,
then `cir.switch` on that integer. This keeps CIR ops simple and composable.
Semantic information (variant names) is preserved in the frontend AST, not in CIR.

Reference: LLVM `SwitchOp`, Rust `SwitchInt`.

### Decision 6: Frontend syntax

**ac:**
```
enum Color { Red, Green, Blue }              // default i32 backing
enum SmallColor: u8 { Red, Green, Blue }     // explicit backing type

fn describe(c: Color) -> i32 {
    match c {
        Color.Red => return 1
        Color.Green => return 2
        Color.Blue => return 3
    }
}

union Shape {
    Circle: f64,
    Rect: struct { w: f64, h: f64 },
    None
}

fn area(s: Shape) -> f64 {
    match s {
        Shape.Circle |r| => return 3.14 * r * r
        Shape.Rect |rect| => return rect.w * rect.h
        Shape.None => return 0.0
    }
}
```

**Zig:**
```zig
const Color = enum(u8) { red, green, blue };  // explicit backing type

pub fn describe(c: Color) i32 {
    return switch (c) {
        .red => 1,
        .green => 2,
        .blue => 3,
    };
}

const Shape = union(enum) {
    circle: f64,
    rect: struct { w: f64, h: f64 },
    none,
};

pub fn area(s: Shape) f64 {
    return switch (s) {
        .circle => |r| 3.14 * r * r,
        .rect => |rect| rect.w * rect.h,
        .none => 0.0,
    };
}
```

**TypeScript:**
```typescript
enum Color { Red, Green, Blue }

function describe(c: Color): number {
    switch (c) {
        case Color.Red: return 1;
        case Color.Green: return 2;
        case Color.Blue: return 3;
    }
}

// TS tagged unions via discriminated unions:
type Shape =
    | { kind: "circle"; radius: number }
    | { kind: "rect"; w: number; h: number }
    | { kind: "none" };

function area(s: Shape): number {
    switch (s.kind) {
        case "circle": return 3.14 * s.radius * s.radius;
        case "rect": return s.w * s.h;
        case "none": return 0;
    }
}
```

**Frontend fidelity notes:**
- Zig enum/switch is native Zig syntax — must compile with `zig build`
- TS `enum` and discriminated unions are native TypeScript — must compile with `tsc`
- ac uses `match` (Rust influence) and explicit union syntax

---

## New CIR Ops Summary

| Op | Description | LLVM Lowering |
|----|-------------|---------------|
| `cir.enum_constant` | construct enum value by variant name | `llvm.mlir.constant` (tag type integer) |
| `cir.enum_value` | extract tag-type integer from enum | identity (enum IS tag integer) |
| `cir.union_init` | construct tagged union with variant + payload | undef + insertvalue(tag) + insertvalue(payload) |
| `cir.union_tag` | extract tag (discriminant) from tagged union | `llvm.extractvalue [0]` |
| `cir.union_payload` | extract payload from tagged union (unchecked) | `llvm.extractvalue [1]` + bitcast |
| `cir.switch` | integer multi-way branch | `llvm.switch` |

**New types:**
- `!cir.enum<"Name", TagType, variant: value, ...>` — named enumeration → TagType integer
- `!cir.tagged_union<"Name", variant: type, ...>` — discriminated union → {tag, payload}

---

## Implementation Order

1. **#049** `!cir.enum` type + `cir.enum_constant` op + type converter + C API
2. **#050** `cir.enum_value` op + lowering + all 3 frontends emit enum values
3. **#051** `cir.switch` op + lowering + `match`/`switch` statement in all 3 frontends
4. **#052** Switch expression (value-producing) — block arguments for phi
5. **#053** `!cir.tagged_union` type + `cir.union_init` + `cir.union_tag` + `cir.union_payload`
6. **#054** Union match with payload capture — `cir.switch` + `cir.union_payload` in case blocks

Each step: type/op → lowering → 3 frontends → C API → lit tests → inline test → docs.
Follow the 12-step checklist. Write tests first. Never modify tests to pass.

---

## Reference Code to Port

| What | Port from | Source |
|------|-----------|--------|
| Enum type definition | Zig LoadedEnumType | `~/claude/references/zig/src/InternPool.zig` |
| Enum type converter | Zig int_tag_type | Enum → integer (i8 for ≤256 variants) |
| Tagged union layout | Rust Variants::Multiple | `~/claude/references/rust/compiler/rustc_abi/src/lib.rs` |
| Switch op | LLVM SwitchOp | `~/claude/references/llvm-project/mlir/include/mlir/Dialect/LLVMIR/LLVMOps.td` |
| Enum construction | Swift EnumInst | `~/claude/references/swift/include/swift/SIL/SILInstruction.h` |
| Union payload extract | Swift UncheckedEnumDataInst | Same as above |
| Switch semantics | Zig zirSwitchBlock | `~/claude/references/zig/src/Sema.zig` |
| Discriminant access | Rust Discriminant rvalue | `~/claude/references/rust/compiler/rustc_middle/src/mir/syntax.rs` |

---

## Pre-Phase 6 Audit

Before starting implementation, verify:
- [ ] All Phase 5 tests pass (129 total)
- [ ] No regressions from Phase 5 changes
- [ ] Existing struct type infrastructure can be extended for unions
- [ ] LLVM switch op is available in our MLIR version
- [ ] C API pattern (cirBuild*) scales for new ops
