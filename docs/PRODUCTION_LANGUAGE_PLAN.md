# Cot: From Test Harness to Production Language

## Status: Phase 1 Complete (Feb 2026)

Cot now works as a language. A developer can write multi-file programs, import generics from stdlib, produce output, and run tests — all from the CLI.

### What a developer sees today

```bash
$ cat app.cot
import "std/list"

fn main() i64 {
    var nums: List(i64) = .{}
    nums.append(10)
    nums.append(20)
    nums.append(30)
    println(nums.get(0) + nums.get(1) + nums.get(2))
    nums.free()
    return 0
}

$ cot run app.cot
60
```

```bash
$ cat math_test.cot
test "addition" { @assert_eq(2 + 2, 4) }
test "negative" { @assert_eq(-3 + 3, 0) }

$ cot test math_test.cot
2 passed
```

---

## What Was Fixed (Phase 1 — Complete)

### 1A. Cross-file generic imports

**Was:** `checker.zig` stored generic registrations per-instance. Generic types from file A were invisible to file B.

**Fix:** `SharedGenericContext` holds all generic maps shared across checkers. Each checker has its own `expr_types` (to avoid NodeIndex collisions across ASTs). Generic instance symbols are stored in `global_scope`. The lowerer's `lowerGenericFnInstance` does tree-swap + fresh expr_types for cross-file methods.

### 1B. stdlib/list.cot

Extracted from test files into `stdlib/list.cot`. Works via `import "std/list"`.

### 1C. print/println/eprint/eprintln

Implemented as runtime functions with native syscalls. `print` and `println` write to stdout, `eprint` and `eprintln` write to stderr. Integer-to-string conversion happens in generated Wasm runtime code.

### 1D. Stdlib discovery

`import "std/list"` resolves via executable-relative path lookup. Works in both development and installed contexts.

### 2A. CLI subcommands

```bash
cot build app.cot          # compile to ./app
cot build app.cot -o myapp # compile to ./myapp
cot run app.cot            # compile + run + cleanup
cot test app_test.cot      # compile + run inline tests
cot version                # cot 0.3.1 (arm64-macos)
cot help                   # usage info
```

### 2B. Test framework

Inline test blocks with per-test error-union isolation:

```cot
test "name" {
    @assert(condition)
    @assert_eq(actual, expected)
}
```

Summary output: `N passed, M failed`. Wired into `zig build test` for CI. ~812 tests converted to inline format.

### 2C. LSP server

Basic LSP with diagnostics, hover, goto definition, and document symbols.

---

## What Remains (Phase 2+)

### Collections

| What | Status | Depends On |
|------|--------|------------|
| Map(K,V) | Not started | Hash function, `Hash + Eq` trait impls |
| Set(T) | Not started | Map(K,V) |

**Reference:** Go `runtime/map.go` (bucket-based hash map), Zig `std/hash_map.zig`

### Type System

| What | Status |
|------|--------|
| Trait bounds on generics (`where T: Trait`) | **Done** — working with monomorphized dispatch |
| String interpolation (`"Hello, {name}"`) | Not started |
| Iterator protocol (`for x in collection`) | Not started |
| Pattern matching (`match` expressions) | Not started |
| Multiple return values | Not started |
| `weak` references (ARC cycle breaker) | Not started |

### I/O and Standard Library

| What | Status |
|------|--------|
| `std/fs` — file I/O | Not started |
| `std/os` — process args, env vars | Not started |
| `std/fmt` — string formatting | Not started |
| `std/math` — math functions | Not started |
| `std/json` — JSON parse/serialize | Not started |
| `std/dom` — browser DOM API | Not started |
| WASI target (`--target=wasm32-wasi`) | Not started |

### Developer Experience

| What | Status |
|------|--------|
| Project manifest (cot.toml) | Not started |
| `cot fmt` — auto-formatter | Not started |
| Syntax highlighting (VS Code, tree-sitter) | Not started |
| Error messages with source locations | Partial |

---

## Known Compiler Bugs

| Bug | Impact | Root Cause |
|-----|--------|------------|
| Non-void sibling method calls in generic impl fail on native | Forces inlining workarounds | Unknown codegen issue in monomorphized method dispatch |
| `_deinit` suffix hijacked by ARC scanner | Can't name methods `deinit` | `driver.zig` scans ALL function names, not just struct-level ones |
| `sort()` in generic impl produces wrong results on native | sort() doesn't work | Unknown — likely codegen issue with `var` mutation in nested loops inside generic impl |

---

## Implementation Order (Remaining)

| Step | What | Unblocks | Effort |
|------|------|----------|--------|
| **1** | Map(K,V) in stdlib | Real applications | Large — needs hash function |
| **3** | String interpolation | Readable output | Medium |
| **4** | `std/fs` — file I/O | Real applications | Medium — syscall wrappers |
| **5** | Iterator protocol | Ergonomic loops | Medium |
| **6** | `std/os` — args, env | CLI tools | Small |

---

## Reference Architecture

| Component | Copy From | Why |
|-----------|-----------|-----|
| Map(K,V) | Go `runtime/map.go` | Bucket-based hash map |
| String interpolation | Zig `std.fmt` | Comptime format parsing |
| File I/O | Go `os/file.go` + WASI `fd_read`/`fd_write` | Cross-target I/O model |
| Iterator protocol | Zig `for` over slices | Simple interface, no allocations |
| Pattern matching | Rust `match` | Exhaustiveness checking |

---

## What Success Looks Like (Next Milestone)

A developer creates a project:

```cot
import "std/list"
import "std/map"

fn main() i64 {
    var scores: Map([]u8, i64) = .{}
    scores.set("alice", 95)
    scores.set("bob", 87)

    var names: List([]u8) = scores.keys()
    var i: i64 = 0
    while i < names.len() {
        println("{}: {}", names.get(i), scores.get(names.get(i)))
        i = i + 1
    }

    names.free()
    scores.free()
    return 0
}
```

```bash
$ cot run app.cot
alice: 95
bob: 87
```

That's the next bar. We need Map(K,V), trait bounds, and string interpolation to get there.
