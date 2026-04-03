//! astgen.zig — Zig AST → CIR MLIR ops
//!
//! Uses std.zig.Ast parser (battle-tested) to parse Zig source,
//! then walks AST nodes and emits CIR ops via MLIR C API.
//!
//! Architecture: Zig AstGen single-pass recursive dispatch
//!   ~/claude/references/zig/lib/std/zig/AstGen.zig (13,664 lines)
//!
//! Supports the same features as libac (Phase 1):
//!   functions, arithmetic, comparisons, return, test blocks, assert

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
        // For now, resolve type identifiers to MLIR types
        const tag = self.tree.nodeTag(node);
        if (tag == .identifier) {
            const tok = self.tree.nodeMainToken(node);
            const name = self.tree.tokenSlice(tok);
            if (std.mem.eql(u8, name, "i32")) return self.b.intType(32);
            if (std.mem.eql(u8, name, "i64")) return self.b.intType(64);
            if (std.mem.eql(u8, name, "bool")) return self.b.intType(1);
            if (std.mem.eql(u8, name, "void")) return self.b.intType(0);
        }
        return self.i32Type(); // default
    }

    fn resolve(self: *Gen, name: []const u8) ?mlir.Value {
        for (0..self.param_count) |i| {
            if (std.mem.eql(u8, self.param_names[i], name)) return self.param_values[i];
        }
        return null;
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

        // Count params and build types
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

        // Return type
        var result_types: [1]mlir.Type = undefined;
        var n_results: usize = 0;
        if (proto.ast.return_type.unwrap()) |ret_node| {
            const ret_type = self.resolveType(ret_node);
            result_types[0] = ret_type;
            n_results = 1;
        }

        // Create function
        const func = self.b.createFunc(
            self.module,
            fn_name,
            param_types[0..param_count],
            result_types[0..n_results],
        );

        // Bind param names
        self.param_count = 0;
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

        // Map body
        self.mapBody(func.entry_block, body_node, result_types[0..n_results]);
    }

    fn mapTestDecl(self: *Gen, node: Node.Index) void {
        const tree = self.tree;
        // test_decl: data is opt_token_and_node (name token + body)
        const data = tree.nodeData(node);
        const body_node = data.opt_token_and_node[1];

        // Test blocks become void functions named __test_N
        var name_buf: [32]u8 = undefined;
        const name = std.fmt.bufPrint(&name_buf, "__test_{d}", .{node}) catch "test";

        const func = self.b.createFunc(self.module, name, &.{}, &.{});
        self.param_count = 0;
        self.mapBody(func.entry_block, body_node, &.{});
    }

    // ============================================================
    // Body / statement mapping
    // ============================================================

    fn mapBody(self: *Gen, block: mlir.Block, node: Node.Index, result_types: []const mlir.Type) void {
        const tree = self.tree;
        const tag = tree.nodeTag(node);
        self.has_terminator = false;
        switch (tag) {
            .block_two, .block_two_semicolon => {
                const d = tree.nodeData(node).opt_node_and_opt_node;
                if (d[0].unwrap()) |s| self.mapStmt(block, s, result_types);
                if (d[1].unwrap()) |s| self.mapStmt(block, s, result_types);
            },
            .block, .block_semicolon => {
                const stmts = tree.extraDataSlice(tree.nodeData(node).extra_range, Node.Index);
                for (stmts) |stmt| self.mapStmt(block, stmt, result_types);
            },
            else => self.mapStmt(block, node, result_types),
        }
        // Implicit void return only if no explicit return was emitted
        if (!self.has_terminator) {
            _ = self.b.emit(block, "func.return", &.{}, &.{}, &.{});
        }
    }

    fn mapStmt(self: *Gen, block: mlir.Block, node: Node.Index, result_types: []const mlir.Type) void {
        const tag = self.tree.nodeTag(node);
        switch (tag) {
            .@"return" => {
                const ret_opt = self.tree.nodeData(node).opt_node;
                if (ret_opt.unwrap()) |ret_expr| {
                    if (result_types.len > 0) {
                        const val = self.mapExpr(block, ret_expr, result_types[0]);
                        _ = self.b.emit(block, "func.return", &.{}, &.{val}, &.{});
                    } else {
                        _ = self.b.emit(block, "func.return", &.{}, &.{}, &.{});
                    }
                } else {
                    _ = self.b.emit(block, "func.return", &.{}, &.{}, &.{});
                }
                self.has_terminator = true;
            },
            // Builtin call: assert is @import("std").testing.expect in Zig,
            // but for simple test support we handle call_one where callee is "assert"
            else => {
                // Expression statement — evaluate for side effects
                _ = self.mapExpr(block, node, self.i32Type());
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
            .add => self.mapBinOp(block, node, "cir.add", result_type),
            .sub => self.mapBinOp(block, node, "cir.sub", result_type),
            .mul => self.mapBinOp(block, node, "cir.mul", result_type),
            .div => self.mapBinOp(block, node, "cir.div", result_type),
            .mod => self.mapBinOp(block, node, "cir.rem", result_type),
            .negation => self.mapUnaryOp(block, node, "cir.neg", result_type),
            .bit_not => self.mapUnaryOp(block, node, "cir.bit_not", result_type),
            .bit_and => self.mapBinOp(block, node, "cir.bit_and", result_type),
            .bit_or => self.mapBinOp(block, node, "cir.bit_or", result_type),
            .bit_xor => self.mapBinOp(block, node, "cir.xor", result_type),
            .shl => self.mapBinOp(block, node, "cir.shl", result_type),
            .shr => self.mapBinOp(block, node, "cir.shr", result_type),
            .equal_equal => self.mapCmp(block, node, 0),
            .bang_equal => self.mapCmp(block, node, 1),
            .less_than => self.mapCmp(block, node, 2),
            .less_or_equal => self.mapCmp(block, node, 3),
            .greater_than => self.mapCmp(block, node, 4),
            .greater_or_equal => self.mapCmp(block, node, 5),
            .call_one, .call_one_comma => self.mapCall(block, node, result_type),
            .call, .call_comma => self.mapCall(block, node, result_type),
            .grouped_expression => blk: {
                const inner = tree.nodeData(node).node_and_token[0];
                break :blk self.mapExpr(block, inner, result_type);
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
        // Boolean literals appear as identifiers in Zig AST
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

        // Use Zig's fullCall helper — handles both call_one and call variants
        // Reference: ~/claude/references/zig/lib/std/zig/Ast.zig callOne/callFull
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
