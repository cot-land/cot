# ac Language Syntax Reference

**ac = agentic cot** — syntax designed by AI agents

**Version:** 0.1 (Phase 1)
**Updated as features are implemented. Each section lists the feature number from FEATURES.md.**

---

## Design Principle

ac's syntax was designed by AI agents. The rule: if an LLM can predict the syntax, that IS the syntax. Every construct uses the most familiar pattern across C-style languages — the pattern with the strongest signal in training data. The result is Rust's expressiveness with Go's cleanliness.

ac exists to dogfood the COT compiler toolkit. It is not the product — CIR is the product. ac exercises CIR until real frontends (Zig, TypeScript) are added. But its agentic design means it's genuinely easy for AI-assisted development.

---

## Basics

No semicolons. Newlines terminate statements (Go-style automatic insertion).
Line comments: `// comment`

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
let x: i32 = 42        // immutable binding
var count: i32 = 0      // mutable binding
count = count + 1       // assignment
count += 1              // compound assignment
```

## Control Flow (#015-#019)

```ac
if x > 0 {
    // ...
} else {
    // ...
}

while x < 10 {
    x += 1
}

for i in 0..10 {
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

## Structs (#024-#027)

```ac
struct Point {
    x: i32
    y: i32
}

let p = Point { x: 1, y: 2 }
let x = p.x
```

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

## Generics (#055-#059)

```ac
fn max[T](a: T, b: T) -> T {
    if a > b { a } else { b }
}
```

## Traits (#057-#060)

```ac
trait Hashable {
    fn hash(self) -> u64
}

impl Hashable for Point {
    fn hash(self) -> u64 {
        // ...
    }
}
```

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
