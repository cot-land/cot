# Cotty Dogfooding — Compiler Bugs Found

Bugs found while building Cotty (cot-land/cotty) with `"safe": true` in cot.json. Prioritized by severity.

## Bug 1: @assertEq Fails for Enum Return Values

### Reproduction

```cot
// cot-land/cotty/src/input.cot (project has "safe": true in cot.json)
const InputAction = enum(u8) {
    none, insert_char, delete_back, delete_forward,
    move_left, move_right, move_up, move_down,
    move_line_start, move_line_end, page_up, page_down,
    save, quit, new_surface, close_surface,
}

fn keyToAction(event: KeyEvent) InputAction {
    const has_ctrl = (event.mods & MOD_CTRL) != 0
    if (has_ctrl) {
        if (event.key == 's') { return InputAction.save }
        if (event.key == 'n') { return InputAction.new_surface }
        return InputAction.none
    }
    if (event.key >= 32 and event.key <= 126) { return InputAction.insert_char }
    return InputAction.none
}

// PASSES:
test "ctrl+s" {
    const event = KeyEvent { key: 's', mods: 1 }
    @assertEq(keyToAction(event), InputAction.save)       // save=12, OK
}

// FAILS:
test "ctrl+n" {
    const event = KeyEvent { key: 'n', mods: 1 }
    @assertEq(keyToAction(event), InputAction.new_surface) // expected: 0, received: 14
}

test "printable char" {
    const event = KeyEvent { key: 'a', mods: 0 }
    @assertEq(keyToAction(event), InputAction.insert_char) // expected: 0, received: 1
}
```

### Observations
- Some enum `@assertEq` comparisons pass, others fail
- ALL failures show "expected: 0" — the first operand (function return value) is always displayed as 0
- The second operand is displayed correctly (its integer enum value)
- The comparison itself (`emitBinary(.eq)`) returns false, meaning it's not just a display bug

### Root Cause Location

**`compiler/frontend/lower.zig` lines 6339-6430** — the `.assert_eq` builtin lowering.

The sequence is:
1. Line 6340-6341: Lower left and right expressions → IR nodes
2. Line 6369-6372: Store both to i64 locals (for fail-path display)
3. Line 6385: Compare with `emitBinary(.eq, left, right, BOOL)`
4. Line 6401-6402: On fail, reload from i64 locals for display

**Suspected issue at line 6369-6372:**
```zig
left_local = try fb.addLocalWithSize("__fail_left", TypeRegistry.I64, false, 8);
_ = try fb.emitStoreLocal(left_local, left, bc.span);
right_local = try fb.addLocalWithSize("__fail_right", TypeRegistry.I64, false, 8);
_ = try fb.emitStoreLocal(right_local, right, bc.span);
```

When `left` is a u8 enum return value (i32 on Wasm stack), storing to an i64 local may not correctly widen the value. The local reads back as 0.

**And at line 6385:**
```zig
} else try fb.emitBinary(.eq, left, right, TypeRegistry.BOOL, bc.span);
```

If `left` is i32 (u8 enum return) and `right` is i64 (enum constant), the `.eq` may compare different Wasm types, causing the comparison to fail even when values match logically.

### Suggested Fix

In the `.assert_eq` handler around line 6368-6373, widen both operands to i64 before storing AND before comparing:

```zig
} else {
    // Ensure both values are i64 for consistent comparison and storage
    const left_widened = if (self.type_reg.sizeOf(left_type) < 8)
        try fb.emitUnary(.extend_i64, left, TypeRegistry.I64, bc.span)
    else
        left;
    const right_widened = if (self.type_reg.sizeOf(self.inferExprType(bc.args[1])) < 8)
        try fb.emitUnary(.extend_i64, right, TypeRegistry.I64, bc.span)
    else
        right;

    left_local = try fb.addLocalWithSize("__fail_left", TypeRegistry.I64, false, 8);
    _ = try fb.emitStoreLocal(left_local, left_widened, bc.span);
    right_local = try fb.addLocalWithSize("__fail_right", TypeRegistry.I64, false, 8);
    _ = try fb.emitStoreLocal(right_local, right_widened, bc.span);
}
```

And update the comparison at line 6385 to use the widened values:
```zig
} else try fb.emitBinary(.eq, left_widened, right_widened, TypeRegistry.BOOL, bc.span);
```

Check `emitUnary(.extend_i64, ...)` exists — if not, use the appropriate wasm i32.extend_i64_u or i32.extend_i64_s op. For unsigned enums (enum(u8)), use zero-extension.

---

## Bug 2: Union Switch Fails to Match No-Payload Variants

### Reproduction

