# Wasm Upgrade Plan: Making Cot a True Wasm-First Language

**Purpose:** Concrete task list for upgrading Cot's Wasm output from 1.0 to modern 2.0/3.0. Every high-priority feature here is already shipping in all browsers.

**Last updated:** February 2026

---

## Current State

Cot emits **Wasm 1.0** with cherry-picked 2.0 features (sign extension ops, reference types for tables). All Wasm 3.0 features are absent. This means:

- `@memcpy` compiles to a **word-by-word copy loop** (gen.zig:998-1013) instead of native `memory.copy`
- Closures use **`call_indirect` + table** instead of typed `call_ref`
- Deep recursion **stack overflows** — no `return_call` tail calls
- Error propagation generates **branch-per-call-site** — no `try_table`/`throw`
- Compound returns (string ptr+len) use a **complex local-decomposition workaround** with 5+ special cases
- `tail_call` SSA op exists but is **stubbed out**: `lower_wasm.zig:347` says `"Wasm has no tail call (yet)"`

---

## Task List

### Wave 1: Wasm 2.0 Quick Wins (hours of work, immediate value)

These features are universally supported and require minimal code changes.

#### Task 1.1: Replace memcpy loop with `memory.copy`

**Impact:** 5-10x faster memcpy — affects every List grow, Map rehash, string copy, struct clone.

**Current code** (`gen.zig:998-1013`):
```zig
.wasm_lowered_move => {
    const size: i32 = @intCast(v.aux_int);
    const num_words: u32 = @intCast(@divTrunc(size + 7, 8));
    var word_i: u32 = 0;
    while (word_i < num_words) : (word_i += 1) {  // LOOP — one i64 load/store per iteration
        ...
        const ld = try self.builder.append(.i64_load);
        ...
        const st = try self.builder.append(.i64_store);
    }
},
```

**Target code:**
```zig
.wasm_lowered_move => {
    const size: i32 = @intCast(v.aux_int);
    try self.getValue64(v.args[0]); // dest
    _ = try self.builder.append(.i32_wrap_i64);
    try self.getValue64(v.args[1]); // src
    _ = try self.builder.append(.i32_wrap_i64);
    // Push size as i32
    const c = try self.builder.append(.i32_const);
    c.from = prog_mod.constAddr(size);
    // memory.copy: dest src size → (copies size bytes from src to dest)
    _ = try self.builder.append(.memory_copy);
},
```

**Files to change:**
| File | Change |
|------|--------|
| `wasm_opcodes.zig:306` | Add `FC_MEMORY_FILL: u8 = 0x0B` (copy already defined) |
| `gen.zig:998-1013` | Replace loop with `memory.copy` emission |
| `assemble.zig` | Add `.memory_copy` encoding: `0xFC`, LEB128(0x0A), `0x00`, `0x00` |
| `constants.zig` (or instruction enum) | Add `.memory_copy`, `.memory_fill` instruction variants |

**Verification:** Run `./test/run_all.sh` — all memcpy-dependent tests (list, map, set, string) must pass.

---

#### Task 1.2: Add `memory.fill` for zero-initialization

**Impact:** Faster zero-init for `@alloc` and struct initialization.

**Files to change:**
| File | Change |
|------|--------|
| `wasm_opcodes.zig` | Confirm `FC_MEMORY_FILL = 0x0B` added in 1.1 |
| `gen.zig` | Where zero-init loops exist (or where `@alloc` zeroes memory), emit `memory.fill` |
| `assemble.zig` | Add `.memory_fill` encoding: `0xFC`, LEB128(0x0B), `0x00` |
| `arc.zig` | If allocator does manual zero-fill, replace with `memory.fill` call |

---

#### Task 1.3: Add non-trapping float-to-int conversions

**Impact:** Safe float casts — no unexpected traps on NaN/infinity.

**Current:** `i64.trunc_f64_s` (0xAE) traps on out-of-range values.
**Target:** `i64.trunc_sat_f64_s` (0xFC 0x06) saturates instead.

