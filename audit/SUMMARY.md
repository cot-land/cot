# Audit Summary

**Last Updated:** February 1, 2026

## Overall Status: M19-M20 COMPLETE

**Total Tests: 65 tests (all passing)**
- Arithmetic: 10/10
- Control Flow: 14/14
- Functions: 16/16
- Memory: 5/5
- Structs: 5/5
- Arrays: 5/5
- Strings: 7/7 (NEW - M20)
- ARC: 2/2 (NEW - M19)
- Loops: 1/1

**Unit Tests: All passing**

---

## Compilation Pipeline

```
Source Code (.cot)
       │
       ▼
┌─────────────┐
│   Scanner   │  token.zig, scanner.zig
└─────────────┘
       │ tokens
       ▼
┌─────────────┐
│   Parser    │  parser.zig, ast.zig
└─────────────┘
       │ AST
       ▼
┌─────────────┐
│   Checker   │  checker.zig, types.zig
└─────────────┘
       │ typed AST
       ▼
┌─────────────┐
│   Lowerer   │  lower.zig, ir.zig
└─────────────┘
       │ IR
       ▼
┌─────────────┐
│ SSA Builder │  ssa_builder.zig
└─────────────┘
       │ SSA
       ▼
┌─────────────────────────────────────────┐
│            SSA Passes                    │
│  rewritegeneric.zig  (const_string)     │
│  rewritedec.zig      (decomposition)    │
│  lower_wasm.zig      (wasm ops)         │
└─────────────────────────────────────────┘
       │ Wasm SSA
       ▼
┌─────────────┐
│   gen.zig   │  SSA → Prog instructions
└─────────────┘
       │ Prog chain
       ▼
┌───────────────┐
│ preprocess.zig│  Control flow, dispatch loop
└───────────────┘
       │
       ▼
┌───────────────┐
│ assemble.zig  │  Prog → bytecode
└───────────────┘
       │
       ▼
┌─────────────┐
│  link.zig   │  Sections, imports, exports
└─────────────┘
       │
       ▼
   .wasm file
```

---

## Wasm Backend Components

| Component | Status | Go Reference | Purpose |
|-----------|--------|--------------|---------|
| gen.zig | ✅ Done | wasm/ssa.go | SSA value → Wasm instructions |
| preprocess.zig | ✅ Done | wasmobj.go | Dispatch loop, control flow |
| assemble.zig | ✅ Done | wasmobj.go | Prog → binary bytecode |
| link.zig | ✅ Done | wasm/asm.go | Wasm sections, imports/exports |
| prog.zig | ✅ Done | obj.Prog | Pseudo-instruction format |
| constants.zig | ✅ Done | a.out.go | Wasm opcodes, types |
| arc.zig | ✅ Done | Swift HeapObject.cpp | ARC runtime functions |

---

## SSA Pass Architecture

Following Go's cmd/compile/internal/ssa/ patterns:

| Pass | File | Go Reference | Purpose |
|------|------|--------------|---------|
| rewritegeneric | rewritegeneric.zig | rewritegeneric.go | Algebraic simplification, const_string → string_make |
| rewritedec | rewritedec.zig | rewritedec.go | Decompose compound types (slice/string ptr/len) |
| lower_wasm | lower_wasm.zig | lower.go | Generic ops → Wasm-specific ops |

### Key Decomposition Patterns (rewritedec.zig)

```
slice_len(slice_make(ptr, len)) → copy(len)
slice_ptr(slice_make(ptr, len)) → copy(ptr)
string_len(string_make(ptr, len)) → copy(len)
string_ptr(string_make(ptr, len)) → copy(ptr)
string_concat(s1, s2) → static_call("cot_string_concat") + string_make
```

---

## Milestone Status

| Milestone | Status | Description |
|-----------|--------|-------------|
| M1-M3 | ✅ Done | Wasm SSA ops, lowering pass, code generator |
| M4-M5 | ✅ Done | E2E: return 42, add two numbers |
| M6-M7 | ✅ Done | Control flow (if/else, loops, break, continue) |
| M8-M9 | ✅ Done | Function calls (params, recursion), CLI outputs .wasm |
| M10 | ✅ Done | Linear memory (load/store, SP global, frame allocation) |
| M11 | ✅ Done | Pointers (off_ptr, add_ptr, sub_ptr) |
| M12 | ✅ Done | Structs (field read/write via off_ptr) |
| M13 | ✅ Done | Arrays/Slices (decomposition, frame size fix) |
| M14 | ✅ Done | Strings (rewritegeneric + rewritedec passes) |
| M15 | ✅ Done | ARC runtime (retain/release in arc.zig) |
| M16 | ✅ Done | Browser imports (import section, import-aware exports) |
| M17 | ✅ Done | Frontend emits retain/release |
| M18 | ✅ Done | Heap allocation (new keyword) |
| **M19** | ✅ **Done** | Destructor calls on release |
| **M20** | ✅ **Done** | String concatenation & indexing |
| M21 | ⏳ Next | Array append |
| M22 | ⏳ TODO | For-range loops |
| M23-24 | ⏳ TODO | Native AOT debugging |

