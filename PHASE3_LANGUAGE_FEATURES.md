# Phase 3: Language Features Execution Plan

## Critical Methodology

**READ FIRST: [TROUBLESHOOTING.md](TROUBLESHOOTING.md)**

Every feature in this document MUST be implemented by copying from reference implementations. The Cot project has failed 5 times from "inventing" solutions. The methodology that works:

1. Find the equivalent code in the reference implementation
2. Do line-by-line comparison
3. Copy exactly - no simplifications, no "improvements", no TODOs
4. If you don't understand the reference, read more of it until you do

**Reference Implementations:**

| Pipeline Stage | Reference | Location |
|----------------|-----------|----------|
| Scanner/Parser | Go | `~/learning/go/src/cmd/compile/internal/syntax/` |
| Type Checker | Go | `~/learning/go/src/cmd/compile/internal/types2/` |
| AST → IR | Go | `~/learning/go/src/cmd/compile/internal/ir/` |
| IR → SSA | Go | `~/learning/go/src/cmd/compile/internal/ssagen/` |
| SSA → Wasm | Go | `~/learning/go/src/cmd/compile/internal/wasm/` |
| ARC Insertion | Swift | `~/learning/swift/lib/SILGen/` |
| ARC Runtime | Swift | `~/learning/swift/stdlib/public/runtime/` |
| Wasm → CLIF | Cranelift | `~/learning/wasmtime/crates/cranelift/src/translate/` |
| CLIF → Native | Cranelift | `~/learning/wasmtime/cranelift/codegen/src/` |
| Register Alloc | regalloc2 | `~/learning/regalloc2/src/` |

---

## Feature Inventory

### Priority 1: Core Language Features

| Feature | Keyword | Scanner | Parser | Checker | Lower | Wasm | Native |
|---------|---------|---------|--------|---------|-------|------|--------|
| Methods on structs | `impl` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Enumerations | `enum` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Tagged unions | `union` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Switch expressions | `switch` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Type aliases | `type` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

### Priority 2: Module System

| Feature | Keyword | Scanner | Parser | Checker | Lower | Wasm | Native |
|---------|---------|---------|--------|---------|-------|------|--------|
| File imports | `import` | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| External functions | `extern` | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| Test blocks | `test` | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |

### Priority 3: Operators & Expressions

| Feature | Syntax | Scanner | Parser | Checker | Lower | Wasm | Native |
|---------|--------|---------|--------|---------|-------|------|--------|
| Bitwise AND | `&` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Bitwise OR | `\|` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Bitwise XOR | `^` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Bitwise NOT | `~` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Left shift | `<<` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Right shift | `>>` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Add-assign | `+=` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Sub-assign | `-=` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Mul-assign | `*=` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Div-assign | `/=` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Mod-assign | `%=` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| And-assign | `&=` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Or-assign | `\|=` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Xor-assign | `^=` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

### Priority 4: Types & Literals

| Feature | Syntax | Scanner | Parser | Checker | Lower | Wasm | Native |
|---------|--------|---------|--------|---------|-------|------|--------|
| Optional types | `?T` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Char literals | `'a'` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Hex literals | `0xFF` | ✅ | ✅ | ✅ | ? | ? | ? |
| Binary literals | `0b1010` | ✅ | ✅ | ✅ | ? | ? | ? |
| Octal literals | `0o777` | ✅ | ✅ | ✅ | ? | ? | ? |

### Priority 5: Builtins & Advanced

| Feature | Syntax | Scanner | Parser | Checker | Lower | Wasm | Native |
|---------|--------|---------|--------|---------|-------|------|--------|
| Size of type | `@sizeOf(T)` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Align of type | `@alignOf(T)` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Integer cast | `@intCast(T, v)` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Forward declarations | `fn foo();` | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| Labeled break | `break :label` | ✅ | ✅ | ? | ? | ? | ? |
| Labeled continue | `continue :label` | ✅ | ✅ | ? | ? | ? | ? |

---

## Detailed Implementation Plans

### F1: Methods on Structs (`impl` blocks)

**Syntax:**
```cot
struct Point {
    x: i64,
    y: i64,
}

impl Point {
    fn distance(self) i64 {
        return self.x * self.x + self.y * self.y
    }

    fn translate(self, dx: i64, dy: i64) Point {
        return Point { x: self.x + dx, y: self.y + dy }
    }
}

// Usage:
let p = Point { x: 3, y: 4 }
let d = p.distance()  // Method call syntax
```

**Reference Implementation:**

Go doesn't have impl blocks, but Swift does. For method dispatch:
- Swift SIL: `~/learning/swift/lib/SIL/`
- Swift method lowering: `~/learning/swift/lib/SILGen/SILGenApply.cpp`

For struct methods in Go (receiver syntax):
- `~/learning/go/src/cmd/compile/internal/syntax/parser.go` - function parsing
- `~/learning/go/src/cmd/compile/internal/types2/signature.go` - method signatures

**Pipeline Changes:**

| Stage | File | Changes |
|-------|------|---------|
| Scanner | `token.zig` | `kw_impl` already exists |
| Parser | `parser.zig` | Parse `impl TypeName { fn... }` block |
| AST | `ast.zig` | Add `ImplDecl` node with methods list |
| Checker | `checker.zig` | Resolve `self` type, validate method signatures |
| Lower | `lower.zig` | Lower method calls to function calls with receiver |
| Wasm | `wasm_gen.zig` | Methods become regular functions with extra param |

**Implementation Steps:**

1. **Parser** - Add `parseImplDecl`:
   ```
   Go reference: syntax/parser.go:funcDecl() for method receivers
   ```
   - Parse `impl TypeName { ... }`
   - Inside block, parse function declarations
   - First parameter `self` is implicit receiver

