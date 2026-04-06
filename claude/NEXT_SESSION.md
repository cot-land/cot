# Next Session Instructions — Phase 7c-d

**Written by:** Previous Claude session (2026-04-06)
**For:** Fresh agent continuing COT development
**Delete this file after reading — it's session-specific, not permanent docs.**

---

## How to Come Up to Speed (5 min)

Read these docs IN ORDER:

1. `CLAUDE.md` (project root) — **the rules**. 12-step feature checklist, 4 frontends, coding standards. Read the "Two Laws" and "Feature Implementation Checklist" sections. These are non-negotiable.

2. `claude/HANDOFF.md` — **current state**. 65 ops, 10 types, 200 tests. Phase 7b complete. What's done, what's next.

3. `claude/PHASE7_WITNESS_DESIGN.md` — **the plan** for what you're implementing. Protocol witness tables (PWT), value witness tables (VWT), existential containers.

4. `claude/AUDIT.md` — Round 9 audit results. All 5 issues fixed. Deferred items listed.

5. `claude/REFERENCES.md` — which reference compiler to study for each component.

---

## What Was Done This Session

### Phase 7b: Traits + Witness Tables + Structural Dispatch
- `cir.witness_table` — protocol witness table (maps trait methods to concrete implementations)
- `cir.trait_call` — named protocol dispatch (resolved by GenericSpecializer via PWT lookup)
- `cir.method_call` — structural/duck dispatch (resolved by name search on concrete type)
- `cir.shr_s` — arithmetic shift right (audit fix)
- Unsigned comparison predicates added (ult/ule/ugt/uge)
- All 4 frontends (ac, Zig, TS, Swift) emit CIR-level generics + traits
- GenericSpecializer resolves trait_call, method_call, and generic struct field types

### Feature #056: Generic Structs
- `struct Pair[T] { a: T, b: T }` in ac syntax
- `!cir.struct` with `type_param` fields — no new CIR types needed
- `substituteType()` recurses into struct field types during specialization
- ARC-ready: generic fields stay as `type_param` until specialization (VWT path for Phase 8)

---

## What to Implement Next

### Phase 7c: Protocol Dispatch (Dynamic)

Currently, `cir.trait_call` is ALWAYS resolved by the specializer to a direct `func.call`. Phase 7c adds the **dynamic dispatch** path for when the concrete type isn't known (existentials / `dyn Trait`).

New ops needed (from PHASE7_WITNESS_DESIGN.md):
- `cir.witness_method` — load function pointer from PWT at runtime (GEP + load)
- `cir.init_existential` — pack value + VWT + PWT into existential container
- `cir.open_existential` — unpack existential to access value + witnesses

### Phase 7d: Value Witness Tables (VWT)

VWT answers "how do I manage T's memory?" — size, alignment, copy, destroy, move. This is the bridge to ARC (Phase 8).

New ops (from PHASE7_WITNESS_DESIGN.md):
- `cir.vwt_size` — query type size from VWT
- `cir.vwt_align` — query alignment
- `cir.vwt_copy` — copy value through witness (retain for ref types, memcpy for value types)
- `cir.vwt_destroy` — destroy through witness (release for ref types, noop for value types)
- `cir.vwt_move` — move/transfer ownership

New pass:
- `WitnessTableGenerator` — emit VWTs for every concrete type (size, align, copy fn, destroy fn)

---

## The Pattern Used This Session (Follow This Exactly)

### For every feature:

1. **Study reference FIRST.** Use the `Explore` agent to read the actual Swift/Rust/Zig source code. Don't invent. The references are in `~/claude/references/`. The mapping is in `claude/REFERENCES.md`.

2. **Audit against references.** After studying, write up what each reference compiler does. Compare designs. The user will ask for this before approving implementation.

3. **Follow the 12-step checklist** from CLAUDE.md:
   - Study reference → Check audit → CIR ops (ODS) → Lowering patterns → ac frontend → Zig frontend → TS frontend → Swift frontend → lit tests (all 4 frontends) → lowering test → inline runtime test → build+test → update docs

4. **Update AC_SYNTAX.md** as part of the checklist. The user flagged this specifically.