---

## M19: Destructor Calls on Release

### Implementation Summary

| Component | File | Change |
|-----------|------|--------|
| IR Node | ir.zig | Added `TypeMetadata` struct |
| SSA Op | op.zig | Added `metadata_addr` operation |
| Wasm Gen | gen.zig | Added `metadata_addr` handler |
| Driver | driver.zig | Build destructor table, type metadata |
| ARC | arc.zig | Release calls destructor via `call_indirect` |
| Lower | lower.zig | Integrated CleanupStack from arc_insertion.zig |

### Swift References

| Pattern | Swift File | Cot Implementation |
|---------|------------|-------------------|
| CleanupStack | Cleanup.h | arc_insertion.zig |
| swift_allocObject | HeapObject.cpp | arc.zig generateAllocBody |
| swift_release_dealloc | HeapObject.cpp | arc.zig generateReleaseBody |
| FullMetadata::destroy | Metadata.h | driver.zig metadata generation |

---

## M20: String Concatenation

### Implementation Summary

| Component | File | Change |
|-----------|------|--------|
| Decomposition | rewritedec.zig | string_concat → static_call + string_make |
| Runtime | arc.zig | cot_string_concat with memory.copy |
| Codegen | wasm.zig | emitMemoryCopy helper |
| Frame Layout | gen.zig | Fixed local_addr offset calculation |

### Bug Fix: Multi-Variable String Offsets

**Problem:** `len(s1) + len(s2)` returned wrong values when both s1 and s2 were string variables.

**Root Cause 1:** gen.zig calculated local offsets as `slot * 8`, but STRING is 16 bytes.

**Fix:** `getLocalOffset()` sums actual sizes from `local_sizes` array.

**Root Cause 2:** STRING loads create `slice_make`, but extractStringPtr/Len only checked for `string_make`.

**Fix:** Check both `string_make` and `slice_make` ops.

---

## Component Directory

| Category | Files | Status |
|----------|-------|--------|
| Core | 4 | ✅ types, errors, target, testing |
| Frontend | 11 | ✅ scanner, parser, checker, IR, lowerer |
| SSA | 12 | ✅ op, value, block, func, passes |
| SSA Passes | 3 | ✅ rewritegeneric, rewritedec, lower_wasm |
| Wasm Codegen | 7 | ✅ wasm/, arc.zig |
| Native Codegen | 8 | ✅ arm64, amd64, asm, regs |
| Object Files | 3 | ✅ elf, macho, dwarf |
| Pipeline | 3 | ✅ driver, main, pipeline_debug |

---

## Key Design Decisions

### 1. STRING is slice<u8>

STRING type is internally `{ .slice = .{ .elem = U8 } }` (16 bytes: ptr + len).

This means:
- `type_registry.get(STRING)` returns `.slice`
- STRING loads go through slice handling code
- STRING locals create `slice_make`, not `string_make`

### 2. Two-Stage Decomposition

1. **rewritegeneric:** `const_string` → `string_make(ptr, len)`
2. **rewritedec:** `slice_len(slice_make(ptr, len))` → `copy(len)`

### 3. ARC Object Layout

```
+0: metadata_ptr (i64) - points to type metadata
+8: ref_count (i64)
+16: user data...

Type Metadata:
+0: type_size (i64)
+8: destructor_idx (i32) - function table index, 0 = no destructor
```

---

## Next Steps

1. **M21: Array Append** - Dynamic array growth with ARC
2. **M22: For-Range Loops** - Iterator protocol
3. **AOT Phase 4** - Wire ARM64/AMD64 into driver
4. **Additional ARC Tests** - Multiple objects, nested scopes, early return

---

## Related Documents

| Document | Purpose |
|----------|---------|
| CLAUDE.md | Development instructions, Go reference locations |
| ROADMAP_PHASE2.md | M17-M24 detailed plan with Go/Swift research |
| TYPE_FLOW.md | How types transform through pipeline |
| audit/wasm/*.md | Individual wasm component audits |
| audit/frontend/*.md | Individual frontend component audits |