```cot
// cot-land/cotty/src/message.cot
union Message {
    open_file: string,
    close_surface: int,
    save,
    quit,
    redraw,
}

// PASSES (payload variant):
test "message open_file" {
    var msg = Message.open_file("test.cot")
    const path = switch (msg) {
        Message.open_file |p| => p,
        else => "",
    }
    @assertEq(path, "test.cot")
}

// FAILS (no-payload variant):
test "message quit tag" {
    var msg = Message.quit
    const is_quit = switch (msg) {
        Message.quit => true,
        else => false,
    }
    @assertEq(is_quit, true)   // expected: 0, received: 1
    // is_quit is false — the switch matched `else`, not `Message.quit`
}
```

### Observations
- Payload variants (`Message.open_file |p|`) match correctly in switch
- No-payload variants (`Message.quit`, `Message.save`, `Message.redraw`) always fall through to `else`
- The `msg.tag` value is correct (verified by reading tag directly)

### Root Cause Location

**`compiler/frontend/lower.zig` lines 5147-5158** — `resolveUnionVariantIndex`:

```zig
fn resolveUnionVariantIndex(self: *Lowerer, pattern_idx: NodeIndex, ut: types.UnionType) ?usize {
    const node = self.tree.getNode(pattern_idx) orelse return null;
    const expr = node.asExpr() orelse return null;
    const field_name = switch (expr) {
        .field_access => |fa| fa.field,
        else => return null,       // <-- BUG: only handles .field_access
    };
    for (ut.variants, 0..) |v, i| {
        if (std.mem.eql(u8, v.name, field_name)) return i;
    }
    return null;
}
```

This function **only handles `.field_access` AST nodes**. When the parser represents `Message.quit` in a switch arm as a different expression type (e.g., a `.call` with zero args, or an `.enum_literal`), the function returns `null`.

**Effect at lines 5076-5088:**
```zig
for (case.patterns) |pattern_idx| {
    const variant_idx = self.resolveUnionVariantIndex(pattern_idx, ut);
    if (variant_idx) |vidx| {                    // null → skipped
        // ... build condition ...
    }
}
// case_cond stays ir.null_node
if (case_cond != ir.null_node) _ = try fb.emitBranch(case_cond, case_block, next_block, se.span);
// No branch emitted → falls through to case_block unconditionally
fb.setBlock(case_block);
```

When `variant_idx` is null, `case_cond` stays `ir.null_node`, no branch is emitted, and control falls through to the case block unconditionally. BUT the case block code is immediately followed by a jump to merge, so the actual behavior is that the **first unresolved case** gets executed unconditionally, and subsequent cases are skipped.

Wait — actually re-reading: `fb.setBlock(case_block)` just sets the current block. The `next_block` check never happens. So the code IS entered. But then for the NEXT case (else), its `case_block` is set as current. The net effect is the `else` arm's code becomes the active code path, since no branch ever diverts to the earlier case.

### Suggested Fix

Extend `resolveUnionVariantIndex` to handle all expression types that can represent union variants:

```zig
fn resolveUnionVariantIndex(self: *Lowerer, pattern_idx: NodeIndex, ut: types.UnionType) ?usize {
    const node = self.tree.getNode(pattern_idx) orelse return null;
    const expr = node.asExpr() orelse return null;
    const field_name = switch (expr) {
        .field_access => |fa| fa.field,
        .call => |call| blk: {
            // Handle Message.quit() parsed as a call with zero args
            const callee_node = self.tree.getNode(call.func) orelse return null;
            const callee_expr = callee_node.asExpr() orelse return null;
            break :blk switch (callee_expr) {
                .field_access => |fa| fa.field,
                else => return null,
            };
        },
        else => return null,
    };
    for (ut.variants, 0..) |v, i| {
        if (std.mem.eql(u8, v.name, field_name)) return i;
    }
    return null;
}
```

**Also add a safety check at line 5088** to prevent silent fallthrough:
```zig
if (case_cond != ir.null_node) {
    _ = try fb.emitBranch(case_cond, case_block, next_block, se.span);
} else {
    // Pattern resolution failed — jump to next to skip this case
    _ = try fb.emitJump(next_block, se.span);
}
fb.setBlock(case_block);
```

### Debug tip

To determine what AST node type the parser produces for `Message.quit` in a switch arm, add a debug log in `resolveUnionVariantIndex`:

```zig
const expr = node.asExpr() orelse return null;
debug.log(.codegen, "resolveUnionVariantIndex: expr tag = {s}", .{@tagName(expr)});
```

This will show whether it's `.field_access`, `.call`, `.enum_literal`, or something else.

---

## Bug 3: @assertEq Fails for Bool Comparisons (Same Root Cause as Bug 1)

### Reproduction

