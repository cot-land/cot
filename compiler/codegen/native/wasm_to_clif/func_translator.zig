//! Function-level Wasm to CLIF translator.
//!
//! Port of wasmtime/crates/cranelift/src/translate/func_translator.rs
//!
//! The `FuncTranslator` struct translates a single WebAssembly function
//! to CLIF IR. It can be reused for multiple functions.

const std = @import("std");
const stack_mod = @import("stack.zig");
const translator_mod = @import("translator.zig");

pub const Block = stack_mod.Block;
pub const Value = stack_mod.Value;
pub const TranslationState = stack_mod.TranslationState;
pub const Translator = translator_mod.Translator;
pub const ClifOpcode = translator_mod.ClifOpcode;
pub const WasmOpcode = translator_mod.WasmOpcode;

// ============================================================================
// Wasm Value Type
// ============================================================================

pub const WasmValType = enum {
    i32,
    i64,
    f32,
    f64,
    v128,
    funcref,
    externref,
};

// ============================================================================
// Local Declaration
// ============================================================================

pub const LocalDecl = struct {
    count: u32,
    val_type: WasmValType,
};

// ============================================================================
// Function Signature (simplified)
// ============================================================================

pub const FuncSignature = struct {
    params: []const WasmValType,
    results: []const WasmValType,
};

// ============================================================================
// FuncTranslator
// ============================================================================

