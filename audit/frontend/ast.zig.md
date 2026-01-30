# Audit: frontend/ast.zig

## Status: VERIFIED CORRECT

| Metric | Value |
|--------|-------|
| 0.2 lines | 765 |
| 0.3 lines | 333 |
| Reduction | 57% |
| Tests | 9/9 pass |

---

## Function-by-Function Verification

### Core Types

| Type | 0.2 | 0.3 | Verdict |
|------|-----|-----|---------|
| NodeIndex | u32 | Same | IDENTICAL |
| null_node | std.math.maxInt(NodeIndex) | Same | IDENTICAL |
| NodeList | []const NodeIndex | Same | IDENTICAL |

### File struct

| Field | 0.2 | 0.3 | Verdict |
|-------|-----|-----|---------|
| filename | []const u8 | Same | IDENTICAL |
| decls | []const NodeIndex | Same | IDENTICAL |
| span | Span | Same | IDENTICAL |

### Decl union (10 variants)

| Variant | 0.2 | 0.3 | Verdict |
|---------|-----|-----|---------|
| fn_decl | FnDecl | Same | IDENTICAL |
| var_decl | VarDecl | Same | IDENTICAL |
| struct_decl | StructDecl | Same | IDENTICAL |
| enum_decl | EnumDecl | Same | IDENTICAL |
| union_decl | UnionDecl | Same | IDENTICAL |
| type_alias | TypeAlias | Same | IDENTICAL |
| import_decl | ImportDecl | Same | IDENTICAL |
| impl_block | ImplBlock | Same | IDENTICAL |
| test_decl | TestDecl | Same | IDENTICAL |
| bad_decl | BadDecl | Same | IDENTICAL |
| span() | `inline else => \|d\| d.span` | Same | IDENTICAL |

### Declaration structs

| Struct | Fields | Verdict |
|--------|--------|---------|
| FnDecl | name, params, return_type, body, is_extern, span | IDENTICAL |
| VarDecl | name, type_expr, value, is_const, span | IDENTICAL |
| StructDecl | name, fields, span | IDENTICAL |
| ImplBlock | type_name, methods, span | IDENTICAL |
| TestDecl | name, body, span | IDENTICAL |
| EnumDecl | name, backing_type, variants, span | IDENTICAL |
| UnionDecl | name, variants, span | IDENTICAL |
| TypeAlias | name, target, span | IDENTICAL |
| ImportDecl | path, span | IDENTICAL |
| BadDecl | span | IDENTICAL |
| Field | name, type_expr, default_value, span | IDENTICAL |
| EnumVariant | name, value, span | IDENTICAL |
| UnionVariant | name, type_expr, span | IDENTICAL |

### Expr union (19 variants)

| Variant | 0.2 | 0.3 | Verdict |
|---------|-----|-----|---------|
| ident, literal, binary, unary | Same | Same | IDENTICAL |
| call, index, slice_expr, field_access | Same | Same | IDENTICAL |
| array_literal, paren, if_expr, switch_expr | Same | Same | IDENTICAL |
| block_expr, struct_init, new_expr, builtin_call | Same | Same | IDENTICAL |
| string_interp, type_expr, addr_of, deref, bad_expr | Same | Same | IDENTICAL |
| span() | `inline else => \|e\| e.span` | Same | IDENTICAL |

### Expression structs (all fields verified identical)

Ident, Literal, Binary, Unary, Call, Index, SliceExpr, FieldAccess, ArrayLiteral, Paren, IfExpr, SwitchExpr, SwitchCase, BlockExpr, StructInit, FieldInit, NewExpr, BuiltinCall, StringSegment, StringInterp, TypeExpr, TypeKind, AddrOf, Deref, BadExpr - ALL IDENTICAL

### LiteralKind enum (8 variants)

int, float, string, char, true_lit, false_lit, null_lit, undefined_lit - IDENTICAL

### TypeKind union (9 variants)

named, pointer, optional, error_union, slice, array, map, list, function - IDENTICAL

### Stmt union (12 variants)