2. **AST** - Add `ImplDecl`:
   ```zig
   pub const ImplDecl = struct {
       type_name: []const u8,
       methods: []const NodeIndex,  // FnDecl nodes
       span: Span,
   };
   ```

3. **Checker** - Method resolution:
   ```
   Go reference: types2/lookup.go:LookupFieldOrMethod
   Swift reference: lib/Sema/TypeCheckDecl.cpp
   ```
   - When checking `expr.method()`, look up method in impl block
   - Verify `self` type matches
   - Add method to type's method table

4. **Lower** - Method call lowering:
   ```
   Swift reference: lib/SILGen/SILGenApply.cpp:emitApply
   ```
   - Transform `obj.method(args)` → `TypeName_method(obj, args)`
   - Methods become regular functions with mangled names

5. **Wasm** - No special handling needed:
   - Methods are just functions after lowering
   - Receiver is first parameter

**Tests to write first:**
```
test/cases/methods/simple_method.cot
test/cases/methods/method_with_args.cot
test/cases/methods/method_chain.cot
test/cases/methods/self_mutation.cot
```

---

### F2: Enumerations (`enum`)

**Syntax:**
```cot
enum Color {
    Red,
    Green,
    Blue,
}

enum Status {
    Pending = 0,
    Active = 1,
    Inactive = 2,
}

let c: Color = Color.Red
```

**Reference Implementation:**

Go enums (iota pattern):
- `~/learning/go/src/cmd/compile/internal/syntax/parser.go` - const decl
- `~/learning/go/src/cmd/compile/internal/types2/const.go` - iota handling

Swift enums:
- `~/learning/swift/lib/AST/Decl.cpp` - EnumDecl
- `~/learning/swift/lib/SILGen/SILGenEnum.cpp` - enum lowering

**Pipeline Changes:**

| Stage | File | Changes |
|-------|------|---------|
| Scanner | `token.zig` | `kw_enum` already exists |
| Parser | `parser.zig` | Parse `enum Name { Variant, ... }` |
| AST | `ast.zig` | Add `EnumDecl` with variants list |
| Types | `types.zig` | Add enum type with variant mapping |
| Checker | `checker.zig` | Resolve `EnumName.Variant`, check exhaustiveness |
| Lower | `lower.zig` | Enums become integers |
| Wasm | `wasm_gen.zig` | Enum values are i32/i64 constants |

**Implementation Steps:**

1. **Parser** - Add `parseEnumDecl`:
   ```
   Go reference: syntax/parser.go:typeDecl, constDecl
   Swift reference: lib/Parse/ParseDecl.cpp:parseEnumDecl
   ```

2. **Types** - Add enum type:
   ```zig
   pub const EnumType = struct {
       name: []const u8,
       variants: []const Variant,

       pub const Variant = struct {
           name: []const u8,
           value: i64,
       };
   };
   ```

3. **Checker** - Enum resolution:
   ```
   Swift reference: lib/Sema/TypeCheckDecl.cpp:visitEnumDecl
   ```
   - Register enum type
   - Assign sequential values (or explicit if provided)
   - Resolve `EnumName.Variant` access

4. **Lower** - Enum to integer:
   ```
   Go reference: cmd/compile/internal/walk/convert.go
   ```
   - `Color.Red` → constant 0
   - `Color.Green` → constant 1
   - etc.

**Tests:**
```
test/cases/enums/simple_enum.cot
test/cases/enums/enum_with_values.cot
test/cases/enums/enum_comparison.cot
test/cases/enums/enum_in_struct.cot
```

---

### F3: Tagged Unions (`union`)

**Syntax:**
```cot
union Result {
    ok: i64,
    error: string,
}

union Option {
    some: i64,
    none,
}

let r: Result = Result.ok(42)
let o: Option = Option.none
```

**Reference Implementation:**

Swift enums with associated values:
- `~/learning/swift/lib/SILGen/SILGenEnum.cpp`
- `~/learning/swift/lib/IRGen/GenEnum.cpp`

Go doesn't have tagged unions, use Swift as primary reference.

**Pipeline Changes:**

| Stage | File | Changes |
|-------|------|---------|
| Scanner | `token.zig` | `kw_union` already exists |
| Parser | `parser.zig` | Parse `union Name { variant: Type, ... }` |
| AST | `ast.zig` | Add `UnionDecl` with typed variants |
| Types | `types.zig` | Add union type (tag + max payload size) |
| Checker | `checker.zig` | Validate variant types, check pattern matching |
| Lower | `lower.zig` | Union = tag byte + payload |
| Wasm | `wasm_gen.zig` | Store tag at offset 0, payload at offset 8 |

**Memory Layout:**
```
offset 0: tag (i32) - which variant
offset 8: payload (max size of all variants)
```

**Implementation Steps:**

1. **Parser** - Parse union declaration:
   ```
   Swift reference: lib/Parse/ParseDecl.cpp:parseEnumDecl (with payloads)
   ```

2. **Types** - Union type:
   ```zig
   pub const UnionType = struct {
       name: []const u8,
       variants: []const Variant,

       pub const Variant = struct {
           name: []const u8,
           payload_type: ?TypeIndex,  // null for unit variants
           tag: u32,
       };

       pub fn maxPayloadSize(self: UnionType, reg: *TypeRegistry) usize {
           var max: usize = 0;
           for (self.variants) |v| {
               if (v.payload_type) |t| {
                   max = @max(max, reg.sizeOf(t));
               }
           }
           return max;
       }
   };
   ```

