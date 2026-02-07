# Traits / Interfaces Design

**Date:** February 2026
**Status:** Not implemented
**Priority:** MEDIUM (unblocks sort, contains, generic algorithms over collections)
**Estimated effort:** Large (1-2 days)

---

## Motivation

Cot has generics (`fn max(T)(a: T, b: T) T`) and impl blocks (`impl List(T) { ... }`).
But there's no way to constrain a type parameter:

```cot
// This works today:
fn max(T)(a: T, b: T) T {
    if a > b { return a }    // Assumes T supports >
    return b
}

// But what if T is a struct? Compilation succeeds, then fails at monomorphization.
// No way to say "T must support comparison".
```

Traits solve this:

```cot
trait Comparable {
    fn lessThan(self: *Self, other: *Self) bool
}

fn sort(T: Comparable)(items: []T) void {
    // T is guaranteed to have lessThan()
}
```

### What Traits Enable

| Feature | Without Traits | With Traits |
|---------|---------------|-------------|
| `List.sort()` | Can't — no comparison protocol | `fn sort(self) where T: Comparable` |
| `List.contains(value)` | Can't — no equality protocol | `fn contains(self, v: T) bool where T: Eq` |
| `List.indexOf(value)` | Can't — no equality | `fn indexOf(self, v: T) ?i64 where T: Eq` |
| `HashMap(K,V)` | Can't — no hash protocol | `K: Hash + Eq` |
| `print(value)` | Can't — no string protocol | `T: Display` |
| Generic algorithms | Only on primitives | On any conforming type |

---

## Design Decisions

### Decision 1: Monomorphized Traits (Zig/Rust) vs Runtime Dispatch (Go)

| Approach | How It Works | Performance | Complexity |
|----------|-------------|-------------|------------|
| **Monomorphized** (Zig/Rust) | Compiler generates specialized code per concrete type | Zero overhead | Lower (no runtime tables) |
| **Runtime dispatch** (Go) | Interface values carry itab + data pointer, methods resolved at runtime | vtable indirection | Higher (runtime type info) |

**Decision: Monomorphized traits.**

Reasons:
1. Cot already uses monomorphization for generics — traits are a natural extension
2. No runtime overhead (important for Wasm where indirect calls are expensive)
3. Simpler implementation (no itab generation, no runtime type descriptors)
4. Matches Zig's comptime interface pattern and Rust's monomorphization

### Decision 2: Syntax

**Option A: Zig-style (duck typing with comptime checks)**
```cot
fn sort(T)(items: []T) void {
    // T must have a lessThan method — checked at monomorphization time
    // No explicit trait declaration needed
}
```

**Option B: Rust-style (explicit trait declarations + bounds)**
```cot
trait Eq {
    fn eq(self: *Self, other: *Self) bool
}

trait Ord: Eq {
    fn cmp(self: *Self, other: *Self) i64
}

fn sort(T: Ord)(items: []T) void { ... }

impl Ord for Point {
    fn cmp(self: *Point, other: *Point) i64 {
        return self.x - other.x
    }
}
```

**Option C: Go-style (interfaces with implicit satisfaction)**
```cot
interface Stringer {
    fn toString(self: *Self) string
}

// Any type with a toString method satisfies Stringer
// No explicit "impl Stringer for X" needed
```

**Decision: Option B (Rust-style) with one simplification.**

Reasons:
- Explicit is better than implicit for a compiled language
- Trait bounds give clear error messages ("Point does not implement Ord")
- `impl Trait for Type` already aligns with Cot's existing `impl Type { ... }` syntax
- Zig's duck typing gives bad error messages (fails deep in monomorphized code)
- Go's implicit satisfaction is hard to implement correctly with monomorphization

**Simplification:** No trait inheritance initially. `trait Ord: Eq` comes later.

### Decision 3: Self Type

In trait methods, `Self` refers to the implementing type:

```cot
trait Eq {
    fn eq(self: *Self, other: *Self) bool
}

impl Eq for i64 {
    fn eq(self: *i64, other: *i64) bool {
        return self.* == other.*
    }
}
```

For primitive types (`i64`, `i32`, `f64`), we need `impl Trait for PrimitiveType`.
This requires the checker to accept `impl` blocks for non-struct types.

### Decision 4: Built-in Traits

| Trait | Methods | Used By |
|-------|---------|---------|
| `Eq` | `fn eq(self, other) bool` | `contains`, `indexOf`, `HashMap` |
| `Ord` | `fn cmp(self, other) i64` | `sort`, `min`, `max`, `binarySearch` |
| `Hash` | `fn hash(self) i64` | `HashMap`, `HashSet` |
| `Display` | `fn toString(self) string` | `print`, string interpolation |
| `Clone` | `fn clone(self) Self` | Deep copy semantics |