/// WebAssembly to CLIF IR function translator.
///
/// A `FuncTranslator` is used to translate a binary WebAssembly function into CLIF IR.
/// A single translator instance can be reused to translate multiple functions.
pub const FuncTranslator = struct {
    /// Underlying code translator.
    translator: Translator,
    /// Allocator.
    allocator: std.mem.Allocator,
    /// Number of return values for current function.
    num_returns: usize,

    const Self = @This();

    /// Create a new translator.
    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .translator = Translator.init(allocator),
            .allocator = allocator,
            .num_returns = 0,
        };
    }

    /// Deallocate storage.
    pub fn deinit(self: *Self) void {
        self.translator.deinit();
    }

    /// Translate a WebAssembly function.
    ///
    /// The function body is provided as a sequence of operators.
    /// Local declarations are provided separately.
    pub fn translateFunction(
        self: *Self,
        signature: FuncSignature,
        locals: []const LocalDecl,
        operators: []const WasmOperator,
    ) !void {
        // Save return count for use after translation
        self.num_returns = signature.results.len;

        // 1. Calculate total number of locals (params + declared locals)
        var num_locals: u32 = @intCast(signature.params.len);
        for (locals) |local| {
            num_locals += local.count;
        }

        // 2. Initialize the translator for this function
        try self.translator.initializeFunction(num_locals, signature.results.len);

        // 3. Create entry block and set up parameters
        const entry_block = self.translator.createBlock();
        _ = entry_block;

        // Push parameter values onto the stack (they become the initial locals)
        // In real translation, these would come from block params
        for (signature.params) |_| {
            const param_val = self.translator.createValue();
            try self.translator.state.push1(param_val);
        }

        // 4. Initialize declared locals to their default values
        // (i32/i64 -> 0, f32/f64 -> 0.0)
        for (locals) |local| {
            for (0..local.count) |_| {
                switch (local.val_type) {
                    .i32, .i64 => {
                        try self.translator.translateI32Const(0);
                        _ = self.translator.state.pop1();
                    },
                    else => {
                        // For other types, just create a placeholder value
                        _ = self.translator.createValue();
                    },
                }
            }
        }

        // 5. Translate the function body
        for (operators) |op| {
            try self.translateOperator(op);
        }

        // 6. The final End operator should leave us at the exit block
        // Add return instruction if reachable
        // (The final `end` pops the function frame, so control stack is empty now)
        if (self.translator.state.isReachable()) {
            // Pop return values and emit return
            if (self.num_returns > 0) {
                self.translator.state.popn(self.num_returns);
            }
            try self.translator.emitVoid(.return_op, .{ null, null, null }, 0, null, null);
        }
    }

    /// Translate a single Wasm operator.
    fn translateOperator(self: *Self, op: WasmOperator) !void {
        switch (op) {
            // Control flow
            .block => |data| try self.translator.translateBlock(data.params, data.results),
            .loop => |data| try self.translator.translateLoop(data.params, data.results),
            .if_op => |data| try self.translator.translateIf(data.params, data.results),
            .else_op => try self.translator.translateElse(),
            .end => try self.translator.translateEnd(),
            .br => |depth| try self.translator.translateBr(depth),
            .br_if => |depth| try self.translator.translateBrIf(depth),
            .br_table => |data| try self.translator.translateBrTable(data.targets, data.default),
            .return_op => try self.translator.translateReturn(),
            .unreachable_op => {
                self.translator.state.reachable = false;
            },
            .nop => {},

            // Variables
            .local_get => |idx| try self.translator.translateLocalGet(idx),
            .local_set => |idx| try self.translator.translateLocalSet(idx),
            .local_tee => |idx| try self.translator.translateLocalTee(idx),

            // Constants
            .i32_const => |val| try self.translator.translateI32Const(val),
            .i64_const => |val| try self.translator.translateI64Const(val),

            // Arithmetic
            .i32_add => try self.translator.translateI32Add(),
            .i32_sub => try self.translator.translateI32Sub(),
            .i32_mul => try self.translator.translateI32Mul(),
            .i32_div_s => try self.translator.translateI32DivS(),
            .i32_div_u => try self.translator.translateI32DivU(),
            .i32_rem_s => try self.translator.translateI32RemS(),
            .i32_rem_u => try self.translator.translateI32RemU(),
            .i32_and => try self.translator.translateI32And(),
            .i32_or => try self.translator.translateI32Or(),
            .i32_xor => try self.translator.translateI32Xor(),
            .i32_shl => try self.translator.translateI32Shl(),
            .i32_shr_s => try self.translator.translateI32ShrS(),
            .i32_shr_u => try self.translator.translateI32ShrU(),
            .i32_rotl => try self.translator.translateI32Rotl(),
            .i32_rotr => try self.translator.translateI32Rotr(),

            // Comparison
            .i32_eqz => try self.translator.translateI32Eqz(),
            .i32_eq => try self.translator.translateI32Eq(),
            .i32_ne => try self.translator.translateI32Ne(),
            .i32_lt_s => try self.translator.translateI32LtS(),
            .i32_lt_u => try self.translator.translateI32LtU(),
            .i32_gt_s => try self.translator.translateI32GtS(),
            .i32_gt_u => try self.translator.translateI32GtU(),
            .i32_le_s => try self.translator.translateI32LeS(),
            .i32_le_u => try self.translator.translateI32LeU(),
            .i32_ge_s => try self.translator.translateI32GeS(),
            .i32_ge_u => try self.translator.translateI32GeU(),

            // Conversions
            .i32_wrap_i64 => try self.translator.translateI32WrapI64(),
            .i64_extend_i32_s => try self.translator.translateI64ExtendI32S(),
            .i64_extend_i32_u => try self.translator.translateI64ExtendI32U(),

            // Parametric
            .drop => try self.translator.translateDrop(),
            .select => try self.translator.translateSelect(),
        }
    }

    /// Get the emitted instructions (for testing).
    pub fn getInstructions(self: Self) []const Translator.EmittedInst {
        return self.translator.instructions.items;
    }

    /// Get the final stack state (for testing).
    pub fn getStack(self: Self) []const Value {
        return self.translator.state.stack.items;
    }
};

// ============================================================================
// WasmOperator - Tagged union for operators
// ============================================================================

pub const BlockData = struct {
    params: usize,
    results: usize,
};

pub const BrTableData = struct {
    targets: []const u32,
    default: u32,
};

pub const WasmOperator = union(enum) {
    // Control flow
    block: BlockData,
    loop: BlockData,
    if_op: BlockData,
    else_op,
    end,
    br: u32,
    br_if: u32,
    br_table: BrTableData,
    return_op,
    unreachable_op,
    nop,

    // Variables
    local_get: u32,
    local_set: u32,
    local_tee: u32,

    // Constants
    i32_const: i32,
    i64_const: i64,

    // Arithmetic i32
    i32_add,
    i32_sub,
    i32_mul,
    i32_div_s,
    i32_div_u,
    i32_rem_s,
    i32_rem_u,
    i32_and,
    i32_or,
    i32_xor,
    i32_shl,
    i32_shr_s,
    i32_shr_u,
    i32_rotl,
    i32_rotr,

    // Comparison i32
    i32_eqz,
    i32_eq,
    i32_ne,
    i32_lt_s,
    i32_lt_u,
    i32_gt_s,
    i32_gt_u,
    i32_le_s,
    i32_le_u,
    i32_ge_s,
    i32_ge_u,

    // Conversions
    i32_wrap_i64,
    i64_extend_i32_s,
    i64_extend_i32_u,

    // Parametric
    drop,
    select,
};