3. **Lower** - Union construction and access:
   ```
   Swift reference: lib/SILGen/SILGenEnum.cpp:emitInjectEnum
   ```
   - Construction: store tag, then store payload
   - Access: check tag, extract payload

4. **Wasm** - Memory operations:
   - Store tag: `i32.store offset=0`
   - Store payload: `i64.store offset=8` (or appropriate type)

**Tests:**
```
test/cases/unions/simple_union.cot
test/cases/unions/union_with_payload.cot
test/cases/unions/union_unit_variant.cot
test/cases/unions/union_in_switch.cot
```

---

### F4: Switch Expressions

**Syntax:**
```cot
let result = switch value {
    1 => 10,
    2, 3 => 20,
    else => 0,
}

// With unions:
let msg = switch result {
    Result.ok(v) => "got " + str(v),
    Result.error(e) => "error: " + e,
}
```

**Reference Implementation:**

Go switch:
- `~/learning/go/src/cmd/compile/internal/syntax/parser.go` - switchStmt
- `~/learning/go/src/cmd/compile/internal/ssagen/ssa.go` - switch codegen
- `~/learning/go/src/cmd/compile/internal/walk/switch.go` - switch lowering

**Pipeline Changes:**

| Stage | File | Changes |
|-------|------|---------|
| Scanner | `token.zig` | `kw_switch` already exists, add `=>` |
| Parser | `parser.zig` | Parse switch expression with cases |
| AST | `ast.zig` | Add `SwitchExpr` with cases and else |
| Checker | `checker.zig` | Verify exhaustiveness, type consistency |
| Lower | `lower.zig` | Convert to if-else chain or jump table |
| Wasm | `wasm_gen.zig` | Use `br_table` for dense switches |

**Implementation Steps:**

1. **Scanner** - Add `=>` token:
   ```zig
   fat_arrow,  // =>
   ```

2. **Parser** - Parse switch:
   ```
   Go reference: syntax/parser.go:switchStmt
   ```
   ```zig
   fn parseSwitchExpr(self: *Parser) !NodeIndex {
       _ = try self.expect(.kw_switch);
       const scrutinee = try self.parseExpr();
       _ = try self.expect(.lbrace);
       var cases = ArrayList(SwitchCase).init(self.allocator);
       while (!self.check(.rbrace)) {
           const case = try self.parseSwitchCase();
           try cases.append(case);
       }
       _ = try self.expect(.rbrace);
       return self.tree.addExpr(.{ .switch_expr = ... });
   }
   ```

3. **Lower** - Switch to control flow:
   ```
   Go reference: walk/switch.go:walkSwitchExpr
   ```
   - Small switch (< 4 cases): if-else chain
   - Dense switch: jump table (br_table in Wasm)
   - Sparse switch: binary search

4. **Wasm** - Use br_table for efficient dispatch:
   ```
   Go reference: cmd/compile/internal/wasm/ssa.go
   ```

**Tests:**
```
test/cases/switch/switch_int.cot
test/cases/switch/switch_multiple.cot
test/cases/switch/switch_else.cot
test/cases/switch/switch_enum.cot
test/cases/switch/switch_union.cot
```

---

### F5: Type Aliases

**Syntax:**
```cot
type UserId = i64
type Handler = fn(Request) Response
type StringList = []string
```

**Reference Implementation:**

Go type aliases:
- `~/learning/go/src/cmd/compile/internal/syntax/parser.go` - typeDecl
- `~/learning/go/src/cmd/compile/internal/types2/decl.go` - type alias handling

**Pipeline Changes:**

| Stage | File | Changes |
|-------|------|---------|
| Scanner | `token.zig` | `kw_type` already exists |
| Parser | `parser.zig` | Parse `type Name = Type` |
| AST | `ast.zig` | Add `TypeAlias` decl |
| Types | `types.zig` | Register alias, resolve to underlying |
| Checker | `checker.zig` | Expand aliases during type checking |

**Implementation Steps:**

1. **Parser**:
   ```
   Go reference: syntax/parser.go:typeDecl
   ```

2. **Types** - Alias registration:
   - Store alias name → underlying type mapping
   - `resolveType` expands aliases

**Tests:**
```
test/cases/types/type_alias_primitive.cot
test/cases/types/type_alias_struct.cot
test/cases/types/type_alias_function.cot
```

**Implementation Status:** ✅ COMPLETE (Wave 1)

| Component | Reference | Cot File:Line | Evidence |
|-----------|-----------|---------------|----------|
| Type alias decl | Go `types2/alias.go:11-38` | `parser.zig` | Parse `type Name = Type` |
| Alias resolution | Go `types2/decl.go` | `types.zig` | lookupByName resolves aliases |
| Type checking | Go `types2/decl.go` | `checker.zig` | Aliases expand during type check |

**Go pattern (types2/alias.go:11-18):**
```go
// An Alias represents an alias type.
// Alias types are created by alias declarations such as:
//
//	type A = int
//
// The type on the right-hand side of the declaration can be accessed
// using [Alias.Rhs]. This type may itself be an alias.
```

**Cot implementation:**
Type aliases are resolved during type registration. When `type UserId = i64` is parsed, `UserId` is registered as mapping to the underlying `i64` type.

**Tests:**
- `test/cases/types/type_alias.cot` - Basic type alias (exit_code=42)
- `test/cases/types/struct_alias.cot` - Struct type alias (exit_code=30)

---

### F6: File Imports

**Syntax:**
```cot
import "math.cot"
import "utils/helpers.cot"

fn main() i64 {
    return math.add(10, 20)  // or just add() if no namespace
}
```

**Reference Implementation:**

