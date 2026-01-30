# Audit: frontend/errors.zig

## Status: VERIFIED CORRECT

| Metric | Value |
|--------|-------|
| 0.2 lines | 347 |
| 0.3 lines | 224 |
| Reduction | 36% |
| Tests | 7/7 pass |

---

## Function-by-Function Verification

### ErrorCode enum

| Component | 0.2 | 0.3 | Verdict |
|-----------|-----|-----|---------|
| Scanner codes | e100-e104 (5 codes) | Same | IDENTICAL |
| Parser codes | e200-e208 (9 codes) | Same | IDENTICAL |
| Type codes | e300-e306 (7 codes) | Same | IDENTICAL |
| Semantic codes | e400-e403 (4 codes) | Same | IDENTICAL |
| Total codes | 25 | 25 | IDENTICAL |

### ErrorCode methods

| Method | 0.2 Logic | 0.3 Logic | Verdict |
|--------|-----------|-----------|---------|
| code() | `return @intFromEnum(self)` | Same | IDENTICAL |
| description() | 25-way switch returning description strings | Same 25 cases, same strings | IDENTICAL |

All description strings verified identical:
- e100: "unterminated string literal"
- e101: "unterminated character literal"
- e200: "unexpected token"
- e300: "type mismatch"
- e400: "break outside loop"
- (etc.)

### Error struct

| Component | 0.2 | 0.3 | Verdict |
|-----------|-----|-----|---------|
| span field | Span | Same | IDENTICAL |
| msg field | []const u8 | Same | IDENTICAL |
| code field | `code: ?ErrorCode = null` | `err_code: ?ErrorCode = null` | RENAMED (cosmetic) |

### Error methods

| Method | 0.2 Logic | 0.3 Logic | Verdict |
|--------|-----------|-----------|---------|
| at() | Return Error with Span.fromPos, msg, null code | Same | IDENTICAL |
| withCode() | Return Error with Span.fromPos, msg, code | Same (field name changed) | IDENTICAL |
| atSpan() | Return Error with span, msg, null code | Same | IDENTICAL |

### ErrorHandler and MAX_ERRORS

| Component | 0.2 | 0.3 | Verdict |
|-----------|-----|-----|---------|
| ErrorHandler | `*const fn (err: Error) void` | Same | IDENTICAL |
| MAX_ERRORS | 10 | 10 | IDENTICAL |

### ErrorReporter struct

| Component | 0.2 | 0.3 | Verdict |
|-----------|-----|-----|---------|
| Fields | src, handler, first, count, suppressed | Same 5 fields | IDENTICAL |

### ErrorReporter methods

| Method | 0.2 Logic | 0.3 Logic | Verdict |
|--------|-----------|-----------|---------|
| init() | Return struct with 5 fields initialized | Same (compact) | IDENTICAL |
| errorAt() | `self.report(Error.at(pos, msg))` | Same | IDENTICAL |
| errorWithCode() | `self.report(Error.withCode(pos, err_code, msg))` | Same | IDENTICAL |
| errorAtSpan() | `self.report(Error.atSpan(span, msg))` | Same | IDENTICAL |
| report() | Set first if null, increment count, check MAX_ERRORS, call handler or printError | Same (compact) | IDENTICAL |
| printError() | Get position, print with/without code, print line, print caret | Same | IDENTICAL |
| hasErrors() | `return self.count > 0` | Same | IDENTICAL |
| errorCount() | `return self.count` | Same | IDENTICAL |
| firstError() | `return self.first` | Same | IDENTICAL |

### printError format

| Format | 0.2 | 0.3 | Verdict |
|--------|-----|-----|---------|
| With code | `{filename}:{line}:{col}: error[E{code}]: {msg}` | Same | IDENTICAL |
| Without code | `{filename}:{line}:{col}: error: {msg}` | Same | IDENTICAL |
| Source line | `    {line text}` | Same | IDENTICAL |
| Caret | Spaces/tabs + `^` at column | Same | IDENTICAL |

### Tests (7/7)

| Test | 0.2 | 0.3 | Verdict |
|------|-----|-----|---------|
| ErrorCode description | Check e100, e200, e300 | Same | IDENTICAL |
| ErrorCode code | Check e100=100, e200=200 | Same | IDENTICAL |
| Error creation | Test at() and withCode() | Same (field name adjusted) | IDENTICAL |
| ErrorReporter basic | Init, check hasErrors, report, check count | Same | IDENTICAL |
| ErrorReporter with code | Report with e100, check firstError | Same | IDENTICAL |
| ErrorReporter multiple errors | Report 3 errors, check count and first | Same | IDENTICAL |
| ErrorReporter custom handler | Test handler callback | Same | IDENTICAL |

---

## Changes

1. **Field rename**: `Error.code` -> `Error.err_code` (avoids confusion with `code()` method)
2. **Compact enum layout**: Multiple error codes per line
3. **Compact methods**: Single-line conditionals
4. **Removed doc comments**

## What Did NOT Change

- All 25 error codes (same values, same descriptions)
- All Error methods (at, withCode, atSpan)
- ErrorHandler type and MAX_ERRORS constant
- All ErrorReporter methods (same logic)
- Error output format (filename:line:col: error: msg)
- All 7 tests

---

## Verification

```
$ zig test src/frontend/errors.zig
All 7 tests passed.
```

**VERIFIED: Logic identical. Field renamed (code->err_code). 36% reduction from compaction.**