// ============================================================================
// Tests
// ============================================================================

test "translate simple function: (i32, i32) -> i32 { local.get 0 + local.get 1 }" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var ft = FuncTranslator.init(allocator);
    defer ft.deinit();

    const signature = FuncSignature{
        .params = &[_]WasmValType{ .i32, .i32 },
        .results = &[_]WasmValType{.i32},
    };

    const operators = [_]WasmOperator{
        .{ .local_get = 0 },
        .{ .local_get = 1 },
        .i32_add,
        .end,
    };

    try ft.translateFunction(signature, &[_]LocalDecl{}, &operators);

    // Should have at least iconst, iadd instructions
    try testing.expect(ft.getInstructions().len > 0);
}

test "translate function with local: () -> i32 { local i32; local.set 0 = 42; local.get 0 }" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var ft = FuncTranslator.init(allocator);
    defer ft.deinit();

    const signature = FuncSignature{
        .params = &[_]WasmValType{},
        .results = &[_]WasmValType{.i32},
    };

    const locals = [_]LocalDecl{
        .{ .count = 1, .val_type = .i32 },
    };

    const operators = [_]WasmOperator{
        .{ .i32_const = 42 },
        .{ .local_set = 0 },
        .{ .local_get = 0 },
        .end,
    };

    try ft.translateFunction(signature, &locals, &operators);

    // Should have iconst (for 42), instructions
    const instrs = ft.getInstructions();
    try testing.expect(instrs.len >= 1);
    try testing.expectEqual(ClifOpcode.iconst, instrs[0].opcode);
}

test "translate function with block" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var ft = FuncTranslator.init(allocator);
    defer ft.deinit();

    const signature = FuncSignature{
        .params = &[_]WasmValType{},
        .results = &[_]WasmValType{.i32},
    };

    const operators = [_]WasmOperator{
        .{ .block = .{ .params = 0, .results = 1 } },
        .{ .i32_const = 42 },
        .end, // end block
        .end, // end function
    };

    try ft.translateFunction(signature, &[_]LocalDecl{}, &operators);

    // Should complete without error
    try testing.expect(ft.getInstructions().len > 0);
}

test "translate function with loop and br" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var ft = FuncTranslator.init(allocator);
    defer ft.deinit();

    const signature = FuncSignature{
        .params = &[_]WasmValType{},
        .results = &[_]WasmValType{},
    };

    const operators = [_]WasmOperator{
        .{ .loop = .{ .params = 0, .results = 0 } },
        .{ .br = 0 }, // branch back to loop header
        .end, // end loop
        .end, // end function
    };

    try ft.translateFunction(signature, &[_]LocalDecl{}, &operators);

    // Check that a jump instruction was emitted
    var found_jump = false;
    for (ft.getInstructions()) |inst| {
        if (inst.opcode == .jump) {
            found_jump = true;
            break;
        }
    }
    try testing.expect(found_jump);
}

test "translate function with if-else" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var ft = FuncTranslator.init(allocator);
    defer ft.deinit();

    const signature = FuncSignature{
        .params = &[_]WasmValType{.i32},
        .results = &[_]WasmValType{.i32},
    };

    const operators = [_]WasmOperator{
        .{ .local_get = 0 },
        .{ .if_op = .{ .params = 0, .results = 1 } },
        .{ .i32_const = 1 }, // then branch
        .else_op,
        .{ .i32_const = 0 }, // else branch
        .end, // end if
        .end, // end function
    };

    try ft.translateFunction(signature, &[_]LocalDecl{}, &operators);

    // Should have brif instruction
    var found_brif = false;
    for (ft.getInstructions()) |inst| {
        if (inst.opcode == .brif) {
            found_brif = true;
            break;
        }
    }
    try testing.expect(found_brif);
}