**Files to change:**
| File | Change |
|------|--------|
| `wasm_opcodes.zig` | Add `FC_I32_TRUNC_SAT_F32_S = 0x00` through `FC_I64_TRUNC_SAT_F64_U = 0x07` |
| `gen.zig` | Where float-to-int ops are emitted, use `trunc_sat` variants |
| `assemble.zig` | Add encoding for `0xFC 0x00` through `0xFC 0x07` |
| `decoder.zig` | Add decoding for the new opcodes (native pipeline) |

---

#### Task 1.4: Emit data count section

**Impact:** Spec compliance — required for single-pass validation.

**Current:** `link.zig` emits sections 1-11 but skips 12 (data count). The enum `Section.data_count = 12` is defined but never emitted.

**Files to change:**
| File | Change |
|------|--------|
| `link.zig` | After function section, before code section, emit data count section with the number of data segments |

---

### Wave 2: Wasm 3.0 Tail Calls (1-2 days, prevents stack overflow)

#### Task 2.1: Add `return_call` opcode

**Files to change:**
| File | Change |
|------|--------|
| `wasm_opcodes.zig` | Add `return_call: u8 = 0x12`, `return_call_indirect: u8 = 0x13` |

---

#### Task 2.2: Add `wasm_return_call` SSA op

**Current:** `op.zig:74` has `tail_call` but `lower_wasm.zig:347` maps it to `null`.

**Files to change:**
| File | Change |
|------|--------|
| `op.zig` | Add `wasm_return_call` alongside existing `wasm_call` (line ~200) |
| `lower_wasm.zig:347` | Change `tail_call => null` to `tail_call => .wasm_return_call` |

---

#### Task 2.3: Detect tail position in the frontend

A call is in tail position when:
1. It's the last expression in a `return` statement
2. No `defer` statements are active in the current scope
3. No ARC releases are pending (no owned objects to release)

**Files to change:**
| File | Change |
|------|--------|
| `lower.zig` | In `lowerReturn()` (or equivalent), check if return value is a call. If so and no defer/ARC pending, emit `tail_call` SSA op instead of `call` + `ret` |

**Detection pseudocode:**
```
if return_expr is Call and
   active_defers.len == 0 and
   arc_cleanup_stack.len == 0:
    emit SSA tail_call
else:
    emit SSA call + ret
```

---

#### Task 2.4: Emit `return_call` in Wasm codegen

**Files to change:**
| File | Change |
|------|--------|
| `gen.zig` | Add `wasm_return_call` handler: push args, emit `0x12` with func index (no `aret` needed) |
| `assemble.zig` | Add `.return_call` encoding: `0x12 funcidx:u32` |

---

#### Task 2.5: Parse and decode `return_call` in native pipeline

**Files to change:**
| File | Change |
|------|--------|
| `wasm_parser.zig` | Parse opcode `0x12` (read funcidx) |
| `decoder.zig` | Decode `0x12` → emit CLIF tail call |
| `translator.zig` | Translate to CLIF `return_call` instruction |
| ARM64 backend | `RetCall` instruction already defined at `aarch64/inst/mod.zig:1702` — wire it up |
| x64 backend | `return_call_known`/`return_call_unknown` defined at `x64/inst/mod.zig:669-675` — wire up |

**Verification:** Write recursive test that overflows without tail calls, passes with them:
```cot
fn countDown(n: i64) i64 {
    if n == 0 { return 0 }
    return countDown(n - 1)  // tail call — should handle n=1000000
}
test "deep tail recursion" {
    @assert_eq(countDown(1000000), 0)
}
```

---

### Wave 3: Wasm 3.0 Typed Function References (3-4 days, faster closures)

#### Task 3.1: Add typed ref opcodes

**Files to change:**
| File | Change |
|------|--------|
| `wasm_opcodes.zig` | Add `call_ref = 0x14`, `ref_as_non_null = 0xD4`, `br_on_null = 0xD5`, `br_on_non_null = 0xD6`, `ref_eq = 0xD3` |

---

#### Task 3.2: Extend type section for function reference types

Currently the type section only declares function signatures. Typed refs require the type section to also declare reference types that closures can use.

**Files to change:**
| File | Change |
|------|--------|
| `link.zig` | In type section emission, also emit `(ref $fn_type)` types for each closure signature used in the program |

---

#### Task 3.3: Change closure codegen to use `call_ref`