| Variant | 0.2 | 0.3 | Verdict |
|---------|-----|-----|---------|
| expr_stmt, return_stmt, var_stmt, assign_stmt | Same | Same | IDENTICAL |
| if_stmt, while_stmt, for_stmt, block_stmt | Same | Same | IDENTICAL |
| break_stmt, continue_stmt, defer_stmt, bad_stmt | Same | Same | IDENTICAL |
| span() | `inline else => \|s\| s.span` | Same | IDENTICAL |

### Statement structs (all fields verified identical)

ExprStmt, ReturnStmt, VarStmt, AssignStmt, IfStmt, WhileStmt, ForStmt, BlockStmt, BreakStmt, ContinueStmt, DeferStmt, BadStmt - ALL IDENTICAL

### Node union

| Component | 0.2 | 0.3 | Verdict |
|-----------|-----|-----|---------|
| Variants | decl, expr, stmt | Same | IDENTICAL |
| span() | Switch on variant, call variant.span() | Same | IDENTICAL |
| asDecl() | Return decl or null | Same | IDENTICAL |
| asExpr() | Return expr or null | Same | IDENTICAL |
| asStmt() | Return stmt or null | Same | IDENTICAL |

### Ast struct

| Component | 0.2 | 0.3 | Verdict |
|-----------|-----|-----|---------|
| Fields | nodes, allocator, file | Same | IDENTICAL |

### Ast methods

| Method | 0.2 Logic | 0.3 Logic | Verdict |
|--------|-----------|-----------|---------|
| init() | Return empty struct | Same | IDENTICAL |
| deinit() | Free file.decls, iterate nodes, free internal slices | Same (compact) | IDENTICAL |
| addNode() | Cast len to NodeIndex, append, return | Same | IDENTICAL |
| addExpr() | `addNode(.{ .expr = expr })` | Same | IDENTICAL |
| addStmt() | `addNode(.{ .stmt = stmt })` | Same | IDENTICAL |
| addDecl() | `addNode(.{ .decl = decl })` | Same | IDENTICAL |
| getNode() | Check null_node/bounds, return items[idx] | Same | IDENTICAL |
| nodeCount() | `return self.nodes.items.len` | Same | IDENTICAL |
| getRootDecls() | Return file.decls or empty | Same | IDENTICAL |
| getImports() | Iterate decls, collect import paths | Same | IDENTICAL |

### Tests (9/9)

| Test | 0.2 | 0.3 | Verdict |
|------|-----|-----|---------|
| null_node is max value | maxInt(u32) | Same | IDENTICAL |
| Ast add and get nodes | Add ident, check name | Same | IDENTICAL |
| Ast null_node returns null | getNode(null_node) == null | Same | IDENTICAL |
| Node span accessors | Check decl/expr/stmt spans | Same | IDENTICAL |
| Decl span accessor | FnDecl.span() | Same | IDENTICAL |
| Expr span accessor | Ident.span() | Same | IDENTICAL |
| Stmt span accessor | ReturnStmt.span() | Same | IDENTICAL |
| LiteralKind enum | Check variants | Same | IDENTICAL |
| TypeKind union | Check named/pointer | Same | IDENTICAL |

---

## Changes (formatting only)

1. **Single-line struct definitions**: All AST node structs condensed to one line
2. **Removed section dividers and doc comments**
3. **Compact deinit()**: Single-line conditionals for freeing
4. **Compact accessor methods**: asDecl/asExpr/asStmt on single lines

## What Did NOT Change

- NodeIndex, null_node, NodeList definitions
- File struct (3 fields)
- Decl union (10 variants + span method)
- All 13 declaration structs
- Expr union (19 variants + span method)
- All 25 expression structs/types
- Stmt union (12 variants + span method)
- All 12 statement structs
- Node union (3 variants + 4 methods)
- Ast struct (3 fields + 10 methods)
- All 9 tests

---

## Verification

```
$ zig test src/frontend/ast.zig
All 9 tests passed.
```

**VERIFIED: Logic 100% identical. 57% reduction from single-line structs and comment removal.**
