//! astgen.zig — Zig AST → CIR MLIR ops
//!
//! Uses std.zig.Ast parser (battle-tested) to parse Zig source,
//! then walks AST nodes and emits CIR ops via MLIR C API.
//!
//! Architecture: Zig AstGen single-pass recursive dispatch
//!   ~/claude/references/zig/lib/std/zig/AstGen.zig (13,664 lines)
//!
//! Supports: functions, arithmetic, comparisons, booleans, negation,
//!   bitwise, shifts, let/var bindings, assignment, compound assignment,
//!   if/else, return, test blocks, assert

const std = @import("std");
const Ast = std.zig.Ast;
const Node = Ast.Node;
const mlir = @import("mlir.zig");

const Allocator = std.mem.Allocator;

pub const Result = struct {
    ctx: mlir.Context,
    module: mlir.Module,

    pub fn toBytecode(self: Result, gpa: Allocator) ![]u8 {
        return mlir.serializeToBytecode(gpa, self.module);
    }

    pub fn destroy(self: Result) void {
        mlir.mlirModuleDestroy(self.module);
        mlir.mlirContextDestroy(self.ctx);
    }
};

/// Generate CIR from Zig AST.
pub fn generate(gpa: Allocator, tree: *const Ast) !Result {
    var gen = Gen.init(gpa, tree);
    for (tree.rootDecls()) |node| {
        gen.mapDecl(node);
    }
    const result = Result{ .ctx = gen.ctx, .module = gen.module };
    return result;
}