**Current** (`gen.zig:870-911`):
```zig
.wasm_lowered_closure_call => {
    // ... push args ...
    try self.getValue64(args[0]);        // table index
    _ = try self.builder.append(.i32_wrap_i64);
    const p = try self.builder.append(.call_indirect);  // table lookup + type check
    p.to = prog_mod.constAddr(v.aux_int);
},
```

**Target:**
```zig
.wasm_lowered_closure_call => {
    // ... push args ...
    // Push typed function reference (not table index)
    try self.getValue64(args[0]);        // (ref $fn_type) — no i32 wrap needed
    const p = try self.builder.append(.call_ref);        // direct call, no table
    p.to = prog_mod.constAddr(v.aux_int);  // type index
},
```

**Files to change:**
| File | Change |
|------|--------|
| `gen.zig:870-911` | Replace `call_indirect` with `call_ref` for closure calls |
| `gen.zig` | Where closures are created, emit `ref.func` instead of storing table index |
| `link.zig` | Programs using only closures (no `call_indirect` for other purposes) can skip table emission |
| `assemble.zig` | Add `.call_ref` encoding: `0x14 typeidx:u32` |

---

#### Task 3.4: Parse/decode `call_ref` in native pipeline

**Files to change:**
| File | Change |
|------|--------|
| `wasm_parser.zig` | Parse `0x14` (read typeidx) |
| `decoder.zig` | Decode `0x14` → CLIF indirect call |
| `translator.zig` | Translate `call_ref` to CLIF call instruction |

---

### Wave 4: Multi-Value Returns (2-3 days, eliminate compound return bugs)

#### Task 4.1: Emit multi-result function types

**Current:** Functions returning `string` declare `(result i64)` — single return. The second value (len) is stored to a separate local via `compound_len_locals`.

**Target:** Functions returning `string` declare `(result i64 i64)` — two returns. Both values stay on the Wasm stack.

**Files to change:**
| File | Change |
|------|--------|
| `link.zig` | When building function types, detect compound return types and emit `(result i64 i64)` |
| `driver.zig` | Function type declarations: change compound returns from 1 to 2 results |

---

#### Task 4.2: Simplify return value emission

**Current** (`gen.zig:202-226`): Three separate code paths for return depending on whether the return value is `string_make`, a call result with `compound_len_locals`, or a simple value.

**Target:** For multi-value returns, just push both values and emit `return`. No special cases.

**Files to change:**
| File | Change |
|------|--------|
| `gen.zig:202-226` | Simplify `.ret` handler — push N values for N-return function, emit `aret` |
| `gen.zig:92-95` | Remove `compound_len_locals` map entirely |
| `gen.zig:354-367` | Remove `string_ptr`/`string_len` special-case extraction — values are already on stack |
| `gen.zig:1112-1127` | Remove compound return storage workaround — caller gets both values on stack |

---

#### Task 4.3: Update native pipeline for multi-value

**Files to change:**
| File | Change |
|------|--------|
| `wasm_parser.zig` | Already handles multi-return types — verify |
| `decoder.zig` | Verify multi-return decoding works |
| `translator.zig` | Verify `translateCall` handles multi-return |
| `driver.zig` | Update function type registration for compound returns |
| `ssa_builder.zig` | Simplify compound return handling (currently has special decomposition logic) |

---

### Wave 5: Wasm 3.0 Exception Handling (1-2 weeks, reliable defer + zero-cost errors)

This is the most complex wave. Consider implementing after waves 1-4 are stable.

#### Task 5.1: Add exception opcodes and tag section

**Files to change:**
| File | Change |
|------|--------|
| `wasm_opcodes.zig` | Add `throw = 0x08`, `throw_ref = 0x0A`, `try_table = 0x1F`. Add `Section.tag = 13` |
| `link.zig` | Emit tag section (ID 13) after global section, before export section |

---

#### Task 5.2: Define error tags

Each Cot error set (`FsError`, `ParseError`, etc.) maps to a Wasm exception tag. The tag carries the error value as payload.

**Design decision needed:** One tag per error set, or one generic "Cot error" tag?

- **One tag per error set:** More precise catch handlers, matches Cot's type system
- **One generic tag:** Simpler implementation, matches Go/Zig's "errors are values" philosophy

