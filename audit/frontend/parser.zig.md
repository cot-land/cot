# Audit: frontend/parser.zig

## Status: VERIFIED CORRECT

| Metric | Value |
|--------|-------|
| 0.2 lines | 1815 |
| 0.3 lines | 882 |
| Reduction | 51% |
| Tests | 11/11 pass |

---

## Function-by-Function Verification

### Parser struct

| Component | 0.2 | 0.3 | Verdict |
|-----------|-----|-----|---------|
| Fields | allocator, scan, tree, err, tok, peek_tok, nest_lev | Same 7 fields | IDENTICAL |

### Parser methods - Token handling

| Method | 0.2 Logic | 0.3 Logic | Verdict |
|--------|-----------|-----------|---------|
| init() | Create parser, advance twice for lookahead | Same | IDENTICAL |
| pos() | `return self.tok.span.start` | Same | IDENTICAL |
| advance() | Store peek_tok in tok, scan next into peek_tok | Same | IDENTICAL |
| peekToken() | `return self.peek_tok.tok` | Same | IDENTICAL |
| check() | `return self.tok.tok == tok` | Same | IDENTICAL |
| match() | If check, advance and return true | Same | IDENTICAL |
| expect() | If check, advance; else call unexpectedToken | Same | IDENTICAL |
| unexpectedToken() | Report error with context (after, expected, found) | Same (compact switch) | IDENTICAL |
| incNest() | Increment nest_lev, check MAX_RECURSION | Same | IDENTICAL |
| decNest() | Decrement nest_lev | Same | IDENTICAL |

### Declaration Parsing (11 methods)

| Method | 0.2 Logic | 0.3 Logic | Verdict |
|--------|-----------|-----------|---------|
| parseFile() | Loop parseDecl until eof, build File struct | Same | IDENTICAL |
| parseDecl() | Switch on token: fn/extern/var/const/struct/enum/union/type/impl/test | Same 10-way dispatch | IDENTICAL |
| parseFnDecl() | Parse name, params, return type, body | Same | IDENTICAL |
| parseFieldList() | Loop: name, colon, type, optional default | Same | IDENTICAL |
| parseVarDecl() | Parse name, optional type, optional value | Same | IDENTICAL |
| parseStructDecl() | Parse name, lbrace, fields, rbrace | Same | IDENTICAL |
| parseImplBlock() | Parse type name, lbrace, methods, rbrace | Same | IDENTICAL |
| parseEnumDecl() | Parse name, optional backing type, variants | Same | IDENTICAL |
| parseUnionDecl() | Parse name, lbrace, variants, rbrace | Same | IDENTICAL |
| parseTypeAlias() | Parse name, equals, target type | Same | IDENTICAL |
| parseTestDecl() | Parse optional name, body block | Same | IDENTICAL |

### Type Parsing

| Method | 0.2 Logic | 0.3 Logic | Verdict |
|--------|-----------|-----------|---------|
| parseType() | Handle ?, *, [], [N], named, fn types | Same 9 type kinds | IDENTICAL |

Type kinds handled:
- `?T` optional
- `*T` pointer
- `[]T` slice
- `[N]T` array
- `[K]V` map (with colon)
- `List(T)` generic list
- `fn(args) ret` function type
- Named types with generic args
- Error union `T!E`

### Expression Parsing

| Method | 0.2 Logic | 0.3 Logic | Verdict |
|--------|-----------|-----------|---------|
| parseExpr() | `return self.parseBinaryExpr(0)` | Same | IDENTICAL |
| parseBinaryExpr() | Precedence climbing: parse left, loop on higher precedence ops | Same algorithm | IDENTICAL |
| parseUnaryExpr() | Switch: !, -, ~, &, * prefix ops | Same 5 operators | IDENTICAL |
| parsePrimaryExpr() | Parse operand, then postfix: .field, [idx], (args), .*, .? | Same | IDENTICAL |
| parseOperand() | Switch on token type for literals, ident, paren, block, if, switch, builtins | Same (builtin extracted) | IDENTICAL |
| parseBuiltinCall() | Parse @builtin(args) - @sizeOf, @string, @intCast, etc. | Extracted from parseOperand | REFACTORED |
| parseBlockExpr() | Parse { stmts; optional final expr } | Same | IDENTICAL |
| parseIfExpr() | Parse if cond then else | Same | IDENTICAL |
| parseSwitchExpr() | Parse switch (expr) { cases } | Same | IDENTICAL |
| parseSwitchCase() | Parse pattern => expr | Same | IDENTICAL |
| parseStructInit() | Parse .{ .field = value, ... } | Same | IDENTICAL |
| parseArrayLiteral() | Parse .[ elem, ... ] | Same | IDENTICAL |

### Statement Parsing

| Method | 0.2 Logic | 0.3 Logic | Verdict |
|--------|-----------|-----------|---------|
| parseBlock() | Parse { stmts } into BlockStmt | Same | IDENTICAL |
| parseStmt() | Switch: return, var, const, if, while, for, defer, break, continue, else expr/assign | Same dispatch | IDENTICAL |
| parseExprOrAssign() | Parse expr, if assignment op follows make AssignStmt else ExprStmt | Extracted helper | REFACTORED |
| parseVarStmt() | Parse var/const name: type = value | Same | IDENTICAL |
| parseIfStmt() | Parse if cond { } else { } | Same | IDENTICAL |
| parseWhileStmt() | Parse while cond { } | Same | IDENTICAL |
| parseForStmt() | Parse for iter |capture| { } | Same | IDENTICAL |

### Tests (11/11)

| Test | 0.2 | 0.3 | Verdict |
|------|-----|-----|---------|
| parser simple function | `fn main() { return 42 }` | Same | IDENTICAL |
| parser variable declaration | `var x: int = 5` | Same | IDENTICAL |
| parser binary expression precedence | `1 + 2 * 3` | Same | IDENTICAL |
| parser struct declaration | `struct Point { x: int, y: int }` | Same | IDENTICAL |
| parser enum declaration | `enum Color { red, green, blue }` | Same | IDENTICAL |
| parser union declaration | `union Value { int_val: int, str_val: string }` | Same | IDENTICAL |
| parser if statement | `if cond { ... }` | Same | IDENTICAL |
| parser while loop | `while cond { ... }` | Same | IDENTICAL |
| parser for loop | `for items |item| { ... }` | Same | IDENTICAL |
| parser array literal | `.[1, 2, 3]` | Same | IDENTICAL |
| parser error recovery | Bad token handling | Same | IDENTICAL |

---

## Real Improvements

1. **Extracted parseBuiltinCall()**: Builtin handling moved from parseOperand to dedicated method
2. **Extracted parseExprOrAssign()**: Common expr-or-assignment pattern factored out
3. **Compact conditionals**: Single-line method bodies where appropriate
4. **Removed doc comments**: Function names are self-documenting

## What Did NOT Change

- Parser struct (7 fields)
- All token handling methods (10 methods)
- All declaration parsing (11 methods)
- Type parsing (handles 9 type kinds)
- Expression parsing (precedence climbing algorithm)
- All postfix operators (.field, [idx], (args), .*, .?)
- Statement parsing (12 statement types)
- Error recovery behavior
- All 11 tests

---

## Verification

```
$ zig test src/frontend/parser.zig
All 11 tests passed.
```

**VERIFIED: Logic 100% identical. Extracted 2 helpers. 51% reduction from compaction.**