const Gen = struct {
    gpa: Allocator,
    tree: *const Ast,
    ctx: mlir.Context,
    module: mlir.Module,
    b: mlir.Builder,
    // Current scope: function params by name
    param_names: [16][]const u8 = undefined,
    param_values: [16]mlir.Value = undefined,
    param_count: usize = 0,
    // Local variables: addresses from cir.alloca
    local_names: [32][]const u8 = undefined,
    local_addrs: [32]mlir.Value = undefined,
    local_types: [32]mlir.Type = undefined,
    local_count: usize = 0,
    // Current function's region (for adding blocks)
    current_func: mlir.Operation = .{ .ptr = null },
    // Current insertion block (changes after control flow)
    current_block: mlir.Block = .{ .ptr = null },
    has_terminator: bool = false,

    fn init(gpa: Allocator, tree: *const Ast) Gen {
        const ctx = mlir.createContext();
        return .{
            .gpa = gpa,
            .tree = tree,
            .ctx = ctx,
            .module = mlir.createModule(ctx),
            .b = mlir.Builder.init(ctx),
        };
    }

    fn i32Type(self: *Gen) mlir.Type {
        return self.b.intType(32);
    }

    fn resolveType(self: *Gen, node: Node.Index) mlir.Type {
        const tag = self.tree.nodeTag(node);
        if (tag == .identifier) {
            const tok = self.tree.nodeMainToken(node);
            const name = self.tree.tokenSlice(tok);
            if (std.mem.eql(u8, name, "i32")) return self.b.intType(32);
            if (std.mem.eql(u8, name, "i64")) return self.b.intType(64);
            if (std.mem.eql(u8, name, "bool")) return self.b.intType(1);
            if (std.mem.eql(u8, name, "void")) return self.b.intType(0);
        }
        return self.i32Type();
    }

    fn resolve(self: *Gen, name: []const u8) ?mlir.Value {
        for (0..self.param_count) |i| {
            if (std.mem.eql(u8, self.param_names[i], name)) return self.param_values[i];
        }
        return null;
    }

    fn resolveLocal(self: *Gen, name: []const u8) ?struct { addr: mlir.Value, elem_type: mlir.Type } {
        for (0..self.local_count) |i| {
            if (std.mem.eql(u8, self.local_names[i], name)) {
                return .{ .addr = self.local_addrs[i], .elem_type = self.local_types[i] };
            }
        }
        return null;
    }

    fn ptrType(self: *Gen) mlir.Type {
        return self.b.parseType("!cir.ptr");
    }

    /// Create a new block and add it to the current function's region.
    fn addBlock(self: *Gen) mlir.Block {
        const block = self.b.createBlock(&.{});
        const region = mlir.mlirOperationGetRegion(self.current_func, 0);
        mlir.mlirRegionAppendOwnedBlock(region, block);
        return block;
    }

    // ============================================================
    // Declaration dispatch — Zig AstGen pattern
    // ============================================================

    fn mapDecl(self: *Gen, node: Node.Index) void {
        const tag = self.tree.nodeTag(node);
        switch (tag) {
            .fn_decl => self.mapFnDecl(node),
            .test_decl => self.mapTestDecl(node),
            else => {},
        }
    }

    fn mapFnDecl(self: *Gen, node: Node.Index) void {
        const tree = self.tree;
        const data = tree.nodeData(node).node_and_node;
        const proto_node = data[0];
        const body_node = data[1];

        var proto_buf: [1]Node.Index = undefined;
        const proto = tree.fullFnProto(&proto_buf, proto_node) orelse return;

        const fn_name = if (proto.name_token) |tok| tree.tokenSlice(tok) else "anon";

        var param_count: usize = 0;
        var param_types: [16]mlir.Type = undefined;
        {
            var it = proto.iterate(tree);
            while (it.next()) |param| {
                if (param.type_expr) |type_node| {
                    param_types[param_count] = self.resolveType(type_node);
                } else {
                    param_types[param_count] = self.i32Type();
                }
                param_count += 1;
            }
        }

        var result_types: [1]mlir.Type = undefined;
        var n_results: usize = 0;
        if (proto.ast.return_type.unwrap()) |ret_node| {
            const ret_type = self.resolveType(ret_node);
            result_types[0] = ret_type;
            n_results = 1;
        }

        const func = self.b.createFunc(
            self.module,
            fn_name,
            param_types[0..param_count],
            result_types[0..n_results],
        );
        self.current_func = func.func_op;

        self.param_count = 0;
        self.local_count = 0;
        {
            var it = proto.iterate(tree);
            var i: usize = 0;
            while (it.next()) |param| : (i += 1) {
                if (param.name_token) |name_tok| {
                    self.param_names[self.param_count] = tree.tokenSlice(name_tok);
                    self.param_values[self.param_count] = mlir.mlirBlockGetArgument(func.entry_block, @intCast(i));
                    self.param_count += 1;
                }
            }
        }

        self.mapBody(func.entry_block, body_node, result_types[0..n_results]);
    }

    fn mapTestDecl(self: *Gen, node: Node.Index) void {
        const tree = self.tree;
        const data = tree.nodeData(node);
        const body_node = data.opt_token_and_node[1];

        var name_buf: [32]u8 = undefined;
        const name = std.fmt.bufPrint(&name_buf, "__test_{d}", .{node}) catch "test";

        const func = self.b.createFunc(self.module, name, &.{}, &.{});
        self.current_func = func.func_op;
        self.param_count = 0;
        self.local_count = 0;
        self.mapBody(func.entry_block, body_node, &.{});
    }

    // ============================================================
    // Body / statement mapping
    // ============================================================

    /// Emit statements from a block node. Does NOT add implicit return.
    fn mapBlock(self: *Gen, block: mlir.Block, node: Node.Index, result_types: []const mlir.Type) void {
        const tree = self.tree;
        const tag = tree.nodeTag(node);
        self.has_terminator = false;
        self.current_block = block;
        switch (tag) {
            .block_two, .block_two_semicolon => {
                const d = tree.nodeData(node).opt_node_and_opt_node;
                if (d[0].unwrap()) |s| self.mapStmt(s, result_types);
                if (d[1].unwrap()) |s| self.mapStmt(s, result_types);
            },
            .block, .block_semicolon => {
                const stmts = tree.extraDataSlice(tree.nodeData(node).extra_range, Node.Index);
                for (stmts) |stmt| self.mapStmt(stmt, result_types);
            },
            else => self.mapStmt(node, result_types),
        }
    }

    /// Emit function body — statements + implicit void return.
    fn mapBody(self: *Gen, block: mlir.Block, node: Node.Index, result_types: []const mlir.Type) void {
        self.mapBlock(block, node, result_types);
        if (!self.has_terminator) {
            _ = self.b.emit(self.current_block, "func.return", &.{}, &.{}, &.{});
        }
    }

    fn mapStmt(self: *Gen, node: Node.Index, result_types: []const mlir.Type) void {
        const tag = self.tree.nodeTag(node);
        const blk = self.current_block;
        switch (tag) {
            .@"return" => {
                const ret_opt = self.tree.nodeData(node).opt_node;
                if (ret_opt.unwrap()) |ret_expr| {
                    if (result_types.len > 0) {
                        const val = self.mapExpr(blk, ret_expr, result_types[0]);
                        _ = self.b.emit(blk, "func.return", &.{}, &.{val}, &.{});
                    } else {
                        _ = self.b.emit(blk, "func.return", &.{}, &.{}, &.{});
                    }
                } else {
                    _ = self.b.emit(blk, "func.return", &.{}, &.{}, &.{});
                }
                self.has_terminator = true;
            },
            .if_simple => {
                const d = self.tree.nodeData(node).node_and_node;
                const cond_node = d[0];
                const then_node = d[1];
                const cond = self.mapExpr(blk, cond_node, self.b.intType(1));
                const then_block = self.addBlock();
                const merge_block = self.addBlock();
                self.b.emitBranch(blk, "cir.condbr", &.{cond}, &.{ then_block, merge_block });
                self.mapBlock(then_block, then_node, result_types);
                if (!self.has_terminator) {
                    self.b.emitBranch(self.current_block, "cir.br", &.{}, &.{merge_block});
                }
                self.current_block = merge_block;
                self.has_terminator = false;
            },
            .simple_var_decl => {
                const d = self.tree.nodeData(node).opt_node_and_opt_node;
                const type_node = d[0];
                const init_node = d[1];
                var var_type = self.i32Type();
                if (type_node.unwrap()) |tn| {
                    var_type = self.resolveType(tn);
                }
                const ptr_ty = self.ptrType();
                const addr = self.b.emit(blk, "cir.alloca", &.{ptr_ty}, &.{}, &.{
                    self.b.attr("elem_type", self.b.typeAttr(var_type)),
                });
                if (init_node.unwrap()) |init_expr| {
                    const val = self.mapExpr(blk, init_expr, var_type);
                    _ = self.b.emit(blk, "cir.store", &.{}, &.{ val, addr }, &.{});
                }
                const tok = self.tree.nodeMainToken(node);
                const name = self.tree.tokenSlice(tok + 1);
                self.local_names[self.local_count] = name;
                self.local_addrs[self.local_count] = addr;
                self.local_types[self.local_count] = var_type;
                self.local_count += 1;
            },
            .assign => {
                const d = self.tree.nodeData(node).node_and_node;
                const lhs_node = d[0];
                const rhs_node = d[1];
                const name = self.tree.tokenSlice(self.tree.nodeMainToken(lhs_node));
                if (self.resolveLocal(name)) |local| {
                    const val = self.mapExpr(blk, rhs_node, local.elem_type);
                    _ = self.b.emit(blk, "cir.store", &.{}, &.{ val, local.addr }, &.{});
                }
            },
            .assign_add, .assign_sub, .assign_mul, .assign_div, .assign_mod => {
                const d = self.tree.nodeData(node).node_and_node;
                const lhs_node = d[0];
                const rhs_node = d[1];
                const name = self.tree.tokenSlice(self.tree.nodeMainToken(lhs_node));
                if (self.resolveLocal(name)) |local| {
                    const current = self.b.emit(blk, "cir.load", &.{local.elem_type}, &.{local.addr}, &.{});
                    const rhs = self.mapExpr(blk, rhs_node, local.elem_type);
                    const op_name: []const u8 = switch (tag) {
                        .assign_add => "cir.add",
                        .assign_sub => "cir.sub",
                        .assign_mul => "cir.mul",
                        .assign_div => "cir.div",
                        .assign_mod => "cir.rem",
                        else => unreachable,
                    };
                    const result = self.b.emit(blk, op_name, &.{local.elem_type}, &.{ current, rhs }, &.{});
                    _ = self.b.emit(blk, "cir.store", &.{}, &.{ result, local.addr }, &.{});
                }
            },
            else => {
                _ = self.mapExpr(blk, node, self.i32Type());
            },
        }
    }

    // ============================================================
    // Expression mapping — Zig AstGen expr() pattern
    // ============================================================

    fn mapExpr(self: *Gen, block: mlir.Block, node: Node.Index, result_type: mlir.Type) mlir.Value {
        const tree = self.tree;
        const tag = tree.nodeTag(node);
        return switch (tag) {
            .number_literal => self.mapNumberLit(block, node, result_type),
            .identifier => self.mapIdentifier(block, node),
            .negation => self.mapUnaryOp(block, node, "cir.neg", result_type),
            .bit_not => self.mapUnaryOp(block, node, "cir.bit_not", result_type),
            .bit_and => self.mapBinOp(block, node, "cir.bit_and", result_type),
            .bit_or => self.mapBinOp(block, node, "cir.bit_or", result_type),
            .bit_xor => self.mapBinOp(block, node, "cir.xor", result_type),
            .shl => self.mapBinOp(block, node, "cir.shl", result_type),
            .shr => self.mapBinOp(block, node, "cir.shr", result_type),
            .add => self.mapBinOp(block, node, "cir.add", result_type),
            .sub => self.mapBinOp(block, node, "cir.sub", result_type),
            .mul => self.mapBinOp(block, node, "cir.mul", result_type),
            .div => self.mapBinOp(block, node, "cir.div", result_type),
            .mod => self.mapBinOp(block, node, "cir.rem", result_type),
            .equal_equal => self.mapCmp(block, node, 0),
            .bang_equal => self.mapCmp(block, node, 1),
            .less_than => self.mapCmp(block, node, 2),
            .less_or_equal => self.mapCmp(block, node, 3),
            .greater_than => self.mapCmp(block, node, 4),
            .greater_or_equal => self.mapCmp(block, node, 5),
            .call_one, .call_one_comma => self.mapCall(block, node, result_type),
            .call, .call_comma => self.mapCall(block, node, result_type),
            .grouped_expression => blk2: {
                const inner = tree.nodeData(node).node_and_token[0];
                break :blk2 self.mapExpr(block, inner, result_type);
            },
            else => self.b.emit(block, "cir.constant", &.{result_type}, &.{}, &.{
                self.b.attr("value", self.b.intAttr(result_type, 0)),
            }),
        };
    }

    fn mapNumberLit(self: *Gen, block: mlir.Block, node: Node.Index, result_type: mlir.Type) mlir.Value {
        const tok = self.tree.nodeMainToken(node);
        const text = self.tree.tokenSlice(tok);
        const val = std.fmt.parseInt(i64, text, 10) catch 0;
        return self.b.emit(block, "cir.constant", &.{result_type}, &.{}, &.{
            self.b.attr("value", self.b.intAttr(result_type, val)),
        });
    }

    fn mapIdentifier(self: *Gen, block: mlir.Block, node: Node.Index) mlir.Value {
        const tok = self.tree.nodeMainToken(node);
        const name = self.tree.tokenSlice(tok);
        if (std.mem.eql(u8, name, "true")) {
            const bool_type = self.b.intType(1);
            return self.b.emit(block, "cir.constant", &.{bool_type}, &.{}, &.{
                self.b.attr("value", self.b.intAttr(bool_type, 1)),
            });
        }
        if (std.mem.eql(u8, name, "false")) {
            const bool_type = self.b.intType(1);
            return self.b.emit(block, "cir.constant", &.{bool_type}, &.{}, &.{
                self.b.attr("value", self.b.intAttr(bool_type, 0)),
            });
        }
        if (self.resolveLocal(name)) |local| {
            return self.b.emit(block, "cir.load", &.{local.elem_type}, &.{local.addr}, &.{});
        }
        return self.resolve(name) orelse mlir.Value{ .ptr = null };
    }

    fn mapUnaryOp(self: *Gen, block: mlir.Block, node: Node.Index, op_name: []const u8, result_type: mlir.Type) mlir.Value {
        const operand_node = self.tree.nodeData(node).node;
        const operand = self.mapExpr(block, operand_node, result_type);
        return self.b.emit(block, op_name, &.{result_type}, &.{operand}, &.{});
    }

    fn mapBinOp(self: *Gen, block: mlir.Block, node: Node.Index, op_name: []const u8, result_type: mlir.Type) mlir.Value {
        const d = self.tree.nodeData(node).node_and_node;
        const lhs = self.mapExpr(block, d[0], result_type);
        const rhs = self.mapExpr(block, d[1], result_type);
        return self.b.emit(block, op_name, &.{result_type}, &.{ lhs, rhs }, &.{});
    }

    fn mapCmp(self: *Gen, block: mlir.Block, node: Node.Index, predicate: i64) mlir.Value {
        const d = self.tree.nodeData(node).node_and_node;
        const operand_type = self.i32Type();
        const lhs = self.mapExpr(block, d[0], operand_type);
        const rhs = self.mapExpr(block, d[1], operand_type);
        const bool_type = self.b.intType(1);
        return self.b.emit(block, "cir.cmp", &.{bool_type}, &.{ lhs, rhs }, &.{
            self.b.attr("predicate", self.b.intAttr(self.b.intType(64), predicate)),
        });
    }

    fn mapCall(self: *Gen, block: mlir.Block, node: Node.Index, result_type: mlir.Type) mlir.Value {
        const tree = self.tree;
        var call_buf: [1]Node.Index = undefined;
        const call = tree.fullCall(&call_buf, node) orelse return mlir.Value{ .ptr = null };
        const callee_name = tree.tokenSlice(tree.nodeMainToken(call.ast.fn_expr));
        var args: [16]mlir.Value = undefined;
        for (call.ast.params, 0..) |param_node, i| {
            args[i] = self.mapExpr(block, param_node, result_type);
        }
        return self.b.emit(block, "func.call", &.{result_type}, args[0..call.ast.params.len], &.{
            self.b.attr("callee", mlir.mlirFlatSymbolRefAttrGet(self.ctx, mlir.StringRef.fromSlice(callee_name))),
        });
    }
};
