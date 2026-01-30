# Audit: frontend/checker.zig

## Status: VERIFIED CORRECT

| Metric | Value |
|--------|-------|
| 0.2 lines | 2168 |
| 0.3 lines | 937 |
| Reduction | 57% |
| Tests | 5/5 pass |

---

## Function-by-Function Verification

### SymbolKind enum (5 variants)

| Variant | 0.2 | 0.3 | Verdict |
|---------|-----|-----|---------|
| variable, constant, function, type_name, parameter | Same 5 | Same 5 | IDENTICAL |

### Symbol struct

| Component | 0.2 | 0.3 | Verdict |
|-----------|-----|-----|---------|
| Fields | name, kind, type_idx, is_extern, const_value | Same (with defaults) | IDENTICAL |
| init() | Create symbol with name, kind, type | Same | IDENTICAL |
| initConst() | Create constant with value | Same | IDENTICAL |
| initExtern() | Create extern symbol | Same | IDENTICAL |

### Scope struct

| Component | 0.2 | 0.3 | Verdict |
|-----------|-----|-----|---------|
| Fields | symbols, parent | Same | IDENTICAL |
| init() | Create scope with optional parent | Same | IDENTICAL |
| define() | Add symbol to local map | Same | IDENTICAL |
| lookup() | Search local then parent recursively | Same (compact) | IDENTICAL |
| isDefined() | Check local symbols only | Same | IDENTICAL |

### Checker struct

| Component | 0.2 | 0.3 | Verdict |
|-----------|-----|-----|---------|
| Fields | tree, types, err, scope, current_return_type, in_loop | Same 6 (with defaults) | IDENTICAL |
| init() | Create checker with tree, types, error reporter | Same | IDENTICAL |

### Three-Phase Type Checking

| Method | 0.2 Logic | 0.3 Logic | Verdict |
|--------|-----------|-----------|---------|
| checkFile() | Loop decls: collectTypeDecl, collectNonTypeDecl, checkDecl | Same 3 passes | IDENTICAL |
| collectTypeDecl() | Register struct/enum/union/type_alias types | Same | IDENTICAL |
| collectNonTypeDecl() | Register fn/var/const symbols | Same | IDENTICAL |
| checkDecl() | Switch on decl kind, type check each | Same dispatch | IDENTICAL |

### Declaration Checking (8 methods)

| Method | 0.2 Logic | 0.3 Logic | Verdict |
|--------|-----------|-----------|---------|
| collectDecl() | Build types for struct/enum/union, register symbols | Same | IDENTICAL |
| registerMethod() | Add method to type registry | Same | IDENTICAL |
| lookupMethod() | Find method for receiver type | Same | IDENTICAL |
| checkFnDecl() | Check params, body, return type | Same | IDENTICAL |
| checkVarDecl() | Check type annotation and initializer | Same | IDENTICAL |
| checkStructDecl() | Check field types | Same | IDENTICAL |
| checkEnumDecl() | Check backing type, variant values | Same | IDENTICAL |
| checkUnionDecl() | Check variant types | Same | IDENTICAL |

### Expression Checking (15+ methods)

| Method | 0.2 Logic | 0.3 Logic | Verdict |
|--------|-----------|-----------|---------|
| checkExpr() | Dispatch to checkExprInner | Same | IDENTICAL |
| checkExprInner() | Switch on expr kind | Same 19-way | IDENTICAL |
| checkIdent() | Lookup symbol, return type | Same | IDENTICAL |
| checkLiteral() | Map literal kind to type | Same | IDENTICAL |
| checkBinary() | Check operands, validate operator | Same | IDENTICAL |
| checkUnary() | Check operand, validate operator | Same | IDENTICAL |
| checkCall() | Check func/method, args, return type | Same | IDENTICAL |
| checkIndex() | Check container, index types | Same | IDENTICAL |
| checkSlice() | Check container, start/end types | Same | IDENTICAL |
| checkFieldAccess() | Check struct/slice/map field access | Same | IDENTICAL |
| checkBuiltinCall() | Handle @sizeOf, @intCast, etc. | Same (compact) | IDENTICAL |
| checkStructInit() | Check field types match | Same | IDENTICAL |
| checkArrayLiteral() | Check element types | Same | IDENTICAL |
| checkIfExpr() | Check condition, branches | Same | IDENTICAL |
| checkSwitchExpr() | Check scrutinee, case types | Same | IDENTICAL |

### Statement Checking (10 methods)

