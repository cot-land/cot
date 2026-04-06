# ac Language Syntax Reference

**ac = agentic cot** — syntax designed by AI agents

**Version:** 0.7 (Phase 7b — Generics + Traits + Structural Dispatch)
**Updated as features are implemented. Each section lists the feature number from FEATURES.md.**

---

## Design Principle

ac's syntax was designed by AI agents. The rule: if an LLM can predict the syntax, that IS the syntax. Every construct uses the most familiar pattern across C-style languages — the pattern with the strongest signal in training data. The result is Rust's expressiveness with Go's cleanliness.

ac exists to dogfood the COT compiler toolkit. It is not the product — CIR is the product. ac exercises CIR until real frontends (Zig, TypeScript) are added. But its agentic design means it's genuinely easy for AI-assisted development.

---

## Basics

No semicolons. Newlines terminate statements (Go-style automatic insertion).
Line comments: `// comment`

## Testing (Zig pattern)

```ac
test "addition" {
    assert(add(19, 23) == 42)
    assert(1 + 1 == 2)
}
```

- `test "name" { body }` — Zig-style test blocks (compiled by `cot test file.ac`)
- `assert(expr)` — trap on false (cir.condbr + cir.trap)
- Test blocks become void functions; a generated main calls each one
- Exit 0 = all passed, trap = assertion failure

## Functions (#003, #004)

```ac
fn add(a: i32, b: i32) -> i32 {
    return a + b
}

fn main() -> i32 {
    return add(19, 23)
}
```

- `fn` keyword
- Parameters: `name: type`
- Return type: `-> type` (omit for void)
- Body in `{}`

## Literals (#001, #006)

```ac
42          // i32 integer
1_000_000   // underscores allowed in numbers
3.14        // f64 float
true        // bool
false       // bool
"hello"     // string
'a'         // char
null        // null value
```

## Arithmetic (#002, #005, #008)

```ac
a + b       // addition
a - b       // subtraction
a * b       // multiplication
a / b       // division
a % b       // remainder
-x          // negation (cir.neg)
```

## Comparison (#007)

```ac
a == b      // equal
a != b      // not equal
a < b       // less than
a <= b      // less or equal
a > b       // greater than
a >= b      // greater or equal
```

## Bitwise (#009, #010)

```ac
a & b       // bitwise and
a | b       // bitwise or
a ^ b       // bitwise xor
~a          // bitwise not
a << b      // shift left
a >> b      // shift right
```

## Logical

```ac
a && b      // logical and (short-circuit)
a || b      // logical or (short-circuit)
!a          // logical not
```

---

*Sections below are planned — syntax will be documented as each feature is implemented.*

## Variables (#011, #012, #013, #014)

```ac
let x: i32 = 42        // immutable binding (✓ #011)
var count: i32 = 0      // mutable binding (✓ #012)
count = count + 1       // assignment (✓ #013)
count += 1              // compound assignment (✓ #014) — also -=, *=, /=, %=
```

## Control Flow (#015-#019)

```ac
if x > 0 {             // (✓ #015) no parens — Go/Rust pattern
    // ...
} else {
    // ...
}

let x = if a > b { a } else { b }  // (✓ #016) if-expression → cir.select

while x < 10 {             // (✓ #017) no parens
    x += 1
}

for i in 0..10 {            // (✓ #019) desugars to while
    // ...
}
```

## Types (#021-#023)

```ac
i8  i16  i32  i64      // signed integers
u8  u16  u32  u64      // unsigned integers
f32  f64                // floats
bool                    // boolean
void                    // no value
string                  // UTF-8 string (slice of u8)
```

## Type Casts (#023)

```ac
x as i64               // integer widening (cir.extsi)
x as i32               // integer narrowing (cir.trunci)
x as f64               // int to float (cir.sitofp)
x as i32               // float to int (cir.fptosi)
x as f32               // float narrowing (cir.truncf)
x as f64               // float widening (cir.extf)
```