5. **Test-first rule:** Write correct tests FIRST. If a test fails, the test is correct — fix the implementation, not the test.

### Specific implementation patterns:

**Adding a new CIR op:**
1. `libcir/include/CIR/CIROps.td` — TableGen definition
2. `libcir/lib/CIRDialect.cpp` — custom parse/print/verify (if hasCustomAssemblyFormat)
3. `libcir/c-api/CIRCApi.h` + `.cpp` — C API for non-C++ frontends
4. `libcot/lib/WitnessTablePatterns.cpp` (or new pattern file) — lowering pattern
5. `libcot/include/COT/Passes.h` — declare populate function
6. `libcot/lib/CIRToLLVM.cpp` — register patterns + type converters

**Updating the GenericSpecializer:**
- File: `libcot/lib/Transforms/GenericSpecializer.cpp`
- `substituteType()` — recurse into composite types
- `specializeFunction()` — clone body, substitute types, resolve trait_call/method_call
- After cloning, update type-carrying attributes (alloca elem_type, field_ptr elem_type, etc.)

**Updating frontends:**
- ac (C++): `libac/scanner.h/cpp` (keywords), `parser.h/cpp` (AST + parsing), `codegen.cpp` (CIR emission)
- Zig: `libzc/mlir.zig` (C API bindings), `libzc/astgen.zig` (codegen)
- TS (Go): `libtc/mlir.go` (C API bindings), `libtc/codegen.go` (codegen)
- Swift: `libsc/sc.swift` (everything in one file)

**Build & test:**
```bash
make all      # Build (Release)
make test     # Run all tests
make debug    # Build with debug symbols for F5 in Cursor
```

### Critical gotchas discovered this session:

1. **ac `let` requires type annotation:** `let x: i32 = 42`, NOT `let x = 42`
2. **ac struct init:** `Point { x: 1, y: 2 }` (colon syntax, not `.x = 1`)
3. **ac struct fields:** Newline-separated (no commas needed)
4. **`self` is `kw_self`** in scanner, not `identifier`. Parser handles both `self` (bare, in impl) and `self: Type` (annotated, in standalone fn).
5. **cmake build type caching:** `make all` forces Release. `make debug` patches to Debug. They share `build/` dir.
6. **GenericSpecializer name mangling:** `type.print()` produces invalid C symbols — sanitize with `isalnum` check.
7. **Swift string lifetime in C API calls:** `withCString` closures return dangling pointers. Use `Array(utf8) + [0]` for stable buffers.
8. **TS frontend `resolveTypeName`:** Returns CIR type string (`!cir.struct<"Name">`), not plain name. Use AST node text directly for protocol/trait names.

---

## Key Reference Files for Phase 7c-d

| What | File |
|------|------|
| PWT structure | `~/claude/references/swift/include/swift/SIL/SILWitnessTable.h` |
| VWT entries | `~/claude/references/swift/include/swift/ABI/ValueWitness.def` |
| Type metadata | `~/claude/references/swift/include/swift/Runtime/Metadata.h` |
| SIL witness_method | `~/claude/references/swift/include/swift/SIL/SILInstruction.h` (lines 7872+) |
| SIL existential ops | `~/claude/references/swift/include/swift/SIL/SILInstruction.h` (lines 7931+) |
| ARC + generics | `~/claude/references/swift/lib/SILOptimizer/ARC/` |
| Generic specializer | `~/claude/references/swift/lib/SILOptimizer/Transforms/GenericSpecializer.cpp` |
| Rust drop glue | `~/claude/references/rust/compiler/rustc_middle/src/ty/instance.rs` |

---

## User Preferences (Critical)

- **No shortcuts, no fast paths.** Production-grade from day one.
- **No frontend monomorphization.** ALL 4 frontends emit CIR-level generics.
- **Study reference, then port. Never invent.** Every feature traces to a reference compiler.
- **Test-first.** Never modify tests to make them pass.
- **Audit before implementing.** User will ask you to study references before approving a design.
- **Update AC_SYNTAX.md** with every new feature.
- **NEVER** `git checkout`, `git restore`, `git reset --hard`, `git clean`, `git add .`
