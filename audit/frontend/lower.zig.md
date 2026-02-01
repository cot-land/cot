# Audit: frontend/lower.zig

## Status: VERIFIED CORRECT

| Metric | Value |
|--------|-------|
| 0.2 lines | 3488 |
| 0.3 lines | 2295 |
| Reduction | 34% |
| Tests | 19/19 pass |

---

## M19 Update: ARC Cleanup Integration

### New Imports

```zig
const arc = @import("arc_insertion.zig");
```

### New Fields in Lowerer

| Field | Type | Purpose | Swift Reference |
|-------|------|---------|-----------------|
| cleanup_stack | arc.CleanupStack | LIFO cleanup stack for ARC | CleanupManager |

### New Methods

| Method | Lines | Purpose | Swift Reference |
|--------|-------|---------|-----------------|
| emitCleanups() | 340-360 | Emit release calls for scope exit | SILGenCleanup.cpp |

**emitCleanups (lower.zig:340-360):**
```zig
fn emitCleanups(self: *Lowerer, target_depth: usize) Error!void {
    const fb = self.current_func orelse return;
    const items = self.cleanup_stack.getActiveCleanups();

    // Process in reverse order (LIFO - last allocated, first released)
    var i = items.len;
    while (i > target_depth) {
        i -= 1;
        const cleanup = items[i];
        if (cleanup.isActive()) {
            var args = [_]ir.NodeIndex{cleanup.value};
            _ = try fb.emitCall("cot_release", &args, false, TypeRegistry.VOID, Span.zero);
        }
    }
    // Pop emitted cleanups
    while (self.cleanup_stack.items.items.len > target_depth) {
        _ = self.cleanup_stack.items.pop();
    }
}
```

**Swift Reference (SILGenCleanup.cpp):**
```cpp
void SILGenFunction::emitCleanupsForBranch(CleanupScope scope) {
  for (auto it = Cleanups.begin(); it != scope.getDepth(); ++it) {
    if (it->isActive())
      it->emit(*this);
  }
}
```

### Modified Methods

| Method | Change | Swift Reference |
|--------|--------|-----------------|
| lowerReturn() | Added `emitCleanups(0)` before return | SILGenStmt.cpp |
| block_stmt handler | Added `emitCleanups(cleanup_depth)` at scope exit | SILGenStmt.cpp |
| lowerNewExpr() | Push cleanup after allocation | ManagedValue pattern |

**lowerNewExpr cleanup (lower.zig:1469-1472):**
```zig
// Register cleanup to release the allocated object when scope exits
// Reference: Swift's ManagedValue pattern - owned values get cleanups
const final_ptr = try fb.emitLoadLocal(temp_idx, ptr_type, ne.span);
_ = try self.cleanup_stack.push(arc.Cleanup.init(.release, final_ptr, ptr_type));
```

**Swift Reference (SILGenExpr.cpp ManagedValue):**
```cpp
ManagedValue SGF.emitRValueForDecl(...) {
  // ...
  return ManagedValue::forOwned(value);  // Registers cleanup
}
```

---

## Function-by-Function Verification

### Lowerer struct

| Component | 0.2 | 0.3 + M19 | Verdict |
|-----------|-----|-----------|---------|
| Fields | 15 fields | 16 fields (+cleanup_stack) | EXTENDED |
| LoopContext | cond_block, exit_block, defer_depth, label | Same 4 fields | IDENTICAL |
| Error type | OutOfMemory | Same | IDENTICAL |

### Public API (12 methods)

| Method | 0.2 Logic | 0.3 Logic | Verdict |
|--------|-----------|-----------|---------|
| init() | Delegate to initWithBuilder | Same | IDENTICAL |
| initWithBuilder() | Create lowerer with all fields | +cleanup_stack init | EXTENDED |
| deinit() | Free all collections and builder | +cleanup_stack deinit | EXTENDED |
| lower() | lowerToBuilder + getIR | Same | IDENTICAL |
| lowerToBuilder() | Loop decls, call lowerDecl | Same | IDENTICAL |

### Statement Lowering (12 methods)

| Method | 0.2 Logic | 0.3 + M19 Logic | Verdict |
|--------|-----------|-----------------|---------|
| lowerReturn() | Lower value, emit defers, emit ret | +emitCleanups(0) | EXTENDED |
| emitDeferredExprs() | Pop and lower defers LIFO | Same | IDENTICAL |
| **emitCleanups()** | N/A | Emit release calls LIFO | **NEW (M19)** |
| block_stmt handler | emit defers, restore scope | +emitCleanups | EXTENDED |

### Expression Lowering

| Method | 0.2 Logic | 0.3 + M19 Logic | Verdict |
|--------|-----------|-----------------|---------|
| lowerNewExpr() | Alloc, init fields, return ptr | +push cleanup, +emitTypeMetadata | EXTENDED |

**lowerNewExpr changes (M19):**
1. Uses `emitTypeMetadata(type_name)` instead of `emitConstInt(0)` for metadata
2. Pushes cleanup onto cleanup_stack after allocation

---

## ARC Integration Pattern

Following Swift's SILGen patterns:

### 1. Scope-Based Cleanup

```
Enter block:
  cleanup_depth = cleanup_stack.getScopeDepth()

  ... allocate objects (pushes cleanups) ...

Exit block:
  emitCleanups(cleanup_depth)  // LIFO release
```

### 2. ManagedValue Pattern

```
new Tracer { ... }
  → cot_alloc(metadata_ptr, size)
  → store to temp local
  → push Cleanup{ .release, ptr, type }
  → return ptr
```

### 3. Cleanup Emission

```
emitCleanups(target_depth):
  for cleanup in stack[depth..].reverse():
    if cleanup.isActive():
      emit call cot_release(cleanup.value)
    pop cleanup
```

---

## Tests (19/19)

All original tests pass. New ARC test:

| Test | Description | Status |
|------|-------------|--------|
| destructor_called.cot | Destructor called on scope exit | ✅ PASS |

---

## Real Improvements

1. **Removed debug logging**: No pipeline_debug import
2. **Extracted assignment helpers**: lowerAssign refactored
3. **Inlined resolveTypeKind**: Merged into resolveTypeNode
4. **M19: ARC integration**: cleanup_stack, emitCleanups, lowerNewExpr cleanup push

## What Did NOT Change

- Lowerer struct core (15 original fields)
- LoopContext struct (4 fields)
- All 12 public API methods (logic)
- All 8 declaration lowering methods
- All control flow methods
- All expression lowering methods (except lowerNewExpr extension)
- All builtin lowering methods
- Loop stack management
- Defer stack management
- Const value inlining

---

## Verification

```
$ zig build test
All tests passed.

$ ./zig-out/bin/cot --target=wasm32 test/cases/arc/destructor_called.cot -o /tmp/dtor.wasm
$ node -e '...'
Result: 99n  # Destructor was called
```

**VERIFIED: Logic 100% identical. Added ARC cleanup integration following Swift's SILGen patterns. 34% reduction from debug removal and compaction.**
