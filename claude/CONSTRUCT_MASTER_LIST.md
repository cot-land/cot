# CIR Construct Master List — v1.0 Target

**Date:** 2026-04-05
**Purpose:** Definitive list of language constructs CIR must support for 1:1 Zig + TypeScript compatibility.
**Status:** Living document. Updated as constructs are implemented.

**Source data:** Zig has 147 AST tags, 247 ZIR instructions, 213 AIR instructions.
TypeScript has 356 AST kind constants. Many overlap. This document groups at
the AST construct level — what each frontend parser actually handles.

**Cross-referenced with:** `claude/FEATURES.md` (~120 features across 12 phases).
New constructs from this audit added to FEATURES.md as #054a-c, #060a-f, #065a-g, #080b-e, #081-088.

---

## High-Level Progress

| Metric | Count |
|--------|-------|
| CIR ops implemented | 55 |
| CIR custom types | 8 |
| Zig AST constructs handled | ~50 of 147 (34%) |
| TypeScript AST constructs handled | ~40 of 356 (11%) |
| Tests passing | 134 |

---

## Zig Constructs (147 AST tags)

### Handled (Zig frontend produces correct CIR)

| # | AST Tag(s) | Construct | CIR Mapping | Status |
|---|-----------|-----------|-------------|--------|
| 1 | `number_literal` | Integer literal | `cir.constant` | ✓ |
| 2 | `number_literal` (float) | Float literal | `cir.constant` (float) | ✓ |
| 3 | `string_literal` | String literal | `cir.string_constant` | ✓ |
| 4 | `char_literal` | Char literal | `cir.constant` (i8) | — |
| 5 | `identifier` (true/false) | Bool literal | `cir.constant` (i1) | ✓ |
| 6 | `identifier` (null) | Null literal | `cir.none` | ✓ |
| 7 | `add`, `sub`, `mul` | Arithmetic | `cir.add/sub/mul` | ✓ |
| 8 | `div`, `mod` | Division/modulo | `cir.div/rem` | ✓ |
| 9 | `negation` | Negation | `cir.neg` (via sub) | ✓ |
| 10 | `cmp_eq/ne/lt/le/gt/ge` | Comparisons (6) | `cir.cmp` | ✓ |
| 11 | `bit_and/or/xor` | Bitwise (3) | `cir.bit_and/or/xor` | ✓ |
| 12 | `bit_not` | Bitwise NOT | `cir.bit_not` | ✓ |
| 13 | `shl/shr` | Shifts | `cir.shl/shr` | ✓ |
| 14 | `simple_var_decl` | const/var declaration | `cir.alloca + store` | ✓ |
| 15 | `assign` | Assignment | `cir.store` | ✓ |
| 16 | `assign_add/sub/mul/div` | Compound assign (4) | load + op + store | ✓ |
| 17 | `fn_decl` | Function declaration | `func.func` | ✓ |
| 18 | `call_one/call` | Function call | `func.call` | ✓ |
| 19 | `@"return"` | Return | `func.return` | ✓ |
| 20 | `if_simple/if` | If statement | `cir.condbr + br` | ✓ |
| 21 | `if_simple` + payload | If-unwrap optional | `cir.is_non_null + optional_payload` | ✓ |
| 22 | `while_simple/while` | While loop | `cir.condbr + br` (loop) | ✓ |
| 23 | `for_simple/for` | For loop | desugar to while | ✓ |
| 24 | `break` | Break | `cir.br` to exit | ✓ |
| 25 | `continue` | Continue | `cir.br` to header | ✓ |
| 26 | `container_decl*` (struct) | Struct declaration | `!cir.struct` | ✓ |
| 27 | `struct_init*` | Struct init | `cir.struct_init` | ✓ |
| 28 | `field_access` (struct) | Field access | `cir.field_val` | ✓ |
| 29 | `field_access` (method) | Method call | desugar to call | ✓ |
| 30 | `array_type` | Array type | `!cir.array` | ✓ |
| 31 | `array_init*` | Array init | `cir.array_init` | ✓ |
| 32 | `array_access` | Array index | `cir.elem_val` | ✓ |
| 33 | `ptr_type*` | Pointer type | `!cir.ref<T>` | ✓ |
| 34 | `address_of` | Address-of (&) | `cir.addr_of` | ✓ |
| 35 | `deref` | Dereference (.*) | `cir.deref` | ✓ |
| 36 | `ptr_type` (slice) | Slice type []T | `!cir.slice<T>` | ✓ |
| 37 | `field_access` (.len/.ptr) | Slice len/ptr | `cir.slice_len/ptr` | ✓ |
| 38 | `slice` | Slice indexing s[i] | `cir.slice_elem` | ✓ |
| 39 | `optional_type` | Optional ?T | `!cir.optional<T>` | ✓ |
| 40 | `error_union` | Error union E!T | `!cir.error_union<T>` | ✓ |
| 41 | `error_value` | Error literal | `cir.wrap_error` | ✓ |
| 42 | `@"try"` | Try expression | `is_error + condbr` | ✓ |
| 43 | `@"catch"` | Catch expression | `is_error + condbr` | ✓ |
| 44 | `builtin_call*` (@intCast) | @intCast | `cir.extsi/trunci` | ✓ |
| 45 | `builtin_call*` (@floatCast) | @floatCast | `cir.extf/truncf` | ✓ |
| 46 | `builtin_call*` (@floatFromInt) | @floatFromInt | `cir.sitofp` | ✓ |
| 47 | `builtin_call*` (@intFromFloat) | @intFromFloat | `cir.fptosi` | ✓ |
| 48 | `builtin_call*` (@divTrunc) | @divTrunc | `cir.div` | ✓ |
| 49 | `builtin_call*` (@mod) | @mod | `cir.rem` | ✓ |
| 50 | `container_decl*` (enum) | Enum declaration | `!cir.enum<...>` | ✓ |
| 51 | `enum_literal` | Enum literal .red | `cir.enum_constant` | ✓ |
| 52 | `test_decl` | Test declaration | test function | ✓ |