**Recommendation:** Start with one generic tag carrying `(error_set_id: i32, error_value: i32)`. Refine later.

---

#### Task 5.3: Emit `throw` for error returns

**Current:** Functions returning `FsError!i64` construct an error union struct (tag + value) and `return` it. Caller checks the tag with `br_if`.

**Target:** On error, emit `throw $cot_error` with the error value. On success, just return the value directly (no tag, no union struct).

**Impact on the entire pipeline:**
| File | Change |
|------|--------|
| `lower.zig` | Error return → emit `throw` SSA op instead of struct construction |
| `gen.zig` | `throw` → Wasm `throw` opcode (0x08) |
| `link.zig` | Declare tag in tag section |

---

#### Task 5.4: Emit `try_table` for `try` expressions

**Current:** `try expr` → call, check tag, branch to error handler.

**Target:** `try expr` → wrap call in `try_table`, catch clause branches to error handler.

```wasm
;; Current: try openFile("foo.txt")
call $openFile        ;; returns error union (tag, value)
local.tee $result
i32.load offset=0     ;; load tag
i32.const 0
i32.ne
br_if $error_handler  ;; branch if error

;; Target:
try_table (catch $cot_error $error_handler)
  call $openFile      ;; throws on error, returns plain value on success
end
;; if we get here, success — value is on stack
```

---

#### Task 5.5: Wrap defer-containing functions in `try_table`

**Current:** `defer cleanup()` runs at function exit via explicit call before `return`. If a called function traps, defer doesn't run.

**Target:** Function body wrapped in `try_table (catch_all $defer_cleanup)`. If ANY exception propagates through, the catch clause runs defers then re-throws with `throw_ref`.

```wasm
;; Function with defer:
try_table (catch_all_ref $cleanup)
  ;; ... function body ...
  ;; normal exit: run defers, return
  call $cleanup
  return
end
$cleanup:
  ;; exception path: run defers, re-throw
  call $cleanup
  throw_ref
```

---

### Wave 6: Post-3.0 Features (track, don't implement yet)

These features are either not shipping in all browsers or are still being standardized. Track them but don't invest implementation time yet.

| Feature | Status | When to Implement | Cot Use Case |
|---------|--------|-------------------|--------------|
| **Threads/atomics** | Shipping all browsers | When adding concurrency (0.5) | Multi-threaded server, atomic ARC |
| **Stack switching** | Phase 3, ~2026-2027 | When adding async (0.5) | `async fn` on Wasm target |
| **Component model** | Active dev, WASI 0.3 | When adding packages (0.6) | Cross-language module interop |
| **Branch hinting** | Standardized | After waves 1-5 | Cold-path optimization |
| **Wide arithmetic** | Phase 3 | When adding BigInt/crypto | 128-bit intermediates |
| **Memory64** | Shipping (no Safari) | When targeting >4GB servers | Remove i32 narrowing |

---

## Summary

| Wave | Features | Effort | Impact |
|------|----------|--------|--------|
| **1** | `memory.copy`/`fill`, `trunc_sat`, data count | 1 day | Performance, safety, compliance |
| **2** | `return_call` tail calls | 1-2 days | No stack overflow on recursion |
| **3** | `call_ref` typed function references | 3-4 days | Faster closures, no table overhead |
| **4** | Multi-value returns | 2-3 days | Eliminate compound return bugs |
| **5** | `try_table`/`throw` exception handling | 1-2 weeks | Reliable defer, zero-cost errors |
| **6** | Post-3.0 features | Track only | Future waves |

**Total for waves 1-4:** ~8-10 days of focused work
**Total for wave 5:** ~1-2 weeks additional

A Wasm-first language should use the latest Wasm features. Waves 1-4 bring Cot's Wasm output from 2019-era to 2025-era with roughly 2 weeks of work. This is the highest-ROI investment for the compiler before 1.0.

---

## Reference Documents

- `docs/specs/WASM_2_0_REFERENCE.md` — Complete Wasm 2.0 feature reference
- `docs/specs/WASM_3_0_REFERENCE.md` — Complete Wasm 3.0 feature reference with opcodes
- `docs/specs/wasm-3.0-full.txt` — Full Wasm 3.0 specification (25K lines)