**Phase 1:** `Eq` and `Ord` only. These unblock `sort`, `contains`, `indexOf`.
**Phase 2:** `Hash` (unblocks HashMap). `Display` (unblocks print).
**Phase 3:** `Clone` and custom traits.

---

## Implementation Plan

### Phase 1: Trait Definitions + impl Trait for Type

#### 1.1 Scanner (`compiler/frontend/scanner.zig`)

Add `trait` keyword:

```zig
.kw_trait => "trait",
```

#### 1.2 Parser (`compiler/frontend/parser.zig`)

Parse trait declarations:

```
trait_decl = "trait" IDENT "{" trait_method* "}"
trait_method = "fn" IDENT "(" params ")" return_type
```

AST node:
```zig
TraitDecl = struct {
    name: TokenIndex,
    methods: []const TraitMethodDecl,
};

TraitMethodDecl = struct {
    name: TokenIndex,
    params: []const ParamDecl,  // includes Self
    return_type: ?NodeIndex,
};
```

Parse `impl Trait for Type`:

```
impl_trait = "impl" IDENT "for" type_expr "{" method_decl* "}"
```

AST node:
```zig
ImplTraitBlock = struct {
    trait_name: TokenIndex,
    target_type: NodeIndex,
    methods: []const NodeIndex,
};
```

#### 1.3 Checker (`compiler/frontend/checker.zig`)

**Trait registration:**
- Store trait definitions in a `traits: StringHashMap(TraitInfo)` map
- `TraitInfo` contains the list of required method signatures

**impl Trait for Type validation:**
- Look up the trait
- Verify all required methods are provided
- Verify method signatures match (substituting `Self` for the concrete type)
- Store the implementation in a `trait_impls: HashMap(TraitName + TypeIndex, ImplInfo)` map

**Trait bounds on generics:**
```cot
fn sort(T: Ord)(items: []T) void { ... }
```

When `sort(Point)` is instantiated:
1. Look up `Ord` trait
2. Check if `impl Ord for Point` exists
3. If not: error "Point does not implement Ord"
4. If yes: proceed with monomorphization

#### 1.4 Lowerer (`compiler/frontend/lower.zig`)

**Monomorphization of trait methods:**

When `sort(Point)` calls `a.cmp(b)`:
1. Look up `impl Ord for Point`
2. Find the concrete `cmp` method
3. Emit a direct call to `Point_cmp` (the concrete implementation)

No virtual dispatch. No function pointers. Just direct calls to concrete methods.
This is identical to how generic impl methods already work.

#### 1.5 Wasm + Native Backends

No changes. Trait methods become regular function calls after monomorphization.

### Phase 2: Built-in Eq + Ord for Primitives

Provide built-in implementations for primitive types:

```cot
// Compiler-provided, not in user source
impl Eq for i64 {
    fn eq(self: *i64, other: *i64) bool { return self.* == other.* }
}
impl Ord for i64 {
    fn cmp(self: *i64, other: *i64) i64 {
        if self.* < other.* { return -1 }
        if self.* > other.* { return 1 }
        return 0
    }
}
// Same for i32, i8, u8, u16, u32, u64, f32, f64
```

These can be:
- Compiler-generated during checker initialization (cleaner)
- Provided as a standard library prelude file (simpler)

### Phase 3: Trait-Bounded List Methods

With Eq and Ord traits, List(T) gains:

```cot
impl List(T) {
    fn contains(self: *List(T), value: T) bool where T: Eq {
        var i: i64 = 0
        while i < self.count {
            let elem = self.get(i)
            if elem.eq(value) { return true }
            i = i + 1
        }
        return false
    }

    fn sort(self: *List(T)) void where T: Ord {
        // Insertion sort (simple, correct)
        var i: i64 = 1
        while i < self.count {
            let key = self.get(i)
            var j = i - 1
            while j >= 0 {
                let elem = self.get(j)
                if elem.cmp(key) <= 0 { break }
                self.set(j + 1, elem)
                j = j - 1
            }
            self.set(j + 1, key)
            i = i + 1
        }
    }
}
```

---

## Syntax Summary

```cot
// Define a trait
trait Eq {
    fn eq(self: *Self, other: *Self) bool
}

// Implement a trait for a type
impl Eq for Point {
    fn eq(self: *Point, other: *Point) bool {
        return self.x == other.x
    }
}

// Use trait bounds on generic functions
fn contains(T: Eq)(items: []T, target: T) bool {
    var i: i64 = 0
    while i < items.len {
        if items[i].eq(target) { return true }
        i = i + 1
    }
    return false
}

// Use trait bounds on generic impl methods
impl List(T) {
    fn sort(self: *List(T)) void where T: Ord {
        // ...
    }
}
```