```cot
// cot-land/cotty/src/config.cot
test "config parse line show_line_numbers" {
    var cfg = Config.init()           // show_line_numbers defaults to true
    cfg.parseLine("show_line_numbers = false")
    @assertEq(cfg.show_line_numbers, false)   // expected: 1, received: 0
}
```

### Analysis

Same root cause as Bug 1 — `bool` is a small type (1 byte). The `@assertEq` stores to an i64 local without proper widening. The comparison also fails because the bool value is on the stack as i32 but compared against an i64 constant.

The fix for Bug 1 (widening all small types to i64 before comparison) should fix this too.

---

## Bug 4: Compiler Crash on app.cot (Codegen Null Panic)

### Reproduction

```bash
cot test src/app.cot
# thread panic: attempt to use null value
# in wasm_to_clif.stack.TranslationState.pop1
# in wasm_to_clif.translator.FuncTranslator.translateLocalSet
```

### Analysis

The compiler crashes during native codegen (wasm→clif translation) when translating a `local.set` instruction. The Wasm stack is empty when it expects a value — `pop1` returns null because there's nothing to pop.

**Location:** `compiler/codegen/native/wasm_to_clif/stack.zig` → `TranslationState.pop1`

This is likely triggered by more complex patterns in app.cot:
- `List(Surface)` and `List(Message)` — generic container types with struct payloads
- `?int` optional type with union switch (`focused_surface`)
- Union switch with `Message` payloads inside `handleMessage()`

The Wasm bytecode generated for one of these patterns has a `local.set` without a preceding value on the stack, which is invalid Wasm. This points to a bug in `compiler/frontend/lower.zig` or `compiler/ssa/` producing malformed Wasm output.

### Suggested Investigation

1. Add `--emit-wasm` or equivalent to dump the Wasm bytecode for app.cot
2. Find the function with the invalid `local.set` (probably `handleMessage` or `drainMailbox`)
3. Trace back to which IR lowering step produced the empty-stack situation
4. Likely related to union switch codegen for `Message` (since Bug 2 shows pattern resolution issues)

Note: `cot check src/app.cot` passes — the crash is specifically in native codegen (wasm→clif translation), not in the frontend. This also blocks `cot run src/main.cot` since main.cot imports app.cot.

This is the highest-priority bug since it crashes the compiler entirely and blocks all `cot run` and `cot test` on files that import app.cot.

---

## Bug 5: String Comparison in @assertEq Shows Memory Corruption

### Reproduction

```cot
// cot-land/cotty/src/surface.cot
test "surface title with filepath" {
    var s = Surface.init()
    s.filepath = "test.cot"
    @assertEq(s.title(), "test.cot")
    // expected: "test.cotbuffer init empty       buffer insert single char       "
    // received: "test.cot"
}
```

### Analysis

The "expected" string (`s.title()` return value) shows `"test.cot"` followed by garbage data from other test strings. This suggests the string returned by `title()` has the correct pointer but an incorrect length, causing the display to read past the end of the string into adjacent memory.

The `title()` method uses optional unwrap:
```cot
fn title() string {
    if (self.filepath) |path| { return path }
    return "untitled"
}
```

The optional unwrap of `?string` may not be correctly extracting the string length, or the `@assertEq` string comparison path may be using a wrong length value from the fail-path locals.

---

## Priority Order

1. **Bug 4** (compiler crash) — blocks all app.cot testing
2. **Bug 1 + Bug 3** (@assertEq with small types) — blocks enum and bool test assertions
3. **Bug 2** (union switch no-payload) — blocks union switch pattern matching
4. **Bug 5** (string memory) — blocks optional string comparisons

---

## Testing Plan

After fixing, these commands should all pass in `cot-land/cotty/`:

```bash
cot test src/input.cot      # Enum @assertEq tests
cot test src/message.cot     # Union switch no-payload tests
cot test src/buffer.cot      # Gap buffer tests
cot test src/app.cot         # App lifecycle (uses union switch internally)
cot test src/surface.cot     # Surface tests
cot test src/cursor.cot      # Already passing
cot test src/config.cot      # Config tests
cot check src/main.cot       # Full project type-check (already passing)
cot run src/main.cot -- help  # CLI dispatch
```

Also run the existing compiler test suite to ensure no regressions:
```bash
cot test test/e2e/features.cot
cot test test/cases/union.cot
```

Consider adding dedicated test cases:
```cot
// test/cases/union.cot — add:
test "switch no-payload variant" {
    union Action { Run, Stop, Pause: int }
    var a = Action.Stop
    const matched = switch (a) {
        Action.Stop => true,
        else => false,
    }
    @assertEq(matched, true)
}

// test/cases/enum.cot — add:
test "assertEq with enum(u8)" {
    const Color = enum(u8) { Red, Green, Blue }
    @assertEq(Color.Green, Color.Green)
}
```
