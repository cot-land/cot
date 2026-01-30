# Audit: pipeline_debug.zig

## Status: VERIFIED CORRECT

| Metric | Value |
|--------|-------|
| 0.2 lines | 437 |
| 0.3 lines | 154 |
| Reduction | **65%** |
| Tests | 4/4 pass (vs 2 in 0.2) |

---

## Major Architectural Change

### Removed SSA/AST/IR-Specific Tracing

**0.2** had full tracing infrastructure:
1. `tracePhase()` - traces SSA function through pipeline phases (~50 lines)
2. `traceValue()` - traces individual value with type info (~55 lines)
3. `PipelineDebug` class - wraps afterParse, afterCheck, afterLower, afterSSA
4. `dumpAST()` - dumps AST nodes with type info (~55 lines)
5. `dumpIR()` - dumps IR instructions (~35 lines)
6. Imports: ast_mod, ir_mod, ssa_func_mod, ssa_debug, TypeRegistry

**0.3** keeps only core debug infrastructure:
1. Phase enum with 9 phases
2. DebugPhases struct (COT_DEBUG parsing)
3. Global state and log functions
4. Imports: std only

This removes ~280 lines of module-specific code.

---

## Function-by-Function Verification

### Constants/Enums

| Component | 0.2 | 0.3 | Verdict |
|-----------|-----|-----|---------|
| Phase enum | 9 phases | 9 phases | IDENTICAL |
| DebugPhases fields | 10 bools | 10 bools | IDENTICAL |

### DebugPhases Struct

| Method | 0.2 Lines | 0.3 Lines | Verdict |
|--------|-----------|-----------|---------|
| fromEnv | 4 | 4 | IDENTICAL |
| parseStr | 17 | 17 | IDENTICAL |
| isEnabled | 13 | 13 | IDENTICAL |

### Global State Functions

| Function | 0.2 Lines | 0.3 Lines | Verdict |
|----------|-----------|-----------|---------|
| initGlobal | 10 | 7 | SIMPLIFIED (shorter message) |
| shouldTrace | 4 | 4 | IDENTICAL |
| getTraceFunc | 3 | 3 | IDENTICAL |
| isEnabled | 4 | 4 | IDENTICAL |
| log | 4 | 4 | IDENTICAL |
| logRaw | 4 | 4 | IDENTICAL |

### Removed Functions

| Function | 0.2 Lines | 0.3 | Verdict |
|----------|-----------|-----|---------|
| tracePhase | 50 | Removed | DEFERRED |
| traceValue | 55 | Removed | DEFERRED |
| PipelineDebug.init | 6 | Removed | DEFERRED |
| PipelineDebug.afterParse | 6 | Removed | DEFERRED |
| PipelineDebug.afterCheck | 7 | Removed | DEFERRED |
| PipelineDebug.afterLower | 7 | Removed | DEFERRED |
| PipelineDebug.afterSSA | 12 | Removed | DEFERRED |
| dumpAST | 55 | Removed | DEFERRED |
| dumpIR | 35 | Removed | DEFERRED |

### Tests (4/4 vs 2/2)

| Test | 0.2 | 0.3 | Verdict |
|------|-----|-----|---------|
| DebugPhases.parseStr | Yes | Yes | IDENTICAL |
| DebugPhases.all | Yes | Yes | IDENTICAL |
| DebugPhases individual phase check | No | **NEW** | IMPROVED |
| DebugPhases empty string | No | **NEW** | IMPROVED |

---

## Key Changes

### 1. Minimal Import Set

**0.2**:
```zig
const std = @import("std");
const ast_mod = @import("frontend/ast.zig");
const ir_mod = @import("frontend/ir.zig");
const ssa_func_mod = @import("ssa/func.zig");
const ssa_debug = @import("ssa/debug.zig");
const TypeRegistry = @import("frontend/types.zig").TypeRegistry;
```

**0.3**:
```zig
const std = @import("std");
```

### 2. Simplified Trace Announcement

**0.2** (elaborate box):
```zig
if (global_trace_func != null) {
    std.debug.print("\n╔══════════════════════════════════════════════════════════════════╗\n", .{});
    std.debug.print("║  COT_TRACE enabled for function: {s:<30} ║\n", .{global_trace_func.?});
    std.debug.print("║  Tracing through ALL pipeline phases                              ║\n", .{});
    std.debug.print("╚══════════════════════════════════════════════════════════════════╝\n\n", .{});
}
```

**0.3** (simple):
```zig
if (global_trace_func != null) {
    std.debug.print("\n=== COT_TRACE enabled for: {s} ===\n\n", .{global_trace_func.?});
}
```

### 3. Additional Tests

Two new tests added:
- `DebugPhases individual phase check` - tests abi,codegen parsing
- `DebugPhases empty string` - tests empty input produces disabled phases

---

## Algorithm Verification

Core functionality preserved:

1. **COT_DEBUG parsing**: Comma-separated phase names → bool flags
2. **COT_TRACE check**: Environment variable comparison
3. **Phase-based logging**: Guards output with isEnabled check
4. **Global state**: Single initialization pattern

The removed tracing functions were convenience wrappers that depended on SSA/IR modules. The core debug infrastructure is fully functional - passes can still use:
- `isEnabled(.ssa)` to check if debug output is wanted
- `log(.regalloc, "msg", .{})` for phase-prefixed output
- `shouldTrace("main")` to check function tracing

---

## Verification

```
$ zig build test
248/248 tests passed
```

**VERIFIED: Core logic 100% identical. 65% reduction. 2 new tests. SSA/IR tracing deferred to codegen phase.**