Go imports:
- `~/learning/go/src/cmd/compile/internal/noder/import.go`
- `~/learning/go/src/cmd/compile/internal/types2/resolver.go`

**Pipeline Changes:**

| Stage | File | Changes |
|-------|------|---------|
| Scanner | `token.zig` | `kw_import` already exists |
| Parser | `parser.zig` | Parse `import "path"` at file start |
| Driver | `driver.zig` | Load and compile imported files |
| Checker | `checker.zig` | Merge symbols from imported files |
| Linker | `link.zig` | Combine multiple modules |

**Implementation Steps:**

1. **Parser** - Parse import declarations (must be at top of file)

2. **Driver** - Import resolution:
   ```
   Go reference: noder/import.go:importfile
   ```
   - Resolve path relative to importing file
   - Check for circular imports
   - Parse and check imported file
   - Cache compiled modules

3. **Checker** - Symbol merging:
   - Add imported symbols to scope
   - Handle name collisions

4. **Linker** - Module combination:
   - Merge function tables
   - Resolve cross-module references

**Implementation Status:** ✅ COMPLETE (Wave 4)

| Component | Reference | Cot File:Line | Evidence |
|-----------|-----------|---------------|----------|
| kw_import token | Go `token.go` | `token.zig:33` | `kw_import` in keyword enum |
| Parser import | Go `noder/import.go` | `parser.zig:282-292` | parseImportDecl parses string path |
| AST ImportDecl | Go `ir/import.go` | `ast.zig:39` | ImportDecl with path field |
| AST getImports | Go `gc/main.go` | `ast.zig:284-295` | Collect all import paths from decls |
| Driver recursive | Go `noder/import.go` | `driver.zig:208-246` | parseFileRecursive with seen_files |
| Circular check | Go `noder/import.go` | `driver.zig:212` | seen_files.contains prevents cycles |
| Shared scope | Go `types2/check.go` | `driver.zig:127-148` | global_scope shared across files |
| Shared builder | Go `gc/main.go` | `driver.zig:151-179` | shared_builder accumulates all funcs |

**Go Reference: `cmd/compile/internal/noder/import.go`**

The key pattern is recursive parsing with cycle detection:

```go
// Go pattern
func importfile(pos syntax.Pos, path string) {
    if seen[path] { return } // cycle check
    seen[path] = true
    pkg := loadpkg(path)     // parse + type check
    // merge symbols
}
```

**Cot implementation (`driver.zig:208-246`):**
- parseFileRecursive uses seen_files map for cycle detection
- Imports are resolved relative to the importing file's directory
- All files share a single global_scope for symbol resolution
- All files share a single IR Builder for unified compilation

**Tests:**
- Multi-file compilation works via driver.compileFile()

---

### F7: External Functions

**Syntax:**
```cot
extern fn write(fd: i32, buf: *u8, count: i64) i64
extern fn malloc(size: i64) *u8
extern fn free(ptr: *u8)
```

**Reference Implementation:**

Go external functions:
- `~/learning/go/src/cmd/compile/internal/ir/func.go` - external func handling
- `~/learning/go/src/cmd/link/internal/loader/loader.go` - symbol resolution

**Pipeline Changes:**

| Stage | File | Changes |
|-------|------|---------|
| Scanner | `token.zig` | `kw_extern` already exists |
| Parser | `parser.zig` | Parse `extern fn` (no body) |
| AST | `ast.zig` | Mark FnDecl as external |
| Checker | `checker.zig` | Allow bodyless functions if extern |
| Wasm | `wasm.zig` | Add to import section |
| Native | `driver.zig` | Link with external symbols |

**Implementation Steps:**

1. **Parser** - Extern function (no body):
   ```zig
   if (self.match(.kw_extern)) {
       const fn_decl = try self.parseFnDecl();
       fn_decl.is_extern = true;
       return fn_decl;
   }
   ```

2. **Wasm** - Import section:
   ```
   Go reference: cmd/internal/obj/wasm/wasmobj.go
   ```
   - External functions go in import section
   - Need module name (e.g., "env")

3. **Native** - External symbol reference:
   - Add undefined symbol to object file
   - Linker resolves from libc or other libraries

**Implementation Status:** ✅ COMPLETE (Wave 4)

| Component | Reference | Cot File:Line | Evidence |
|-----------|-----------|---------------|----------|
| kw_extern token | Go `token.go` | `token.zig:33` | `kw_extern` in keyword enum |
| Keyword lookup | Go `token.go` | `token.zig:206` | `"extern", .kw_extern` in keywords map |
| Parser extern fn | Go `syntax/parser.go` | `parser.zig:124-128` | parseExternFn advances, calls parseFnDecl(true) |
| Parser no body | Go `syntax/parser.go` | `parser.zig:146-148` | is_extern -> expect semicolon, no body |
| AST is_extern | Go `ir/func.go` | `ast.zig:40` | FnDecl has is_extern field |
| Checker extern | Go `types2/check.go` | `checker.zig:120-125` | Extern allowed, stored in Symbol |
| Lower skip extern | Go `gc/main.go` | `lower.zig:148-161` | is_extern -> collect ExternFunc instead of lowering |
| IR ExternFunc | Go `obj.WasmImport` | `ir.zig:377-386` | ExternFunc struct: module, name, params, return |
| IR collection | Go `asm.go:159` | `ir.zig:421,466` | Builder.extern_funcs, getIR() includes them |
| Driver wiring | Go `asm.go:154-181` | `driver.zig:995-1041` | Collect extern, addImport BEFORE runtime funcs |
| Wasm import | Go `asm.go:267-288` | `link.zig:156-160,270-288` | addImport, writeImportSec |
| Func index map | Go `hostImportMap` | `driver.zig:1053-1060` | extern_indices added to func_indices |

