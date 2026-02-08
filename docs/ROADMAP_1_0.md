# Cot 1.0: The Road from 0.3 to Public Release

## Document Purpose

This document conceptualizes how Cot reaches a 1.0 release — a version other developers can install, learn, and build real applications with. It covers the feature roadmap, the architectural evolution needed (particularly the Wasm IR question), ecosystem requirements, and a rough phasing plan.

---

## Where We Are: Cot 0.3

### By the Numbers

| Metric | Value |
|--------|-------|
| Zig source code | ~98,000 lines across 121 files |
| Tests passing | 853 (0 failures) |
| Test case files | 121 `.cot` files |
| Commits | 226 over ~6 weeks of AI-assisted development |
| Wasm E2E tests | 81 |
| Native E2E sub-tests | 453 |
| Native AOT pipeline | 61,000 lines (regalloc2 port, ARM64, x64) |
| Documentation | 11,000+ lines across 23 files |

### What 0.3 Proves

The compiler can handle a real programming language:

```cot
// Generics, closures, ARC, error unions, defer — all working on Wasm + native
fn map(T, U)(items: List(T), f: fn(T) -> U) List(U) {
    var result = List_init(U)()
    for i in 0..List_count(T)(items) {
        let item = List_get(T)(items, i)
        List_append(U)(&result, f(item))
    }
    return result
}
```

The architecture is proven: Cot source compiles to Wasm bytecode, which either runs in a browser or gets AOT-compiled to ARM64/x64 native executables through a Cranelift-port pipeline. ARC handles memory. 37+ language features work on both targets.

### What 0.3 Lacks for 1.0

A developer downloading Cot today would immediately hit:

1. **No package manager** — can't install libraries
2. **No standard library** — no file I/O, no HTTP, no JSON, no formatted printing
3. **No string interpolation** — `"Hello, " + name` works but `"Hello, {name}"` doesn't
4. **No traits/interfaces** — can't write polymorphic APIs
5. **No async** — can't write a web server that handles concurrent connections
6. **No error messages that help** — compiler errors are functional but not friendly
7. **No documentation** — no language guide, no API docs, no tutorials
8. **No editor support** — no LSP, no syntax highlighting packages
9. **No way to produce a web app** — browser deployment story is incomplete
10. **No way to interact with the OS** — extern fn pipeline is incomplete on native

---

## What 1.0 Means

**1.0 is not "feature-complete forever." It's "useful enough to build real things and stable enough to depend on."**

### The 1.0 Contract

A developer who installs Cot 1.0 should be able to:

1. **Write a web server** that handles HTTP requests, reads files, talks to a database
2. **Write a browser application** that manipulates the DOM, handles events, fetches APIs
3. **Share code between client and server** — the core promise
4. **Use typed collections** — `List(T)`, `Map(K,V)`, `Set(T)`
5. **Handle errors properly** — error unions, try/catch, meaningful error messages
6. **Import packages** — a package manager with a registry
7. **Get editor help** — LSP with autocomplete, go-to-definition, error highlighting
8. **Read documentation** — language guide, standard library API docs, examples
9. **Trust stability** — code that compiles today will compile tomorrow

### What 1.0 is NOT