---

## Test Plan

### Phase 1: Trait Definition + Impl

```cot
trait Greet {
    fn greet(self: *Self) i64
}

struct Dog { age: i64 }

impl Greet for Dog {
    fn greet(self: *Dog) i64 {
        return self.age
    }
}

fn test_trait_basic() i64 {
    var d: Dog = Dog { .age = 5 }
    if d.greet() != 5 { return 1 }
    return 0
}
```

### Phase 2: Trait Bounds

```cot
trait Eq {
    fn eq(self: *Self, other: *Self) bool
}

impl Eq for i64 {
    fn eq(self: *i64, other: *i64) bool {
        return self.* == other.*
    }
}

fn findFirst(T: Eq)(items: []T, target: T) i64 {
    var i: i64 = 0
    while i < items.len {
        if items[i].eq(target) { return i }
        i = i + 1
    }
    return -1
}

fn test_trait_bounds() i64 {
    var arr = [10, 20, 30]
    let idx = findFirst(i64)(arr[0:3], 20)
    if idx != 1 { return 1 }
    return 0
}
```

### Phase 3: List.sort

```cot
trait Ord {
    fn cmp(self: *Self, other: *Self) i64
}

impl Ord for i64 {
    fn cmp(self: *i64, other: *i64) i64 {
        if self.* < other.* { return -1 }
        if self.* > other.* { return 1 }
        return 0
    }
}

fn test_list_sort() i64 {
    var list: List(i64) = undefined
    list.items = 0
    list.count = 0
    list.capacity = 0
    list.append(30)
    list.append(10)
    list.append(20)
    list.sort()
    if list.get(0) != 10 { return 1 }
    if list.get(1) != 20 { return 2 }
    if list.get(2) != 30 { return 3 }
    return 0
}
```

---

## Files to Modify

| File | Change | Effort |
|------|--------|--------|
| `compiler/frontend/scanner.zig` | Add `trait` keyword | 1 line |
| `compiler/frontend/token.zig` | Add `kw_trait` token | 1 line |
| `compiler/frontend/ast.zig` | Add `TraitDecl`, `ImplTraitBlock` AST nodes | ~15 lines |
| `compiler/frontend/parser.zig` | Parse `trait { ... }` and `impl Trait for Type { ... }` | ~60 lines |
| `compiler/frontend/checker.zig` | Trait registration, impl validation, trait bounds checking | ~100 lines |
| `compiler/frontend/lower.zig` | Resolve trait method calls to concrete implementations | ~30 lines |
| `compiler/frontend/types.zig` | Add trait type info if needed | ~10 lines |
| Test files | E2E tests | ~100 lines |

**Total: ~220 lines of compiler code + ~100 lines of tests**

This is the largest feature but the most impactful. Without traits, the standard library
is limited to operations on primitives. With traits, any user-defined type can participate
in generic algorithms.

---

## Risks

| Risk | Mitigation |
|------|-----------|
| `impl Trait for PrimitiveType` requires checker changes for non-struct impl | Extend existing impl block handling |
| `Self` type substitution in trait methods | Reuse existing type_substitution from generics |
| Method resolution order (impl block methods vs trait methods) | Trait methods are only accessible via trait bounds, not ambient |
| Orphan rules (implementing foreign traits for foreign types) | Don't enforce initially — Cot is single-file for now |
| Trait inheritance (`trait Ord: Eq`) | Defer to Phase 2 — not needed for initial sort/contains |
| Where clauses on impl methods | Parse as constraint on the impl's type param |

---

## Alternatives Considered

### Duck Typing (Zig approach)

```cot
fn sort(T)(items: []T) void {
    // Just use T.cmp() — fails at monomorphization if T doesn't have cmp
}
```

**Rejected because:**
- Error messages are terrible ("unknown method cmp on type Point" deep in generic code)
- No documentation of what T needs to support
- No IDE completion / tooling support

### Structural Interfaces (Go approach)

```cot
interface Stringer {
    fn toString(self) string
}
// Any type with toString() implicitly satisfies Stringer
```

**Rejected because:**
- Requires runtime type info (itab) for interface values
- Implicit satisfaction is hard to reason about
- Doesn't compose well with monomorphization

### Type Classes (Haskell approach)

Too complex for Cot's design goals. Haskell-style type classes involve
higher-kinded types, instance resolution, and coherence checking.