**Go Reference: `cmd/link/internal/wasm/asm.go:154-181`**

The key pattern from Go is collecting host imports and assigning them indices 0..N-1 before native functions:

```go
// Go asm.go:154-181
var hostImports []*wasmFunc
hostImportMap := make(map[loader.Sym]int64)
for _, fn := range ctxt.Textp {
    relocs := ldr.Relocs(fn)
    for ri := 0; ri < relocs.Count(); ri++ {
        r := relocs.At(ri)
        if r.Type() == objabi.R_WASMIMPORT {
            hostImportMap[fn] = int64(len(hostImports))
            hostImports = append(hostImports, &wasmFunc{...})
        }
    }
}
```

**Cot implementation (`driver.zig:995-1041`):**
- Extern functions are collected during lowering (lower.zig:148-161)
- In generateWasmCode, we iterate extern_funcs and call linker.addImport() BEFORE runtime functions
- Import indices are added to func_indices map so call instructions use correct index
- Result: `(import "env" "console_log" (func (type 0)))` in wasm output

**Tests:**
- `test/cases/extern/simple.cot` - Basic extern function (exit_code=42)

---

### F8: Bitwise Operators

**Syntax:**
```cot
let a = x & y      // AND
let b = x | y      // OR
let c = x ^ y      // XOR
let d = ~x         // NOT
let e = x << 2     // Left shift
let f = x >> 2     // Right shift
```

**Reference Implementation:**

Go bitwise:
- `~/learning/go/src/cmd/compile/internal/ssagen/ssa.go` - binary ops
- `~/learning/go/src/cmd/compile/internal/wasm/ssa.go:401` - wasm codegen

**Implementation Status:** ✅ COMPLETE (Wave 1)

| Component | Reference | Cot File:Line | Evidence |
|-----------|-----------|---------------|----------|
| i64 bitwise | Go `ssa.go:401-406` | `gen.zig:313-345` | getValue64 x2, emit op |
| i32 bitwise | Go `ssa.go:401-406` | `gen.zig:347-395` | wrap, op, extend |
| NOT | N/A (Wasm has no NOT) | `gen.zig:397-402` | XOR with -1 |

**Go pattern (ssa.go:401-406):**
```go
case ssa.OpWasmI64And, ssa.OpWasmI64Or, ssa.OpWasmI64Xor,
     ssa.OpWasmI64Shl, ssa.OpWasmI64ShrS, ssa.OpWasmI64ShrU:
    getValue64(s, v.Args[0])
    getValue64(s, v.Args[1])
    s.Prog(v.Op.Asm())
```

**Cot port (gen.zig:313-320):**
```zig
.wasm_i64_and => {
    try self.getValue64(v.args[0]);
    try self.getValue64(v.args[1]);
    _ = try self.builder.append(.i64_and);
},
```

**Pipeline Changes:**

| Stage | File | Changes |
|-------|------|---------|
| Scanner | `token.zig` | Add `~`, `<<`, `>>` tokens |
| Parser | `parser.zig` | Parse as binary/unary ops |
| SSA | `op.zig` | Add `band`, `bor`, `bxor`, `bnot`, `shl`, `shr` |
| Wasm | `wasm_gen.zig` | Map to `i64.and`, `i64.or`, etc. |

**Wasm Instructions:**
- `&` → `i64.and`
- `|` → `i64.or`
- `^` → `i64.xor`
- `~` → `i64.xor` with -1 (all bits set)
- `<<` → `i64.shl`
- `>>` → `i64.shr_s` (signed) or `i64.shr_u` (unsigned)

**Tests:**
```
test/cases/bitwise/and.cot
test/cases/bitwise/or.cot
test/cases/bitwise/xor.cot
test/cases/bitwise/not.cot
test/cases/bitwise/shift_left.cot
test/cases/bitwise/shift_right.cot
```

---

### F9: Compound Assignment

**Syntax:**
```cot
x += 5    // x = x + 5
x -= 3    // x = x - 3
x *= 2    // x = x * 2
x /= 4    // x = x / 4
x %= 3    // x = x % 3
x &= mask // x = x & mask
x |= flag // x = x | flag
```

**Reference Implementation:**

Go compound assignment:
- `~/learning/go/src/cmd/compile/internal/syntax/parser.go:2164-2168` - parse AssignOp
- `~/learning/go/src/cmd/compile/internal/walk/assign.go:50-52` - rewrite to x = x op y

**Implementation Status:** ✅ COMPLETE (Wave 1)

| Component | Reference | Cot File:Line | Evidence |
|-----------|-----------|---------------|----------|
| Desugar | Go `walk/assign.go:50-52` | `lower.zig:588-594` | Rewrite x op= y → x = x op y |

**Go pattern (walk/assign.go:50-52):**
```go
if n.Op() == ir.OASOP {
    // Rewrite x op= y into x = x op y.
    n = ir.NewAssignStmt(left, ir.NewBinaryExpr(n.AsOp, left, right))
}
```

**Cot port (lower.zig:588-594):**
```zig
// Go reference: walk/assign.go:50-52 - Rewrite x op= y into x = x op y
const value_node = if (assign.op != .assign) blk: {
    const target_val = try self.lowerExprNode(assign.target);
    const rhs_val = try self.lowerExprNode(assign.value);
    break :blk try fb.emitBinary(tokenToBinaryOp(assign.op), target_val, rhs_val, ...);
} else try self.lowerExprNode(assign.value);
```

**Pipeline Changes:**