- `as` is a postfix operator with higher precedence than all binary ops
- Each cast direction maps to a distinct CIR op (Arith dialect pattern)
- Frontends determine the specific cast op; Sema also inserts implicit casts at call boundaries

## Structs (#024-#027)

```ac
struct Point {              // (✓ #024) named aggregate type
    x: i32
    y: i32
}

fn takes_point(p: Point) -> i32 {   // struct as parameter type
    return 0
}

let p = Point { x: 1, y: 2 }       // (#025) struct construction
let x = p.x                         // (#026) field access
```

- Struct fields: `name: type` per line (newline-separated, no commas needed)
- Struct types appear in CIR as `!cir.struct<"Point", x: i32, y: i32>`
- Field names stored in the type (FIR pattern) — enables name-based field access

## Arrays and Slices (#028-#040)

```ac
let arr: [4]i32 = [1, 2, 3, 4]
let elem = arr[0]

let s: []i32 = arr[1..3]
let len = s.len
```

## Pointers (#031-#034)

```ac
let p: *i32 = &x
let val = *p
```

## Optionals (#041-#044)

```ac
let x: ?i32 = 42
let y: ?i32 = null

if x |val| {
    // val is i32
}
```

## Error Handling (#045-#048)

```ac
fn read() -> !string {
    // returns error or string
}

let data = try read()

read() catch |e| {
    // handle error
}
```

## Enums and Match (#049-#054)

```ac
enum Color {
    Red
    Green
    Blue
}

match color {
    Color.Red => // ...
    Color.Green => // ...
    Color.Blue => // ...
}
```

## Generics (#055)

```ac
fn identity[T](x: T) -> T {         // generic function with type param
    return x
}

let r = identity[i32](42)            // explicit type arg at call site
```

- `[T]` after function name declares type parameters
- Call site: `func[ConcreteType](args)` — type argument in brackets
- CIR: emits `!cir.type_param<"T">` + `cir.generic_apply`
- GenericSpecializer monomorphizes before lowering

## Traits (#057-#059)

```ac
trait Summable {                      // (✓ #057) trait declaration
    fn sum(self) -> i32               // method signature — self is receiver
}

impl Summable for Point {             // (✓ #058) trait conformance
    fn sum(self) -> i32 {             // concrete implementation
        return self.x + self.y
    }
}

fn apply[T: Summable](val: T) -> i32 { // (✓ #059) trait-bounded generic
    return val.sum()                    // → cir.trait_call (named dispatch)
}
```

- `trait Name { fn method(self) -> Type }` — declares protocol with method signatures
- `impl Trait for Type { fn method(self) -> Type { body } }` — conformance
- `[T: Trait]` — generic with trait bound
- `self` in trait methods: bare keyword (no type annotation in trait/impl)
- `self: Type` in standalone functions: explicit type annotation
- Emits `cir.witness_table` + `cir.trait_call` (resolved by specializer)

## Structural Dispatch (Duck Typing)

```ac
fn apply[T](val: T) -> i32 {         // generic WITHOUT trait bound
    return val.sum()                   // → cir.method_call (duck dispatch)
}
```

- When T has no trait bound, method calls use structural dispatch
- CIR: emits `cir.method_call "sum"` — resolved by name lookup on concrete type
- Reference: Zig comptime duck typing, Go structural interfaces

## Memory (ARC) (#061-#065)

```ac
let p = new Point { x: 1, y: 2 }   // heap allocated, ARC managed
// retain/release inserted automatically by compiler pass
```

## Concurrency (#066-#070)

```ac
async fn fetch(url: string) -> string {
    // ...
}

let result = await fetch("https://example.com")

spawn process(data)
```

## Comptime (#071-#075)

```ac
comptime {
    // evaluated at compile time
}

fn Vec(comptime T: type) -> type {
    // ...
}
```
