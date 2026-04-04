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
    // Struct types registered by name
    struct_names: [16][]const u8 = undefined,
    struct_types: [16]mlir.Type = undefined,
    struct_count: usize = 0,
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
            if (std.mem.eql(u8, name, "i8") or std.mem.eql(u8, name, "u8")) return self.b.intType(8);
            if (std.mem.eql(u8, name, "i16") or std.mem.eql(u8, name, "u16")) return self.b.intType(16);
            if (std.mem.eql(u8, name, "i32") or std.mem.eql(u8, name, "u32")) return self.b.intType(32);
            if (std.mem.eql(u8, name, "i64") or std.mem.eql(u8, name, "u64")) return self.b.intType(64);
            if (std.mem.eql(u8, name, "bool")) return self.b.intType(1);
            if (std.mem.eql(u8, name, "f32")) return mlir.mlirF32TypeGet(self.ctx);
            if (std.mem.eql(u8, name, "f64")) return mlir.mlirF64TypeGet(self.ctx);
            if (std.mem.eql(u8, name, "void")) return self.b.intType(0);
            // Check struct types
            for (0..self.struct_count) |i| {
                if (std.mem.eql(u8, self.struct_names[i], name))
                    return self.struct_types[i];
            }
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
            .simple_var_decl => self.mapTopLevelVarDecl(node),
            else => {},
        }
    }

    /// Handle top-level const declarations. If the init is a struct container
    /// declaration, register it as a struct type. Otherwise ignore.
    /// Reference: Zig AstGen containerDecl — dispatches on main_token tag.
    fn mapTopLevelVarDecl(self: *Gen, node: Node.Index) void {
        const tree = self.tree;
        const d = tree.nodeData(node).opt_node_and_opt_node;
        const init_node = d[1].unwrap() orelse return;
        const init_tag = tree.nodeTag(init_node);
        // Check if init is a struct container declaration
        if (init_tag == .container_decl_two or
            init_tag == .container_decl_two_trailing or
            init_tag == .container_decl or
            init_tag == .container_decl_trailing)
        {
            // Get name: main_token is `const`/`var`, +1 is the identifier
            const name_tok = tree.nodeMainToken(node) + 1;
            const name = tree.tokenSlice(name_tok);
            self.mapStructDecl(name, init_node);
        }
    }

    /// Parse a Zig struct container declaration and register the !cir.struct type.
    /// Builds a type string and parses it via mlirTypeParseGet.
    fn mapStructDecl(self: *Gen, name: []const u8, node: Node.Index) void {
        const tree = self.tree;
        const tag = tree.nodeTag(node);

        // Get member nodes (handle 0-2 and N-member variants)
        var members_buf: [2]Node.Index = undefined;
        const members: []const Node.Index = switch (tag) {
            .container_decl_two, .container_decl_two_trailing => blk: {
                const d = tree.nodeData(node).opt_node_and_opt_node;
                var count: usize = 0;
                if (d[0].unwrap()) |n| {
                    members_buf[count] = n;
                    count += 1;
                }
                if (d[1].unwrap()) |n| {
                    members_buf[count] = n;
                    count += 1;
                }
                break :blk members_buf[0..count];
            },
            .container_decl, .container_decl_trailing => blk: {
                break :blk tree.extraDataSlice(
                    tree.nodeData(node).extra_range, Node.Index);
            },
            else => return,
        };

        // Build type string: !cir.struct<"Name", field1: type1, field2: type2>
        var buf: [512]u8 = undefined;
        var pos: usize = 0;
        pos += (std.fmt.bufPrint(buf[pos..], "!cir.struct<\"{s}\"", .{name}) catch return).len;

        for (members) |member| {
            const field_tag = tree.nodeTag(member);
            if (field_tag == .container_field_init or
                field_tag == .container_field or
                field_tag == .container_field_align)
            {
                const field_main_token = tree.nodeMainToken(member);
                const field_name = tree.tokenSlice(field_main_token);
                // Get type node (first data node for all field variants)
                const type_node = switch (field_tag) {
                    .container_field_init => tree.nodeData(member).node_and_opt_node[0],
                    .container_field_align => tree.nodeData(member).node_and_node[0],
                    .container_field => tree.nodeData(member).node_and_extra[0],
                    else => unreachable,
                };
                const type_name = self.resolveTypeName(type_node);
                pos += (std.fmt.bufPrint(buf[pos..], ", {s}: {s}", .{ field_name, type_name }) catch return).len;
            }
        }
        pos += (std.fmt.bufPrint(buf[pos..], ">", .{}) catch return).len;

        const type_str = buf[0..pos];
        const struct_type = self.b.parseType(type_str);
        if (struct_type.ptr == null) return; // parse failed
        self.struct_names[self.struct_count] = name;
        self.struct_types[self.struct_count] = struct_type;
        self.struct_count += 1;
    }

    /// Return MLIR type name string for a Zig type identifier node.
    fn resolveTypeName(self: *Gen, node: Node.Index) []const u8 {
        const tag = self.tree.nodeTag(node);
        if (tag == .identifier) {
            const tok = self.tree.nodeMainToken(node);
            const name = self.tree.tokenSlice(tok);
            if (std.mem.eql(u8, name, "i8") or std.mem.eql(u8, name, "u8")) return "i8";
            if (std.mem.eql(u8, name, "i16") or std.mem.eql(u8, name, "u16")) return "i16";
            if (std.mem.eql(u8, name, "i32") or std.mem.eql(u8, name, "u32")) return "i32";
            if (std.mem.eql(u8, name, "i64") or std.mem.eql(u8, name, "u64")) return "i64";
            if (std.mem.eql(u8, name, "f32")) return "f32";
            if (std.mem.eql(u8, name, "f64")) return "f64";
            if (std.mem.eql(u8, name, "bool")) return "i1";
        }
        return "i32";
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
            .while_simple => {
                const d = self.tree.nodeData(node).node_and_node;
                const cond_node = d[0];
                const body_node = d[1];
                const header_block = self.addBlock();
                const body_block = self.addBlock();
                const exit_block = self.addBlock();
                // br to header
                self.b.emitBranch(blk, "cir.br", &.{}, &.{header_block});
                // header: eval condition, condbr
                self.current_block = header_block;
                const cond = self.mapExpr(header_block, cond_node, self.b.intType(1));
                self.b.emitBranch(header_block, "cir.condbr", &.{cond}, &.{ body_block, exit_block });
                // body: statements + back-edge
                self.mapBlock(body_block, body_node, result_types);
                if (!self.has_terminator) {
                    self.b.emitBranch(self.current_block, "cir.br", &.{}, &.{header_block});
                }
                self.current_block = exit_block;
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
            .if_simple => blk2: {
                // if (cond) then_val — no else, select with 0 default
                const d = tree.nodeData(node).node_and_node;
                const cond = self.mapExpr(block, d[0], self.b.intType(1));
                const then_val = self.mapExpr(block, d[1], result_type);
                const zero = self.b.emit(block, "cir.constant", &.{result_type}, &.{}, &.{
                    self.b.attr("value", self.b.intAttr(result_type, 0)),
                });
                break :blk2 self.b.emit(block, "cir.select", &.{result_type}, &.{ cond, then_val, zero }, &.{});
            },
            .@"if" => blk2: {
                // if (cond) then_val else else_val — full if expression
                const cond_node, const extra_index = tree.nodeData(node).node_and_extra;
                const extra = tree.extraData(extra_index, Node.If);
                const cond = self.mapExpr(block, cond_node, self.b.intType(1));
                const then_val = self.mapExpr(block, extra.then_expr, result_type);
                const else_val = self.mapExpr(block, extra.else_expr, result_type);
                break :blk2 self.b.emit(block, "cir.select", &.{result_type}, &.{ cond, then_val, else_val }, &.{});
            },
            .grouped_expression => blk2: {
                const inner = tree.nodeData(node).node_and_token[0];
                break :blk2 self.mapExpr(block, inner, result_type);
            },
            // Zig builtins: @intCast, @floatCast, @truncate, @floatFromInt
            // Reference: ~/claude/references/zig/lib/std/zig/AstGen.zig typeCast
            .builtin_call_two, .builtin_call_two_comma => blk2: {
                break :blk2 self.mapBuiltinCall(block, node, result_type);
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

    /// Handle Zig builtin calls: @intCast, @floatCast, @truncate, @floatFromInt.
    /// Destination type comes from result_type (threaded from variable declaration).
    /// Reference: Zig AstGen typeCast — result type from context.
    fn mapBuiltinCall(self: *Gen, block: mlir.Block, node: Node.Index, result_type: mlir.Type) mlir.Value {
        const tree = self.tree;
        const d = tree.nodeData(node).opt_node_and_opt_node;
        const main_tok = tree.nodeMainToken(node);
        const builtin_name = tree.tokenSlice(main_tok);
        // Get the single argument node
        const arg_node = d[0].unwrap() orelse return mlir.Value{ .ptr = null };
        // Determine the correct cast op based on builtin name.
        // The operand's natural type determines the cast direction.
        if (std.mem.eql(u8, builtin_name, "@intCast")) {
            // @intCast: integer → integer (ext or trunc based on widths)
            const src = self.mapExpr(block, arg_node, self.i32Type());
            return self.emitCast(block, src, result_type);
        }
        if (std.mem.eql(u8, builtin_name, "@truncate")) {
            // @truncate: integer truncation
            const src = self.mapExpr(block, arg_node, self.b.intType(64));
            return self.emitCast(block, src, result_type);
        }
        if (std.mem.eql(u8, builtin_name, "@floatCast")) {
            // @floatCast: float → float (ext or trunc)
            const src = self.mapExpr(block, arg_node, mlir.mlirF64TypeGet(self.ctx));
            return self.emitCast(block, src, result_type);
        }
        if (std.mem.eql(u8, builtin_name, "@floatFromInt")) {
            // @floatFromInt: integer → float
            const src = self.mapExpr(block, arg_node, self.i32Type());
            return self.emitCast(block, src, result_type);
        }
        if (std.mem.eql(u8, builtin_name, "@intFromFloat")) {
            // @intFromFloat: float → integer
            const src = self.mapExpr(block, arg_node, mlir.mlirF64TypeGet(self.ctx));
            return self.emitCast(block, src, result_type);
        }
        // Unknown builtin — fallback
        return self.mapExpr(block, arg_node, result_type);
    }

    /// Emit the correct CIR cast op based on source and destination types.
    /// Reference: Arith dialect — one op per direction.
    fn emitCast(self: *Gen, block: mlir.Block, src: mlir.Value, dst_type: mlir.Type) mlir.Value {
        const src_type = mlir.mlirValueGetType(src);
        // Same type → no-op
        if (mlir.mlirTypeEqual(src_type, dst_type)) return src;

        const src_int = mlir.mlirTypeIsAInteger(src_type);
        const dst_int = mlir.mlirTypeIsAInteger(dst_type);
        const src_float = mlir.mlirTypeIsAFloat(src_type);
        const dst_float = mlir.mlirTypeIsAFloat(dst_type);

        if (src_int and dst_int) {
            const src_w = mlir.mlirIntegerTypeGetWidth(src_type);
            const dst_w = mlir.mlirIntegerTypeGetWidth(dst_type);
            if (dst_w > src_w) {
                return self.b.emit(block, "cir.extsi", &.{dst_type}, &.{src}, &.{});
            }
            if (dst_w < src_w) {
                return self.b.emit(block, "cir.trunci", &.{dst_type}, &.{src}, &.{});
            }
            return src;
        }
        if (src_int and dst_float)
            return self.b.emit(block, "cir.sitofp", &.{dst_type}, &.{src}, &.{});
        if (src_float and dst_int)
            return self.b.emit(block, "cir.fptosi", &.{dst_type}, &.{src}, &.{});
        if (src_float and dst_float) {
            const src_w = mlir.mlirFloatTypeGetWidth(src_type);
            const dst_w = mlir.mlirFloatTypeGetWidth(dst_type);
            if (dst_w > src_w)
                return self.b.emit(block, "cir.extf", &.{dst_type}, &.{src}, &.{});
            if (dst_w < src_w)
                return self.b.emit(block, "cir.truncf", &.{dst_type}, &.{src}, &.{});
            return src;
        }
        return src; // unsupported — fallback
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