| Stage | File | Changes |
|-------|------|---------|
| Scanner | `token.zig` | Add `+=`, `-=`, `*=`, `/=`, `%=`, `&=`, `\|=` |
| Parser | `parser.zig` | Parse compound assignment |
| Lower | `lower.zig` | Desugar `x += y` → `x = x + y` |

**Implementation:**

This is pure syntactic sugar. Lower early in the pipeline:
```zig
// In lower.zig
fn lowerAssign(self: *Lowerer, assign: ast.AssignStmt) !void {
    if (assign.op != .assign) {
        // Compound assignment: x += y becomes x = x + y
        const target = self.lowerExpr(assign.target);
        const value = self.lowerExpr(assign.value);
        const binop = self.emitBinary(opFromToken(assign.op), target, value);
        self.emitStore(assign.target, binop);
    } else {
        // Simple assignment
        ...
    }
}
```

**Tests:**
```
test/cases/compound/add_assign.cot
test/cases/compound/sub_assign.cot
test/cases/compound/mul_assign.cot
test/cases/compound/all_compound.cot
```

---

### F10: Optional Types

**Syntax:**
```cot
let maybe: ?i64 = null
let value: ?i64 = 42

if maybe != null {
    let v = maybe.?  // Unwrap (panics if null)
}

let safe = maybe ?? 0  // Null coalesce
```

**Reference Implementation:**

Swift optionals (for layout/semantics):
- `~/learning/swift/lib/SILGen/SILGenExpr.cpp` - optional handling
- `~/learning/swift/lib/IRGen/GenOpaqueLayout.cpp` - optional layout

Go (for Wasm codegen):
- `~/learning/go/src/cmd/compile/internal/wasm/ssa.go:359-363` - select instruction

**Implementation Status:** ✅ COMPLETE (Wave 2)

| Component | Reference | Cot File:Line | Evidence |
|-----------|-----------|---------------|----------|
| `cond_select` | Go `ssa.go:359-363` | `gen.zig:575-582` | Stack order: then, else, cond (i32) |
| `const_nil` | N/A (trivial) | `gen.zig:269-272` | Nil = i64.const 0 |

**Go select pattern (ssa.go:359-363):**
```go
case ssa.OpWasmSelect:
    getValue64(s, v.Args[0])  // then
    getValue64(s, v.Args[1])  // else
    getValue32(s, v.Args[2])  // cond
    s.Prog(v.Op.Asm())
```

**Cot port (gen.zig:575-582):**
```zig
.cond_select => {
    try self.getValue64(v.args[1]); // then_value
    try self.getValue64(v.args[2]); // else_value
    try self.getValue32(v.args[0]); // condition
    _ = try self.builder.append(.select);
},
```

Note: Arg indices differ because Cot's SSA uses [cond, then, else] order, but Wasm stack order matches Go.

**Memory Layout:**
```
// Option<T> where T is non-nullable:
offset 0: has_value (i8: 0 or 1)
offset 8: value (T)  -- only valid if has_value == 1

// For pointer types, use null directly (no wrapper needed)
```

**Pipeline Changes:**

| Stage | File | Changes |
|-------|------|---------|
| Scanner | `token.zig` | Add `?` prefix for types, `.?` for unwrap, `??` for coalesce |
| Parser | `parser.zig` | Parse `?Type`, `expr.?`, `expr ?? default` |
| Types | `types.zig` | Add optional type wrapper |
| Checker | `checker.zig` | Null safety checking |
| Lower | `lower.zig` | Optional construction and unwrap |

**Tests:**
```
test/cases/optional/optional_null.cot
test/cases/optional/optional_value.cot
test/cases/optional/optional_unwrap.cot
test/cases/optional/optional_coalesce.cot
```

---

## Wave 3: Expressions - Implementation Status

### F2: Enumerations

**Implementation Status:** ✅ COMPLETE (Wave 3)

| Component | Reference | Cot File:Line | Evidence |
|-----------|-----------|---------------|----------|
| Enum type | Go `types2/named.go` | `types.zig` | enum_type with backing_type, variants |
| Variant access | Go `types2/expr.go` | `lower.zig` | Field access on enum type returns variant value |
| Type conversion | Go `types2/assignments.go` | `types.zig:isAssignable` | enum → backing_type implicit conversion |

**Go pattern:**
Go's `iota` enums are constants with a backing integer type. Cot follows the same pattern where enum variants map to sequential integers (or explicit values).

**Cot implementation:**
```zig
// types.zig - enum to backing type conversion
if (from_t == .enum_type) return self.isAssignable(from_t.enum_type.backing_type, to);
```

**Tests:**
- `test/cases/enum/simple.cot` - Basic enum with implicit values (exit_code=1)
- `test/cases/enum/explicit_value.cot` - Enum with explicit integer values (exit_code=100)

### F3: Tagged Unions

**Implementation Status:** ✅ COMPLETE (Wave 3)

| Component | Reference | Cot File:Line | Evidence |
|-----------|-----------|---------------|----------|
| Union type | Go `types2/union.go` | `types.zig` | union_type with tag_type, variants |
| Variant access | - | `lower.zig:lowerFieldAccess` | Union.Variant returns tag integer |
| Type conversion | Go `types2/assignments.go` | `types.zig:isAssignable` | union → tag_type implicit conversion |

**Cot implementation:**
```zig
// types.zig - union to tag type conversion
if (from_t == .union_type) return self.isAssignable(from_t.union_type.tag_type, to);

// lower.zig - union variant access
if (base_type == .union_type) {
    for (base_type.union_type.variants, 0..) |variant, i| {
        if (std.mem.eql(u8, variant.name, fa.field)) {
            return try fb.emitConstInt(@intCast(i), base_type_idx, fa.span);
        }
    }
}
```