### Not Yet Handled (Zig frontend gaps)

| # | AST Tag(s) | Construct | CIR Mapping | Phase |
|---|-----------|-----------|-------------|-------|
| 53 | `switch_block*` | Switch/match | `cir.switch` | 6 |
| 54 | `container_decl*` (union) | Tagged union | `!cir.tagged_union` | 6 |
| 55 | `orelse` | Orelse expression | `is_non_null + select` | 6 |
| 56 | `unwrap` (.?) | Force unwrap | `optional_payload + trap` | 6 |
| 57 | `error_set_decl` | Error set type | frontend maps to i16 | 5 (partial) |
| 58 | `builtin_call*` (@truncate) | @truncate | `cir.trunci` | Done in builtin |
| 59 | `builtin_call*` (@as) | @as type coercion | cast ops | 7 |
| 60 | `builtin_call*` (@sizeOf) | @sizeOf | comptime | 7 |
| 61 | `builtin_call*` (@alignOf) | @alignOf | comptime | 7 |
| 62 | `builtin_call*` (@typeInfo) | @typeInfo | comptime | 7 |
| 63 | `builtin_call*` (@typeName) | @typeName | comptime | 7 |
| 64 | `builtin_call*` (@import) | @import | modules | 10 |
| 65 | `builtin_call*` (@embedFile) | @embedFile | modules | 10 |
| 66 | `builtin_call*` (~30 more) | Other builtins | varies | 7-11 |
| 67 | `asm_expr` | Inline assembly | passthrough | 11 |
| 68 | `defer/errdefer` | Defer statement | `cir.defer` | 10 |
| 69 | `suspend/resume/nosuspend` | Async suspend/resume | `cir_conc.*` | 9 |
| 70 | `async_call` | Async call | `cir_conc.*` | 9 |
| 71 | `await` | Await | `cir_conc.*` | 9 |
| 72 | `comptime` | Comptime block | `cir.comptime_block` | 7 |
| 73 | `fn_proto*` (generic) | Generic function | monomorphize | 7 |
| 74 | `for_simple` (payload) | For with capture | iterator desugar | 6 |
| 75 | `merge_error_sets` | Merge error sets | frontend | 7 |
| 76 | `multi_assign` | Multi-assign destructure | desugar | 8 |
| 77 | `labeled_block` | Labeled blocks | block args | 7 |
| 78 | `container_decl*` (opaque) | Opaque type | `!cir.ptr` | 7 |
| 79 | `align/addrspace/bit_range` | Pointer qualifiers | type attrs | 8 |
| 80 | `bool_and/bool_or` | Short-circuit logic | `condbr` chain | 6 |
| 81 | `wrapping_add/sub/mul` | Wrapping arithmetic | `cir.add_wrap` etc | 8 |
| 82 | `saturating_add/sub/mul` | Saturating arithmetic | `cir.add_sat` etc | 8 |
| 83 | `slice_open/sentinel` | Slice variants | `cir.array_to_slice` variants | 8 |
| 84 | `usingnamespace` | Using namespace | module import | 10 |