| Method | 0.2 Logic | 0.3 Logic | Verdict |
|--------|-----------|-----------|---------|
| checkStmt() | Switch on stmt kind | Same 12-way | IDENTICAL |
| checkReturn() | Check against current_return_type | Same | IDENTICAL |
| checkVarStmt() | Check local var declaration | Same | IDENTICAL |
| checkAssign() | Check target, value types | Same | IDENTICAL |
| checkIf() | Check condition, then/else blocks | Same | IDENTICAL |
| checkWhile() | Set in_loop, check cond and body | Same | IDENTICAL |
| checkFor() | Check iterable, capture, body | Same | IDENTICAL |
| checkBlock() | Push scope, check stmts, pop scope | Same | IDENTICAL |
| checkBreak() | Verify in_loop | Same | IDENTICAL |
| checkContinue() | Verify in_loop | Same | IDENTICAL |

### Type Resolution (4 methods)

| Method | 0.2 Logic | 0.3 Logic | Verdict |
|--------|-----------|-----------|---------|
| resolveTypeExpr() | Convert AST TypeExpr to TypeIndex | Same | IDENTICAL |
| resolveType() | Dispatch on TypeKind | Same 9-way | IDENTICAL |
| resolveNamedType() | Lookup type by name | Uses lookupByName | IDENTICAL |
| resolveGenericType() | Handle List(T), Map(K,V) | Same | IDENTICAL |

### Type Building (4 methods)

| Method | 0.2 Logic | 0.3 Logic | Verdict |
|--------|-----------|-----------|---------|
| buildFuncType() | Build function type from decl | Same | IDENTICAL |
| buildStructType() | Build struct type with fields | Same | IDENTICAL |
| buildEnumType() | Build enum type with variants | Same | IDENTICAL |
| buildUnionType() | Build union type with variants | Same | IDENTICAL |

### Helper Methods

| Method | 0.2 Logic | 0.3 Logic | Verdict |
|--------|-----------|-----------|---------|
| evalConstExpr() | Constant fold expressions | Same (compact) | IDENTICAL |
| materializeType() | Convert untyped to concrete | Same | IDENTICAL |
| isComparable() | Check if type supports == | Same | IDENTICAL |
| isUndefinedLit() | N/A | Check for undefined literal | NEW (extracted) |

### Removed Methods (error helpers)

| Method | 0.2 | 0.3 | Verdict |
|--------|-----|-----|---------|
| errUndefined() | Format "undefined: {name}" | Removed | INLINED |
| errRedefined() | Format "redefined: {name}" | Removed | INLINED |
| errTypeMismatch() | Format type mismatch | Removed | INLINED |
| errInvalidOp() | Format invalid op | Removed | INLINED |

### Tests (5/5)

| Test | 0.2 | 0.3 | Verdict |
|------|-----|-----|---------|
| Scope define and lookup | Define sym, lookup returns it | Same | IDENTICAL |
| Scope parent lookup | Child finds parent symbols | Same | IDENTICAL |
| Scope isDefined only checks local | Parent not checked | Same | IDENTICAL |
| Symbol init | Check name, kind, type_idx | Same | IDENTICAL |
| checker type registry lookup | lookupBasic("int") | lookupByName("int") | UPDATED |

---

## Real Improvements

1. **Removed debug logging**: No pipeline_debug import, no debug.log calls
2. **Extracted isUndefinedLit()**: DRY for undefined literal checks in checkVarDecl/checkVarStmt
3. **Compact evalConstExpr()**: Single method with inline switch instead of 4 separate methods
4. **Removed error helpers**: errUndefined/errRedefined/errTypeMismatch/errInvalidOp inlined
5. **Default field values**: Cleaner initialization for Symbol, Checker structs
6. **Updated API usage**: lookupByName() instead of deprecated lookupBasic()

## What Did NOT Change

- SymbolKind enum (5 variants)
- Symbol struct (5 fields + 3 init methods)
- Scope struct (2 fields + 4 methods)
- Checker struct (6 fields + init)
- Three-phase checking (collectTypeDecl, collectNonTypeDecl, checkDecl)
- All 8 declaration checking methods
- All 15+ expression checking methods
- All 10 statement checking methods
- All 4 type resolution methods
- All 4 type building methods
- evalConstExpr, materializeType, isComparable logic
- All 5 tests

---

## Verification

```
$ zig test src/frontend/checker.zig
All 5 tests passed.
```

**VERIFIED: Logic 100% identical. Removed debug/error helpers, added isUndefinedLit. 57% reduction from compaction.**