**Tests:**
- `test/cases/union/simple.cot` - Basic union with variants (exit_code=1)

**Note:** Payload unions (e.g., `Result.Ok(42)`) are future work. Current implementation supports simple tagged unions without payloads.

### F4: Switch Expressions

**Implementation Status:** ✅ COMPLETE (Wave 3)

| Component | Reference | Cot File:Line | Evidence |
|-----------|-----------|---------------|----------|
| Switch parsing | Go `syntax/parser.go` | `parser.zig` | switch expr { cases } |
| Switch lowering | Go `walk/switch.go:128-161` | `lower.zig` | exprSwitch pattern → if/else cascade |
| Enum matching | Go `walk/switch.go:156` | `lower.zig` | s.Emit generates comparisons |

**Go pattern (walk/switch.go:128-161):**
```go
// An exprSwitch walks an expression switch.
type exprSwitch struct {
    exprname ir.Node // value being switched on
    done     ir.Nodes
    clauses  []exprClause
}

func (s *exprSwitch) Emit(out *ir.Nodes) {
    s.flush()
    out.Append(s.done.Take()...)
}
```

Go's `exprSwitch` generates a series of comparisons (if/else cascade) for switch expressions. Cot follows the same pattern: each case becomes an if-else branch comparing the switch value to the case value.

**Cot implementation:**
Switch expressions are lowered to cascading if/else statements. Each case `value => result` becomes `if (expr == value) { result }`.

**Tests:**
- `test/cases/switch/simple.cot` - Switch on integer (exit_code=20)
- `test/cases/switch/enum_switch.cot` - Switch on enum (exit_code=50)

---

## Wave 4: Methods - Implementation Status

### F1: Methods (impl blocks)

**Implementation Status:** ✅ COMPLETE (Wave 4)

| Component | Reference | Cot File:Line | Evidence |
|-----------|-----------|---------------|----------|
| impl parsing | Swift SIL | `parser.zig` | impl TypeName { fn... } |
| Method registration | Go `types2/lookup.go` | `checker.zig:158-169` | registerMethod in method_registry |
| Method lookup | Go `types2/lookup.go` | `types.zig:204-208` | lookupMethod by type_name, method_name |
| Method call | Swift `SILGenApply.cpp` | `lower.zig:1740-1815` | lowerMethodCall, synthesize Type_method name |
| Receiver passing | Swift `SILGenApply.cpp` | `lower.zig:1755-1773` | Use pointer type for addr_local to avoid struct decomposition |

**Key Fix (Feb 2026):**

The receiver pointer must be emitted with a **pointer type**, not the struct type. Otherwise, the SSA builder's struct decomposition logic (for structs 8-16 bytes) incorrectly decomposes the address as field values.

**Before (broken):**
```zig
break :blk try fb.emitAddrLocal(local_idx, base_type_idx, fa.span);  // Point type
```

**After (fixed):**
```zig
const ptr_type = self.type_reg.makePointer(base_type_idx) catch TypeRegistry.I64;
break :blk try fb.emitAddrLocal(local_idx, ptr_type, fa.span);  // *Point type
```

**Tests:**
- `test/cases/methods/simple.cot` - Method call returning sum of fields (exit_code=30)

---

### F11: Character Literals

**Syntax:**
```cot
let c = 'a'
let newline = '\n'
let tab = '\t'
let backslash = '\\'
let quote = '\''
```

**Reference Implementation:**

Go character literals:
- `~/learning/go/src/cmd/compile/internal/syntax/scanner.go` - rune literal

**Pipeline Changes:**

| Stage | File | Changes |
|-------|------|---------|
| Scanner | `scanner.zig` | Scan `'c'` as character literal |
| Token | `token.zig` | Add `char_lit` token |
| Parser | `parser.zig` | Parse char literal as u8 constant |
| Lower | `lower.zig` | Char is just u8 |

**Implementation:**

Characters are simply u8 integers:
```zig
// scanner.zig
fn scanChar(self: *Scanner) Token {
    self.advance(); // skip opening '
    const c = if (self.current() == '\\')
        self.scanEscape()
    else
        self.advance();
    _ = self.expect('\''); // closing '
    return .{ .tok = .char_lit, .text = &[_]u8{c} };
}
```

**Tests:**
```
test/cases/chars/char_simple.cot
test/cases/chars/char_escape.cot
test/cases/chars/char_in_string.cot
```

**Implementation Status:** ✅ COMPLETE (Wave 1)

| Component | Reference | Cot File:Line | Evidence |
|-----------|-----------|---------------|----------|
| Char scanning | Go `syntax/scanner.go:628` | `scanner.zig` | Scan 'c' as char literal |
| Escape sequences | Go `syntax/scanner.go:590-606` | `scanner.zig` | Handle \n, \t, \\, \' |
| Char as integer | Go semantics | `lower.zig` | Char literal → i64 constant |

**Go pattern (syntax/scanner.go:628):**
```go
func (s *scanner) rune() {
    ok := true
    s.nextch()
    if s.ch == '\'' {
        s.errorf("empty rune literal or unescaped '")
        ok = false
    }
    // ... scan character or escape sequence
}
```

**Cot implementation:**
Character literals are scanned as single-character tokens and lowered to i64 constants (the ASCII value). Escape sequences like `\n` (10), `\t` (9), `\\` (92), `\'` (39) are handled during scanning.

**Tests:**
- `test/cases/chars/char_simple.cot` - Basic char 'A' = 65 (exit_code=65)
- `test/cases/chars/char_escape.cot` - Escape '\n' = 10 (exit_code=10)

---

### F12: Builtins (@sizeOf, @alignOf, @intCast)