- Not self-hosting (that's a maturity milestone, not a user requirement)
- Not the fastest language ever (competitive is enough)
- Not feature-frozen (1.x releases add features; 1.0 syntax is stable)

---

## The Wasm IR Question: Deep Analysis

### The Current Architecture

Every Cot program, regardless of target, compiles through Wasm:

```
Cot Source → Frontend → SSA → Wasm bytecode → { Browser | AOT native }
```

This was the right choice for 0.x. It simplified the compiler enormously:
- One codegen backend to maintain instead of two
- Wasm is well-specified, no ambiguity
- Browser deployment "for free"
- The AOT pipeline reuses the same IR

But Wasm was designed as a **deployment target**, not a **compiler IR**. As the language grows, this distinction matters.

**Note:** Cot currently emits Wasm 1.0 bytecode. Wasm 3.0 was released in September 2025 and adds tail calls, exception handling, typed function references, GC types, multiple memories, 64-bit address space, and relaxed SIMD. Cot can incrementally adopt 3.0 features — the opcodes are additive, and the native AOT parser (`wasm_parser.zig`) just needs to handle the new instructions.

### Where Wasm Works and Will Continue to Work

These features flow through Wasm without any friction:

| Feature | How Wasm handles it | Status |
|---------|-------------------|--------|
| Integer arithmetic (i8–u64) | `i32.*` / `i64.*` ops | Works today |
| Float arithmetic (f32, f64) | `f32.*` / `f64.*` ops | Works today |
| Control flow (if, while, for, switch) | `block` / `loop` / `br_if` / `br_table` | Works today |
| Function calls | `call` / `call_indirect` | Works today |
| Structs (stack + heap) | Linear memory loads/stores | Works today |
| Arrays and slices | Linear memory with pointer arithmetic | Works today |
| Strings | Byte sequences in linear memory | Works today |
| ARC retain/release | Module functions in Wasm bytecode | Works today |
| Generics | Resolved before Wasm (monomorphization) | Works today |
| Closures | Table entries + heap-allocated captures | Works today |
| Error unions | Tagged values in linear memory | Works today |
| Function pointers | `call_indirect` via table | Works today |
| Defer | Lowered to cleanup blocks before Wasm | Works today |
| Traits (planned) | Vtables in linear memory, `call_indirect` | Will work |
| Map(K,V) (planned) | Hash table in linear memory | Will work |
| Pattern matching (planned) | Lowered to branches before Wasm | Will work |

**These represent ~90% of what a typical web application needs.** For many users, Cot 1.0 could ship with Wasm as the sole IR and they'd never notice.

### WebAssembly 3.0 (Released September 2025)

**Wasm 3.0 was released in September 2025 and standardizes several features that were previously considered Cot blockers.** This significantly reduces the urgency of an IR split.

#### Tail Calls — STANDARDIZED

`return_call` (0x12), `return_call_indirect` (0x13), `return_call_ref` (0x15) are now in the spec. Cot can emit these directly. No trampoline workaround needed. This was previously listed as a Wasm limitation — it no longer is.

#### Exception Handling — STANDARDIZED

`throw` (0x08), `throw_ref` (0x0A), `try_table` (0x1F) with catch clauses. Tags (exception types) are first-class module entities with their own section (section 13). New heap types `exnref` / `noexn`.

Implications for Cot:
- Defer cleanup across Wasm call boundaries can use `try_table` + `catch_all` to ensure cleanup runs even if a callee traps
- Interop with languages that use exceptions (C++, Java compiled to Wasm) becomes possible
- Error union propagation could optionally use Wasm exceptions for efficiency (though the current approach of return-value error codes is simpler and works well)

#### Typed Function References — STANDARDIZED

`call_ref x` (0x14) calls through a typed function reference — no table indirection. `ref.as_non_null`, `br_on_null`, `br_on_non_null` for null checking. References can specify any heap type: `(ref null? heaptype)`.

Implications for Cot:
- Closures and function pointers can use `call_ref` instead of `call_indirect` — faster, no table lookup overhead
- Closure capture structs could carry `(ref $func_type)` instead of a table index
- This is a significant performance win for functional patterns (map, filter, reduce over collections)

#### GC Types — STANDARDIZED (but Cot doesn't need them)

`struct.new/get/set`, `array.new/get/set/len`, `ref.i31`, `ref.eq`, `ref.cast`, `br_on_cast`. Full subtyping with recursive types, packed fields (i8, i16).

Cot uses ARC, not GC, so these types are not needed for Cot's own objects. However, they matter for **interop** — consuming objects from Kotlin/Wasm, Dart/Wasm, or Java/Wasm libraries. This is a post-1.0 concern.

#### Multiple Memories — STANDARDIZED

All load/store/memory instructions now take a memory index. Data segments reference a memory index. Cot could use separate memories for different purposes (heap vs. stack vs. ARC metadata), improving isolation and debuggability.

#### 64-bit Address Space — STANDARDIZED

Memory types can use `i64` addresses, lifting the 4GB linear memory limit. Essential for server-side Cot processing large datasets.

#### NOT in Wasm 3.0 (as of Sep 2025 release)

| Proposal | Status | Impact on Cot |
|---------|--------|--------------|
| **Stack switching** | Not included (separate proposal, still in progress) | Async on browser remains JS-interop-based |
| **Shared-everything threads** | Not included | Concurrency remains single-threaded on Wasm |
| **Component model** | Separate WASI layer | Module composition is a post-1.0 concern |
| **Threads/atomics** | Not in 3.0 | No shared-memory concurrency on Wasm |

### Where Wasm Becomes Limiting

The remaining ~10% contains features that are either impossible, slow, or ugly when forced through Wasm:

#### 1. Tail Call Optimization (TCO) — SOLVED BY WASM 3.0

**What it is:** When a function's last action is calling another function (or itself), reuse the current stack frame instead of allocating a new one.

```cot
fn factorial(n: i64, acc: i64) i64 {
    if n <= 1 { return acc }
    return factorial(n - 1, n * acc)  // tail position — reuses frame
}
```

**Wasm 3.0 (released Sep 2025):** `return_call` (0x12), `return_call_indirect` (0x13), and `return_call_ref` (0x15) are part of the standard. All major engines (V8, SpiderMonkey, JavaScriptCore) ship them.

**What Cot needs:** Detect tail position calls in the lowerer. Emit `return_call` instead of `call` + `return`. For native AOT, lower to `b`/`jmp` instead of `bl`/`call`.

**Impact:** No longer a Wasm limitation. Implement when needed (stdlib tree traversal, parser combinators).

#### 2. Async/Await and Coroutines

**What it is:** Cooperative multitasking — a function suspends, yields control, and resumes later.

**Why it matters:** This is the single most important missing feature for Cot's target audience (web developers). Every web server needs async I/O. Every browser app needs async fetch. Without async, Cot cannot fulfill its "full-stack web" promise.

```cot
// What Cot developers will want to write
async fn fetchUser(id: i64) User!Error {
    let response = await http.get("/api/users/{id}")
    return json.parse(User, response.body)
}

// Server-side
async fn handleRequest(req: Request) Response {
    let user = try await fetchUser(req.params.id)
    return Response.json(user)
}
```

**Why Wasm hurts:** Wasm has no stack switching. A function either runs to completion or traps. There's no way to suspend a Wasm function mid-execution, save its state, and resume later.

The [stack switching proposal](https://github.com/WebAssembly/stack-switching) is at Phase 2 (specification draft). It adds `suspend`, `resume`, and continuation types. But Phase 2 means years from standardization and universal deployment.

**Workarounds (all have serious costs):**

| Approach | How it works | Cost |
|----------|-------------|------|
| **CPS transform** | Rewrite every async function into continuation-passing style. Each `await` point splits the function into "before" and "after" closures. | 2-5x code size increase. Stack traces destroyed. Debugging impossible. Every function in the call chain must be transformed. |
| **Asyncify** | Emscripten's approach. Instrument all functions to save/restore their local state to linear memory at suspension points. | 30-50% code size overhead. 10-20% runtime overhead. Requires whole-program transformation. |
| **Event loop + callbacks** | Don't suspend at all. Use JavaScript-style callbacks or promises. No language-level async. | Callback hell. Loses the "write like TypeScript" promise. Users must manually manage async state. |
| **OS threads (native only)** | Use real threads on the native path. Each "async" task is a thread. | Only works on native. Heavy (1MB+ stack per thread). Not available on Wasm at all. |
| **Green threads** | Implement userspace scheduling with stack switching in linear memory. | Requires implementing a full scheduler. Stack copying is expensive. Fragile. |

**Impact on Cot:** Critical. This is potentially the hardest problem between 0.3 and 1.0.

**Recommendation:** This is where the IR split (discussed below) becomes most compelling. For 1.0:

- **Native path:** Use OS-level mechanisms. On native, async can be implemented with real non-blocking I/O (epoll/kqueue) and either threads or coroutines. The native AOT compiler can emit stack-switching code directly (save registers, swap stack pointer — this is how Go's goroutines work).
- **Wasm/browser path:** Use JavaScript's event loop. Wasm functions call out to JS `fetch()` / `setTimeout()` via imports. The async orchestration happens in JS glue code. Cot `async fn` compiles to a function that returns a Promise (via JS interop). This is how every Wasm framework handles async today (Yew, Leptos, etc.).
- **Wasm/WASI path:** Use WASI preview 2's async model (component model with `future` and `stream` types), or wait for stack switching.

The key insight: **async doesn't need to be a single mechanism across all targets.** The syntax is the same (`async fn`, `await`), but the lowering differs:

```
async fn fetch(url: string) Response!Error { ... }
        ↓
  ┌─────┴──────┐
  ↓             ↓
Native:       Wasm/Browser:
  epoll +       JS Promise interop
  coroutine     (extern returns Promise handle)
```

#### 3. Stack Introspection

**What it is:** Walking the call stack to inspect return addresses, local variables, or generate stack traces.

**Why it matters:** Error reporting (stack traces in error messages), debugging, profiling, and some GC algorithms.

**Why Wasm hurts:** Wasm's stack is not accessible to the program. You cannot read return addresses, walk frames, or inspect the call chain. The stack is managed by the Wasm runtime and is intentionally opaque (security sandboxing).

**Workaround:** Shadow stack — maintain a parallel stack in linear memory that records function entries/exits. Every function call pushes a frame descriptor; every return pops it.

```cot
// Compiler-inserted instrumentation
fn foo() {
    __shadow_push("foo", @src())  // compiler inserts
    defer __shadow_pop()          // compiler inserts
    // ... actual function body ...
}
```

**Impact on Cot:** Low-medium. Most users don't need programmatic stack access. But good error messages with stack traces are important for developer experience.

**Recommendation:** For 1.0, implement a debug-mode shadow stack that's compiled in when `--debug` is passed. Release builds omit it. Native builds can use real stack unwinding (DWARF info is already partially emitted). This is what Go does — `runtime.Callers()` works via special runtime support, not by walking the actual machine stack.

#### 4. Custom Calling Conventions

**What it is:** Choosing how arguments are passed between functions (which registers, what order, how many via stack).

**Why it matters:** Performance optimization. Some functions could be faster with non-standard conventions (e.g., passing extra args in registers, using callee-saved registers for hot values, returning multiple values in registers).

**Why Wasm hurts:** Wasm has exactly one calling convention: arguments are pushed onto the value stack, results are left on the value stack. There are no registers. The Wasm runtime (V8, Wasmtime) decides how to map this to the actual CPU.

**Impact on Cot:** Low for 1.0. Custom calling conventions are a micro-optimization. The native AOT path already gets standard C calling convention (which is highly optimized by decades of hardware co-design). This becomes relevant only when Cot is competing on benchmark performance against C/Rust, which is a post-1.0 concern.

**Recommendation:** Ignore for 1.0. If it matters later, the native path can implement custom conventions (the regalloc and ABI infrastructure already support this). Wasm path is stuck with Wasm's convention, which V8 optimizes well.

#### 5. SIMD Beyond 128-bit

**What it is:** Using wider vector registers (AVX-256, AVX-512, SVE) for data-parallel computation.

**Why Wasm hurts:** Wasm SIMD is fixed at 128-bit (`v128` type). ARM64 NEON is also 128-bit, so this matches. But x64 has AVX2 (256-bit) and AVX-512 (512-bit), and ARM64 SVE has variable-width vectors up to 2048-bit.

**Impact on Cot:** Very low. Cot's target audience (web developers) rarely writes SIMD code. Even 128-bit SIMD is niche for this audience.

**Recommendation:** Don't implement SIMD for 1.0. If needed later, it's a native-only feature (the CLIF IR can express wider operations; the Wasm path emits multiple v128 ops or scalar fallbacks).

#### 6. Precise GC / Tagged Pointers

**What it is:** A garbage collector that knows exactly which values on the stack and heap are pointers (vs integers that happen to look like addresses).

**Why Wasm hurts:** Wasm's linear memory is untyped bytes. The Wasm runtime doesn't know which i64 values are pointers. You can't implement a precise, moving GC without stack maps (which Wasm doesn't expose) or conservative scanning (which is slow and unreliable).

**Impact on Cot:** None. Cot uses ARC, not tracing GC. ARC doesn't need stack maps — it tracks ownership via explicit retain/release calls inserted by the compiler. This is one of the key architectural advantages of choosing ARC: it works perfectly within Wasm's constraints.

**However:** ARC has its own limitation — reference cycles. Without a cycle collector (which would need some form of tracing), cycles leak memory. This is the same problem Swift has.

**Recommendation for 1.0:** Document the cycle limitation. Provide `weak` references (like Swift's `weak var`) as an escape hatch. A cycle collector is a post-1.0 project.

```cot
struct Node {
    data: i64
    next: ?*Node         // strong reference (retains)
    parent: weak ?*Node  // weak reference (doesn't retain, becomes null when freed)
}
```

### Summary: The Wasm Limitation Spectrum (Wasm 3.0, released Sep 2025)

```
                    Matters for 1.0?
                    ↓
Tail calls         ─── SOLVED (Wasm 3.0: return_call standardized)
Exception handling ─── AVAILABLE (Wasm 3.0: try_table/throw, useful for defer interop)
Typed func refs    ─── AVAILABLE (Wasm 3.0: call_ref, faster closures)
Multiple memories  ─── AVAILABLE (Wasm 3.0: separate heap/stack/metadata)
64-bit memory      ─── AVAILABLE (Wasm 3.0: >4GB linear memory)
Async/coroutines   ─── STILL BLOCKING (stack switching NOT in 3.0)
Stack introspection── Low (shadow stack for debug mode)
Custom conventions ─── No (micro-optimization, post-1.0)
Wide SIMD          ─── No (not for target audience)
Precise GC         ─── No (ARC avoids this entirely)

Wasm 3.0 (Sep 2025) resolved most limitations. Only async/coroutines
remains as a true blocker — stack switching was not included in 3.0.
```

---

## Architecture Evolution: The IR Split

### When to Split

The Wasm-as-sole-IR architecture should evolve when **async** needs to work on native. Until then, the current pipeline works.

The trigger: when implementing `async fn` for the native path, the compiler needs to emit coroutine-style stack switching code. This cannot be expressed in Wasm opcodes. At that point, the native path needs its own lowering from SSA IR.

### The Split Architecture

```
                         Cot Source
                             │
                  ┌──────────▼──────────┐
                  │   FRONTEND           │
                  │   Scanner → Parser   │
                  │   → Checker → SSA IR │
                  └──────────┬──────────┘
                             │
                   Cot SSA IR (unified)
                             │
               ┌─────────────┼─────────────┐
               │                           │
    ┌──────────▼──────────┐     ┌──────────▼──────────┐
    │  lower_wasm.zig      │     │  lower_clif.zig     │
    │  (SSA → Wasm ops)    │     │  (SSA → CLIF ops)   │  ← NEW
    └──────────┬──────────┘     └──────────┬──────────┘
               │                           │
    ┌──────────▼──────────┐     ┌──────────▼──────────┐
    │  wasm/ package       │     │  CLIF IR             │
    │  (Wasm bytecode)     │     │  (already exists)    │
    └──────────┬──────────┘     └──────────┬──────────┘
               │                           │
     ┌─────────┼────────┐                  │
     │         │        │                  │
     ▼         ▼        ▼                  ▼
  Browser    WASI    Native*           MachInst → Native
                    (via parse-back)
```

**What changes:**
- A new `lower_clif.zig` translates SSA IR directly to CLIF IR
- The native path skips the Wasm round-trip (emit bytes → parse bytes → translate)
- Features that Wasm can't express (async, TCO) go through `lower_clif.zig` only
- The Wasm path remains for browser/WASI targets
- `lower_wasm.zig` continues to work exactly as it does today

**What stays the same:**
- The frontend (scanner, parser, checker) — unchanged
- The SSA IR — unchanged
- The CLIF IR, MachInst framework, regalloc, emission — all unchanged
- The Wasm backend — unchanged
- All existing tests — unchanged

### Migration Path

This is not a rewrite. It's an additive change:

1. **0.3 (now):** Keep current architecture. Add all language features that work through Wasm (traits, Map, string interp, pattern matching, I/O, stdlib). No IR split needed.

2. **0.4-0.5:** Add `lower_clif.zig` that handles the common cases (arithmetic, control flow, function calls, memory). Verify it produces identical native output to the Wasm parse-back path. Then add async support — native path uses `lower_clif.zig` with coroutine-style codegen, browser path uses JS Promise interop.

3. **0.6 → 1.0:** Stabilize, ecosystem, polish. The split is complete. Both paths are tested.

### Why Not Split Now?

The current architecture is simpler to maintain and reason about. Every feature goes through one path. Testing is straightforward. The Wasm parse-back adds ~5ms to native compilation but eliminates an entire category of "works on native but not Wasm" bugs.

Split when you need to, not before.

### Alternative: Extended Wasm (Custom Opcodes)

Instead of splitting the IR, extend the Wasm bytecode format with custom opcodes that only the native path understands.

```
Standard Wasm opcode space:
0x00-0xFF  — core instructions
0xFC xx    — saturating/bulk memory prefix
0xFD xx    — SIMD prefix
0xFE xx    — threads prefix

Cot extended opcodes:
0xFF 0x00  — cot.tail_call (func_idx)
0xFF 0x01  — cot.suspend
0xFF 0x02  — cot.resume
0xFF 0x03  — cot.stack_save
0xFF 0x04  — cot.stack_restore
0xFF 0x05  — cot.yield (value)
```

**Pros:**
- Minimal architectural change. The Wasm module format stays the same.
- `wasm_parser.zig` just handles extra opcodes.
- The translator maps them to CLIF operations.
- Browser path never emits them (or emits polyfill sequences).

**Cons:**
- "Extended Wasm" is a custom format. Debugging tools (wasm-tools, wabt) won't understand it.
- The Wasm is no longer portable to other runtimes.
- It's a conceptual hack — you're bending the format rather than using the right abstraction.

**Verdict:** Viable as a transitional step but not the long-term answer. The IR split is cleaner.

### Alternative: Custom Sections (Metadata Sideband)

Keep standard Wasm opcodes but embed extra information in custom sections that the native path reads.

```wasm
;; Standard code section — valid Wasm
(func $factorial (param i64 i64) (result i64)
  ;; standard loop-based implementation
)

;; Custom section — ignored by browsers
(custom "cot.tailcalls"
  ;; Tells native AOT: function $factorial has a tail call at offset 42
  ;; Replace the call+return with a jump
)
```

**Pros:**
- The Wasm remains 100% valid. Browsers, wabt, wasm-tools all work.
- The native path reads custom sections for optimization hints.
- Incrementally adoptable — add sections as needed.

**Cons:**
- The "real" semantics are split across two places (code + custom section).
- Can only annotate existing Wasm constructs, not add new semantics.
- For async/coroutines, you'd need the actual code in the custom section (at which point it's basically a second IR embedded in the Wasm file).

**Verdict:** Good for optimization hints (tail calls, inlining hints, ARC elision). Not sufficient for fundamentally new semantics (async).

### Recommended Approach: Pragmatic Hybrid

For 1.0, use a combination:

1. **Custom sections** for optimization hints (tail calls, ARC elision, inlining)
2. **IR split** for async (the only feature that truly can't go through Wasm)
3. **Standard Wasm** for everything else (which is 95% of the language)

This means the IR split is small and focused — `lower_clif.zig` only needs to handle async-related constructs initially. Everything else continues through the proven Wasm path.

---

## Versioning Philosophy

**Cot follows Zig's versioning model: versions mark architectural milestones, not feature checklists.**

Zig is over 10 years of development and still on 0.15. Each version represents a meaningful shift in capability or architecture. Features accumulate within a version until the next architectural boundary.

For Cot:
- **0.3** — Wasm-first compiler with full native AOT pipeline. Language features, standard library, type system completion, and I/O all land here. This is the "make the language real" version.
- **0.4** — Developer experience (LSP, formatter, test runner, error messages). This is the "make it pleasant to use" version.
- **0.5** — Async, concurrency, IR split if needed. This is the "make it production-capable" version.
- **0.6+** — Ecosystem (package manager, registry, cross-compilation). This is the "make it community-ready" version.
- **1.0** — Stable, documented, ready for other developers. Syntax frozen. Stability commitment.

**The current sprint target: all language features, type system, stdlib, and I/O within 0.3.**

---

## Feature Roadmap

### 0.3 Sprint: Language + Stdlib + I/O (Target: 1 week)

Everything below lands in 0.3. This is the pace of AI-assisted development — 14-20 dev-months of equivalent work was completed in 6 weeks to reach the current state. The next week targets another 8-10 dev-months of equivalent work.

#### Wave 1: Collections and Strings (Days 1-2)

| # | Feature | Description | Depends On |
|---|---------|-------------|------------|
| 1 | `Map(K,V)` | Hash map: set/get/has/delete/keys/values. FNV-1a hash. Open addressing. | Generics (done) |
| 2 | `Set(T)` | Built on Map(K,V): add/remove/has/union/intersect | Map(K,V) |
| 3 | String interpolation | `"Hello, {name}! You are {age} years old."` | Parser + lowerer |
| 4 | `StringBuilder` | Efficient append-based string building | List(u8) |
| 5 | `@print` / `@println` | Output: extern fn write on native, console.log on Wasm | Extern fn |
| 6 | String escape sequences | `\t`, `\r`, `\0`, `\xFF`, `\u{XXXX}` | Scanner |
| 7 | Multiline strings | Triple-quote `"""..."""` or backtick strings | Scanner + parser |
| 8 | Slice params complete | `fn sum(items: []i64) i64` on both targets | Already started |

#### Wave 2: Type System Completion (Days 2-4)

| # | Feature | Description | Depends On |
|---|---------|-------------|------------|
| 9 | Traits / interfaces | `trait Hashable { fn hash(self) u64 }`, `impl Hashable for string` | Generics (done) |
| 10 | Trait bounds on generics | `fn sort(T: Comparable)(list: *List(T))` | Traits |
| 11 | `for key, value in map` | Map iteration via trait-based iterator protocol | Traits, Map |
| 12 | `match` expressions | Full pattern matching (nested patterns, guards, bindings) | Switch (done) |
| 13 | Tuple types | `(i64, string)` — anonymous product types | Parser + checker |
| 14 | Multiple return values | `fn divmod(a, b: i64) (i64, i64)` — sugar for tuples | Tuples |
| 15 | `weak` references | `weak ?*T` — ARC cycle breaker (Swift pattern) | ARC (done) |
| 16 | `const` evaluation | Compile-time known values (limited comptime for sizes, indices) | Checker |

#### Wave 3: I/O and Host Interop (Days 4-6)

| # | Feature | Description | Depends On |
|---|---------|-------------|------------|
| 17 | Extern fn on native | Complete pipeline: Wasm imports → undefined symbols → linker | Wasm parser |
| 18 | Extern fn on Wasm | Generate proper import section entries | Wasm link |
| 19 | `std/fs` | File I/O: open, read, write, close, readFile, writeFile | Extern fn |
| 20 | `std/os` | Process args, environment variables, exit | Extern fn |
| 21 | `std/fmt` | `format("Hello, {s}! Count: {d}", name, count)` | String interp |
| 22 | `std/math` | sqrt, pow, sin, cos, floor, ceil, abs, min, max | Wasm float ops |
| 23 | `std/json` | JSON parse/serialize using Map + List + tagged unions | Map, traits |
| 24 | Browser DOM API | `std/dom` — getElementById, addEventListener, setInnerHTML | Extern Wasm |
| 25 | WASI support | Target WASI preview 1 for server-side Wasm | Extern Wasm |

#### Wave 4: Test Parity (Day 7)

| # | Feature | Description | Depends On |
|---|---------|-------------|------------|
| 26 | Test runner | `test "name" { ... }` blocks, `cot test` command | Parser |
| 27 | Port expression tests | ~144 edge cases from bootstrap-0.2 | Test runner |
| 28 | Port function tests | ~99 edge cases from bootstrap-0.2 | Test runner |
| 29 | Port control flow tests | ~86 edge cases from bootstrap-0.2 | Test runner |
| 30 | Native parity | Globals, imports, extern on native AOT | Extern native |

### 0.4: Developer Experience

| Feature | Description |
|---------|-------------|
| Error messages | Source location, underline the problem, suggest fixes |
| LSP server | Autocomplete, go-to-definition, hover types, error squiggles |
| Formatter | `cot fmt` — auto-format source files |
| Build system | `cot build` with project manifest (cot.toml) |
| Syntax highlighting | TextMate grammar for VS Code, tree-sitter grammar |
| REPL | `cot repl` — interactive evaluation |

### 0.5: Async and Concurrency

| Feature | Description |
|---------|-------------|
| `async fn` / `await` | Language-level async |
| Native event loop | epoll (Linux) / kqueue (macOS) |
| Browser async | JS Promise interop |
| `std/net` | TCP/HTTP server and client |
| IR split | `lower_clif.zig` for native-only features (if needed for async) |

### 0.6+: Ecosystem

| Feature | Description |
|---------|-------------|
| Package manager | `cot add`, `cot remove`, dependency resolution |
| Package registry | cot.land — publish, search, download |
| Cross-compilation | `cot build --target=linux-x64` from macOS |
| Multi-file module system | Beyond single-file imports |

### 1.0: Public Release

| Feature | Description |
|---------|-------------|
| Language specification | Formal spec, syntax frozen |
| Language guide | "Learn Cot in Y Minutes", tutorials, cookbook |
| Standard library docs | Full API documentation |
| Example applications | TODO app, chat server, blog engine |
| cot.dev website | Documentation site + playground |
| Stability commitment | Semver, deprecation policy |

---

## Effort Estimation

### The AI-Assisted Development Rate

| Period | Calendar Time | Equivalent Dev-Months | Rate |
|--------|--------------|----------------------|------|
| 0.1 → 0.3 (completed) | ~6 weeks | 14-20 months | ~3 dev-months per calendar week |
| 0.3 sprint (target) | 1 week | 8-10 months | Same rate, focused on language features |
| 0.4 (DX) | 2-3 weeks | 4-6 months | Lower AI leverage (design-heavy) |
| 0.5 (async) | 2-3 weeks | 4-6 months | High AI leverage (compiler work) |
| 0.6+ (ecosystem) | 3-4 weeks | 4-6 months | Mixed (registry is infra, not code) |
| 1.0 (polish) | 2-3 weeks | 3-4 months | Low AI leverage (writing, design) |

**Realistic calendar estimate: 0.3 to 1.0 in 3-4 months with sustained AI-assisted development.**

The bottleneck is not code generation — it's design decisions, user testing, and documentation. The compiler features (traits, async, pattern matching) will go fast. The ecosystem (LSP, package manager, website) requires more human judgment.

### Critical Path

```
Map(K,V) → Traits → std/json, std/net APIs → async → web server example → 1.0
   ↓
 Set(T)
   ↓
String interp → std/fmt → developer experience
```

**Map(K,V) and traits are the immediate critical-path items. Everything else flows from them.**

---

## Competitive Positioning at 1.0

### The Landscape in 2027

By the time Cot 1.0 ships, the competitive landscape will include:

| Language | Strength | Weakness Cot exploits |
|----------|----------|----------------------|
| TypeScript | Ecosystem, familiarity | Performance, no native compilation |
| Go | Simplicity, concurrency | No browser target, GC pauses, no generics expressiveness |
| Rust | Performance, safety | Complexity, learning curve, borrow checker friction |
| Swift | ARC, developer experience | No Wasm, Apple-centric, no server story |
| Zig | Performance, simplicity | No GC/ARC, manual memory, niche audience |
| Kotlin/Wasm | JetBrains backing | GC, JVM heritage, not systems-level |

### Cot's Unique Position

No other language offers all of:
1. **ARC memory management** (no GC pauses, no manual memory, no borrow checker)
2. **Wasm-first** (runs in browser natively, not via emulation)
3. **Native AOT** (competitive native performance when you need it)
4. **Full-stack** (same language for browser and server)
5. **Modern syntax** (Zig-inspired but simpler, no historical baggage)
6. **Low learning curve** (if you know TypeScript or Go, you can write Cot)

The closest competitor is Swift, which has ARC and great developer experience but has no Wasm story and is Apple-centric. Cot is "Swift for the web."

---

## Open Questions for 1.0

These decisions should be made before 1.0 but don't need to be decided now:

1. **Async model:** Coroutines (Go-style), async/await (JS/Rust-style), or both?
2. **Module system:** File-based (Go-style) or explicit exports (Rust/Zig-style)?
3. **Error handling:** Is `!T` sufficient, or do typed error hierarchies need support?
4. **Concurrency model:** Shared memory + mutexes, message passing, or actors?
5. **FFI beyond C:** Should Cot interop with JS npm packages? Rust crates? Go modules?
6. **Standard library scope:** Minimal (like Go's stdlib) or batteries-included (like Python)?
7. **Versioning and editions:** Rust-style editions for breaking changes?
8. **Governance:** BDFL, RFC process, or foundation?

---

## Summary

Cot 0.3 has built the hard infrastructure — a complete compiler pipeline with dual-target output, ARC memory management, generics, closures, and 853 passing tests. The road to 1.0 is:

1. **0.3 (this week):** Language features, type system, stdlib, I/O — make Cot a real language
2. **0.4:** Developer experience — make it pleasant to use
3. **0.5:** Async + IR split — make it production-capable
4. **0.6+:** Ecosystem — make it community-ready
5. **1.0:** Polish, docs, stability — make it public

The Wasm-as-IR architecture works for everything in 0.3. The IR split happens in 0.5 when async forces it. That's a future concern.

The demonstrated rate of AI-assisted development (14-20 dev-months equivalent in 6 weeks) means the language features, stdlib, and I/O can land in a single focused week. The compiler infrastructure is ready — it's now about exercising it.

**The compiler is ready. Now build the language around it.**