**Zig total: 84 constructs identified. 52 handled (62%).**
**Remaining: 32 constructs across Phases 6-11.**

---

## TypeScript Constructs (356 AST kinds)

### Handled (TS frontend produces correct CIR)

| # | AST Kind(s) | Construct | CIR Mapping | Status |
|---|------------|-----------|-------------|--------|
| 1 | `NumericLiteral` | Number literal | `cir.constant` (i32) | ✓ |
| 2 | `StringLiteral` | String literal | `cir.string_constant` | ✓ |
| 3 | `TrueKeyword/FalseKeyword` | Bool literal | `cir.constant` (i1) | ✓ |
| 4 | `NullKeyword` | Null literal | `cir.none` / context | ✓ |
| 5 | `BinaryExpression` (+/-/*) | Arithmetic | `cir.add/sub/mul` | ✓ |
| 6 | `BinaryExpression` (/ %) | Division/modulo | `cir.div/rem` | ✓ |
| 7 | `PrefixUnaryExpression` (-) | Negation | `cir.neg` | ✓ |
| 8 | `BinaryExpression` (==/!=/<) | Comparisons | `cir.cmp` | ✓ |
| 9 | `BinaryExpression` (& \| ^) | Bitwise | `cir.bit_and/or/xor` | ✓ |
| 10 | `PrefixUnaryExpression` (~) | Bitwise NOT | `cir.bit_not` | ✓ |
| 11 | `BinaryExpression` (<< >>) | Shifts | `cir.shl/shr` | ✓ |
| 12 | `VariableDeclaration` (let) | Let binding | `cir.alloca + store` | ✓ |
| 13 | `VariableDeclaration` (var) | Var binding | `cir.alloca + store` | ✓ |
| 14 | `VariableDeclaration` (const) | Const binding | `cir.alloca + store` | ✓ |
| 15 | `BinaryExpression` (=) | Assignment | `cir.store` | ✓ |
| 16 | `BinaryExpression` (+=/-=) | Compound assign | load + op + store | ✓ |
| 17 | `FunctionDeclaration` | Function declaration | `func.func` | ✓ |
| 18 | `CallExpression` | Function call | `func.call` | ✓ |
| 19 | `ReturnStatement` | Return | `func.return` | ✓ |
| 20 | `IfStatement` | If statement | `cir.condbr + br` | ✓ |
| 21 | `WhileStatement` | While loop | `cir.condbr + br` (loop) | ✓ |
| 22 | `ForStatement` | For loop | desugared while | ✓ |
| 23 | `ConditionalExpression` | Ternary (?:) | `cir.select` | ✓ |
| 24 | `InterfaceDeclaration` | Interface (→struct) | `!cir.struct` | ✓ |
| 25 | `ObjectLiteralExpression` | Object init | `cir.struct_init` | ✓ |
| 26 | `PropertyAccessExpression` | Property access | `cir.field_val` | ✓ |
| 27 | `CallExpression` (method) | Method call | desugar to call | ✓ |
| 28 | `ArrayLiteralExpression` | Array literal | `cir.array_init` | ✓ |
| 29 | `ElementAccessExpression` | Array index [i] | `cir.elem_val` | ✓ |
| 30 | `PropertyAccess` (.length) | String/array .length | `cir.slice_len` | ✓ |
| 31 | `ThrowStatement` | Throw | `cir.throw` | ✓ |
| 32 | `TryStatement` | Try/catch | `cir.invoke + landingpad` | ✓ |
| 33 | `CatchClause` | Catch clause | `cir.landingpad` | ✓ |
| 34 | `UnionType` (T \| Error) | Error union type | `!cir.error_union<T>` | ✓ |
| 35 | `EnumDeclaration` | Enum declaration | `!cir.enum<...>` | ✓ |
| 36 | `PropertyAccess` (enum) | Enum member access | `cir.enum_constant` | ✓ |
| 37 | `TypeAliasDeclaration` | Type alias | frontend registry | ✓ |

### Not Yet Handled (TS frontend gaps)

| # | AST Kind(s) | Construct | CIR Mapping | Phase |
|---|------------|-----------|-------------|-------|
| 38 | `SwitchStatement` | Switch/case | `cir.switch` | 6 |
| 39 | `CaseClause/DefaultClause` | Case/default | switch branches | 6 |
| 40 | `BreakStatement` | Break | `cir.br` to exit | 6 |
| 41 | `ContinueStatement` | Continue | `cir.br` to header | 6 |
| 42 | `ForInStatement` | For-in loop | desugar | 10 |
| 43 | `ForOfStatement` | For-of loop | desugar iterator | 10 |
| 44 | `DoStatement` | Do-while loop | `cir.condbr` variant | 7 |
| 45 | `ClassDeclaration` | Class declaration | TBD | 7b |
| 46 | `Constructor` | Constructor | TBD | 7b |
| 47 | `MethodDeclaration` | Class method | TBD | 7b |
| 48 | `PropertyDeclaration` | Class property | TBD | 7b |
| 49 | `GetAccessor/SetAccessor` | Getter/Setter | TBD | 7b |
| 50 | `StaticKeyword` | Static members | TBD | 7b |
| 51 | `HeritageClause` (extends) | Inheritance | TBD | 7b |
| 52 | `HeritageClause` (impl) | Implements | TBD | 7b |
| 53 | `AbstractKeyword` | Abstract class | TBD | 7b |
| 54 | `TypeParameter` | Generic param <T> | monomorphize | 7 |
| 55 | `TypeReference` (generic) | Generic invocation | monomorphize | 7 |
| 56 | `ConditionalType` | Conditional type | comptime | 7 |
| 57 | `MappedType` | Mapped type | comptime | 7 |
| 58 | `IndexedAccessType` | Indexed access T[K] | comptime | 7 |
| 59 | `KeyOfKeyword` | keyof operator | comptime | 7 |
| 60 | `TypeQuery` (typeof) | typeof in types | comptime | 7 |
| 61 | `AsyncKeyword` | Async function | `cir_conc.*` | 9 |
| 62 | `AwaitExpression` | Await | `cir_conc.*` | 9 |
| 63 | `YieldExpression` | Generator yield | `cir_conc.*` | 9 |
| 64 | `ImportDeclaration` | Import | module system | 10 |
| 65 | `ExportDeclaration` | Export | module system | 10 |
| 66 | `ImportClause/NamedImports` | Named imports | module system | 10 |
| 67 | `NamespaceImport` | Namespace import | module system | 10 |
| 68 | `ModuleDeclaration` | Namespace/module | module system | 10 |
| 69 | `NewExpression` | new constructor | heap alloc | 8 |
| 70 | `DeleteExpression` | delete operator | dealloc | 8 |
| 71 | `ObjectBindingPattern` | Object destructure | desugar | 8 |
| 72 | `ArrayBindingPattern` | Array destructure | desugar | 8 |
| 73 | `SpreadElement` | Spread operator | desugar | 8 |
| 74 | `TemplateExpression` | Template literal | string ops | 8 |
| 75 | `TaggedTemplateExpr` | Tagged template | call + string | 8 |
| 76 | `RegularExpressionLiteral` | Regex | runtime lib | 11 |
| 77 | `PrefixUnary` (++/--) | Increment/decrement | load + add + store | 7 |
| 78 | `PostfixUnary` (++/--) | Post-increment | load + add + store | 7 |
| 79 | `BinaryExpression` (&&/\|\|) | Short-circuit logic | `condbr` chain | 6 |
| 80 | `BinaryExpression` (??) | Nullish coalescing | `is_non_null + select` | 6 |
| 81 | `QuestionDotToken` | Optional chaining ?. | `is_non_null + condbr` | 7 |
| 82 | `NonNullExpression` | Non-null assert x! | `optional_payload` | 7 |
| 83 | `AsExpression` | Type assertion | cast / noop | 7 |
| 84 | `SatisfiesExpression` | Satisfies check | type-only (no CIR) | 7 |
| 85 | `InstanceOfKeyword` | instanceof | runtime check | 8 |
| 86 | `InKeyword` (expr) | in operator | runtime check | 8 |
| 87 | `Decorator` | Decorators | TBD | 11 |
| 88 | `BigIntLiteral` | BigInt | runtime lib | 11 |
| 89 | `SymbolKeyword` | Symbol | runtime lib | 11 |
| 90 | `JsxElement/Fragment` | JSX (13 kinds) | TBD | 11+ |
| 91 | `LabeledStatement` | Labels | block names | 8 |
| 92 | `WithStatement` | With (deprecated) | skip | — |
| 93 | `DebuggerStatement` | Debugger | noop/trap | 11 |

**TypeScript total: 93 constructs identified. 37 handled (40%).**
**Remaining: 56 constructs across Phases 6-11+.**

---

## Combined v1.0 Scope

| Category | Zig | TS | Shared | CIR Ops | Done |
|----------|-----|----|---------|---------| ----|
| **Core (arithmetic, vars, control)** | 25 | 24 | 24 | 20 | **20** ✓ |
| **Aggregates (struct, array)** | 6 | 5 | 5 | 7 | **7** ✓ |
| **Pointers & Slices** | 7 | 1 | 1 | 9 | **9** ✓ |
| **Optionals** | 4 | 0 | 0 | 4 | **4** ✓ |
| **Error handling** | 5 | 4 | 0 | 8 | **8** ✓ |
| **Enums** | 2 | 2 | 2 | 2 | **2** ✓ |
| **Type casts** | 6 | 1 | 1 | 7 | **7** ✓ |
| **Builtins (@intCast etc)** | 6 | 0 | 0 | (reuse cast ops) | **6** ✓ |
| **Switch/match** | 3 | 4 | 3 | 1 | 0 |
| **Tagged unions** | 3 | 2 | 0 | 3 | 0 |
| **Generics/comptime** | 6 | 8 | 4 | ~8 | 0 |
| **Classes** | 0 | 10 | 0 | ~8 | 0 |
| **Async** | 4 | 3 | 3 | ~4 | 0 |
| **Modules/imports** | 2 | 8 | 2 | ~4 | 0 |
| **Memory (new/delete/ARC)** | 2 | 3 | 0 | ~6 | 0 |
| **Defer/cleanup** | 2 | 0 | 0 | 2 | 0 |
| **Destructuring/spread** | 1 | 4 | 0 | ~3 | 0 |
| **Advanced operators** | 4 | 6 | 2 | ~4 | 0 |
| **Stdlib/runtime** | 2 | 4 | 0 | ~3 | 0 |
| **TOTALS** | **84** | **93** | — | **~100** | **55** |

### Progress: **55 / ~100 CIR ops (55%). 63 / 177 frontend constructs handled.**

---

## Phase Roadmap

| Phase | Features | New CIR Ops | Zig Constructs | TS Constructs |
|-------|----------|-------------|----------------|---------------|
| 6 (current) | Switch, unions, short-circuit | ~5 | 6 | 6 |
| 7 | Generics, comptime, do-while, ++/--, assertions | ~8 | 8 | 12 |
| 7b | Classes (TS-only) | ~8 | 0 | 10 |
| 8 | Memory, destructuring, wrapping math, labels | ~6 | 6 | 8 |
| 9 | Async/await | ~4 | 4 | 3 |
| 10 | Modules, imports, defer | ~4 | 4 | 8 |
| 11 | Stdlib, runtime, advanced | ~3 | 4 | 9 |