**Syntax:**
```cot
let size = @sizeOf(Point)     // Compile-time constant
let align = @alignOf(i64)     // Compile-time constant
let narrow = @intCast(u8, big_value)  // Runtime conversion
```

**Reference Implementation:**

Go builtins:
- `~/learning/go/src/cmd/compile/internal/typecheck/builtin.go`
- `~/learning/go/src/cmd/compile/internal/walk/builtin.go`

**Pipeline Changes:**

| Stage | File | Changes |
|-------|------|---------|
| Scanner | `scanner.zig` | Scan `@identifier` as builtin |
| Parser | `parser.zig` | Parse builtin calls |
| Checker | `checker.zig` | Type-check builtin arguments |
| Lower | `lower.zig` | Evaluate compile-time builtins, lower runtime ones |

**Implementation:**

1. **@sizeOf(T)** - Compile-time:
   ```zig
   fn lowerSizeOf(self: *Lowerer, type_arg: TypeIndex) !ir.NodeIndex {
       const size = self.type_reg.sizeOf(type_arg);
       return self.emitConstInt(size, TypeRegistry.I64);
   }
   ```

2. **@alignOf(T)** - Compile-time:
   ```zig
   fn lowerAlignOf(self: *Lowerer, type_arg: TypeIndex) !ir.NodeIndex {
       const align = self.type_reg.alignOf(type_arg);
       return self.emitConstInt(align, TypeRegistry.I64);
   }
   ```

3. **@intCast(T, v)** - Runtime:
   ```zig
   fn lowerIntCast(self: *Lowerer, target_type: TypeIndex, value: ir.NodeIndex) !ir.NodeIndex {
       // Emit appropriate truncation or extension
       return self.emit(.int_cast, value, target_type);
   }
   ```

**Tests:**
```
test/cases/builtins/sizeof.cot
test/cases/builtins/alignof.cot
test/cases/builtins/intcast.cot
```

**Implementation Status:** ✅ COMPLETE (Wave 3)

| Component | Reference | Cot File:Line | Evidence |
|-----------|-----------|---------------|----------|
| @sizeOf | Go `typecheck/builtin.go` | `lower.zig:2020-2023` | type_reg.sizeOf → const int |
| @alignOf | Go `typecheck/builtin.go` | `lower.zig:2024-2027` | type_reg.alignOf → const int |
| @intCast | Go `wasm/ssa.go:479-501` | `gen.zig:656-676` | i32_wrap_i64, i64_extend_i32_s |
| Parser | Go `syntax/parser.go` | `parser.zig:561-602` | parseBuiltinCall handles @ |
| Checker | Go `typecheck/builtin.go` | `checker.zig:478-481` | Type-check builtin args |

**Go pattern for integer conversion (wasm/ssa.go:479-487):**
```go
// 64-bit to 32-bit truncation
getValue64(s, v.Args[0])
s.Prog(wasm.AI32WrapI64)
```

**Cot port (gen.zig:656-676):**
```zig
.convert => {
    try self.getValue64(v.args[0]);
    if (!from_is_32 and to_is_32) {
        // i64 -> i32: wrap then extend back
        _ = try self.builder.append(.i32_wrap_i64);
        _ = try self.builder.append(.i64_extend_i32_s);
    }
},
```

**Tests:**
- `test/cases/builtins/sizeof_basic.cot` - @sizeOf(i64) = 8 (exit_code=8)
- `test/cases/builtins/sizeof_struct.cot` - @sizeOf(Point) = 16 (exit_code=16)
- `test/cases/builtins/alignof_basic.cot` - @alignOf(i64) = 8 (exit_code=8)
- `test/cases/builtins/intcast_basic.cot` - @intCast(i32, 42) = 42 (exit_code=42)

---

## Implementation Order

Execute in this order to minimize dependencies:

### Wave 1: Foundation (No dependencies)
1. **F11: Character literals** - Simple scanner addition
2. **F8: Bitwise operators** - Straightforward ops
3. **F9: Compound assignment** - Pure desugaring
4. **F5: Type aliases** - Minimal changes

### Wave 2: Core Types (Depends on Wave 1)
5. **F2: Enumerations** - New type, simple lowering
6. **F3: Tagged unions** - Builds on enums
7. **F10: Optional types** - Special case of union

### Wave 3: Expressions (Depends on Wave 2)
8. **F4: Switch expressions** - Works with enums/unions
9. **F12: Builtins** - Compile-time evaluation

### Wave 4: Methods & Modules (Depends on Wave 3)
10. **F1: Methods (impl blocks)** - Major feature
11. **F6: File imports** - Module system
12. **F7: External functions** - FFI

---

## Testing Strategy

For each feature:
1. Write test cases FIRST (TDD)
2. Test must pass on BOTH wasm and native targets
3. Test file naming: `test/cases/{feature}/{test_name}.cot`
4. Expected format: `// EXPECT: exit_code=N`

**Run tests:**
```bash
zig build test
```

---

## Progress Tracking

Update this table as features are completed:

| Feature | Scanner | Parser | Checker | Lower | Wasm | Native | Tests |
|---------|---------|--------|---------|-------|------|--------|-------|
| F1: impl | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| F2: enum | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| F3: union | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| F4: switch | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| F5: type | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| F6: import | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ |
| F7: extern | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ |
| F8: bitwise | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| F9: compound | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| F10: optional | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| F11: char | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| F12: builtins | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

---

## Remember

**From TROUBLESHOOTING.md:**

> If you're reasoning about what the code SHOULD do, you're doing it wrong.
> Find what the reference implementation DOES do, and copy it.

Every line of code in Phase 3 must trace back to a reference implementation. No exceptions.
