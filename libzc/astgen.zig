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

/// Generate CIR from Zig AST with source location tracking.
pub fn generate(gpa: Allocator, tree: *const Ast, filename: []const u8) !Result {
    var gen = Gen.init(gpa, tree, filename);
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
    // Source filename for location tracking
    filename: []const u8,
    // Current scope: function params by name (growable)
    param_names: std.ArrayList([]const u8) = .empty,
    param_values: std.ArrayList(mlir.Value) = .empty,
    // Local variables: addresses from cir.alloca (growable)
    local_names: std.ArrayList([]const u8) = .empty,
    local_addrs: std.ArrayList(mlir.Value) = .empty,
    local_types: std.ArrayList(mlir.Type) = .empty,
    // Struct types registered by name (growable)
    structs: std.ArrayList(StructInfo) = .empty,
    // Enum types registered by name (growable)
    enums: std.ArrayList(EnumInfo) = .empty,
    // Tagged union types registered by name (growable)
    unions: std.ArrayList(UnionInfo) = .empty,
    // Current generic type parameters (for resolving T → !cir.type_param<"T">)
    // Reference: ac frontend currentTypeParams_ pattern (libac/codegen.cpp)
    current_type_params: []const []const u8 = &.{},
    // Generic function names — to detect generic calls at call sites
    generic_func_names: std.ArrayList([]const u8) = .empty,
    generic_func_type_params: std.ArrayList([]const []const u8) = .empty,
    // Current function's return type (for enum literal context inference)
    current_return_type: mlir.Type = .{ .ptr = null },
    // Current function's region (for adding blocks)
    current_func: mlir.Operation = .{ .ptr = null },
    // Current insertion block (changes after control flow)
    current_block: mlir.Block = .{ .ptr = null },
    has_terminator: bool = false,

    const StructInfo = struct {
        name: []const u8,
        mlir_type: mlir.Type,
        field_names: []const []const u8,
        field_types: []const mlir.Type,
    };

    const EnumInfo = struct {
        name: []const u8,
        mlir_type: mlir.Type,
        variant_names: []const []const u8,
    };

    const UnionInfo = struct {
        name: []const u8,
        mlir_type: mlir.Type,
        variant_names: []const []const u8,
        variant_types: []const mlir.Type,
    };

    /// Function pointer types for mapBinOp/mapUnaryOp dispatch.
    const BinOpFn = *const fn (mlir.Block, mlir.Location, mlir.Type, mlir.Value, mlir.Value) callconv(.c) mlir.Value;
    const UnaryOpFn = *const fn (mlir.Block, mlir.Location, mlir.Type, mlir.Value) callconv(.c) mlir.Value;

    fn init(gpa: Allocator, tree: *const Ast, filename: []const u8) Gen {
        const ctx = mlir.createContext();
        return .{
            .gpa = gpa,
            .tree = tree,
            .ctx = ctx,
            .module = mlir.createModule(ctx),
            .b = mlir.Builder.init(ctx),
            .filename = filename,
        };
    }

    /// Create an MLIR FileLineCol location from an AST node's main token.
    /// Uses std.zig.Ast.tokenLocation to compute line/col from source.
    fn locFromNode(self: *Gen, node: Node.Index) mlir.Location {
        const tok = self.tree.nodeMainToken(node);
        const loc = self.tree.tokenLocation(0, tok);
        // tokenLocation returns 0-based line/col; MLIR uses 1-based line, 0-based col
        return mlir.cirLocationFileLineCol(
            self.ctx,
            mlir.StringRef.fromSlice(self.filename),
            @intCast(loc.line + 1),
            @intCast(loc.column),
        );
    }

    /// Set the builder's current location from an AST node.
    fn setLoc(self: *Gen, node: Node.Index) void {
        self.b.loc = self.locFromNode(node);
    }

    fn i32Type(self: *Gen) mlir.Type {
        return self.b.intType(32);
    }

    fn resolveType(self: *Gen, node: Node.Index) mlir.Type {
        const tag = self.tree.nodeTag(node);
        if (tag == .identifier) {
            const tok = self.tree.nodeMainToken(node);
            const name = self.tree.tokenSlice(tok);
            // Check if this is a generic type parameter (T → !cir.type_param<"T">)
            // Reference: ac frontend currentTypeParams_ pattern (libac/codegen.cpp)
            for (self.current_type_params) |tp| {
                if (std.mem.eql(u8, tp, name))
                    return mlir.cirTypeParamGet(self.ctx, mlir.StringRef.fromSlice(name));
            }
            if (std.mem.eql(u8, name, "i8") or std.mem.eql(u8, name, "u8")) return self.b.intType(8);
            if (std.mem.eql(u8, name, "i16") or std.mem.eql(u8, name, "u16")) return self.b.intType(16);
            if (std.mem.eql(u8, name, "i32") or std.mem.eql(u8, name, "u32")) return self.b.intType(32);
            if (std.mem.eql(u8, name, "i64") or std.mem.eql(u8, name, "u64")) return self.b.intType(64);
            if (std.mem.eql(u8, name, "bool")) return self.b.intType(1);
            if (std.mem.eql(u8, name, "f32")) return mlir.mlirF32TypeGet(self.ctx);
            if (std.mem.eql(u8, name, "f64")) return mlir.mlirF64TypeGet(self.ctx);
            if (std.mem.eql(u8, name, "void")) return self.b.intType(0);
            // Check struct types
            for (self.structs.items) |s| {
                if (std.mem.eql(u8, s.name, name))
                    return s.mlir_type;
            }
            // Check enum types
            for (self.enums.items) |e| {
                if (std.mem.eql(u8, e.name, name))
                    return e.mlir_type;
            }
            // Check tagged union types
            for (self.unions.items) |u| {
                if (std.mem.eql(u8, u.name, name))
                    return u.mlir_type;
            }
        }
        // Pointer type: *T → !cir.ref<T>, []T → !cir.slice<T>
        if (tag == .ptr_type or tag == .ptr_type_aligned or
            tag == .ptr_type_sentinel or tag == .ptr_type_bit_range)
        {
            // Pointee type (child_type) location varies by variant:
            //   .ptr_type:         extra_and_node — child is [1]
            //   .ptr_type_bit_range: extra_and_node — child is [1]
            //   .ptr_type_aligned: opt_node_and_node — child is [1]
            //   .ptr_type_sentinel: node_and_node — child is [1]
            const d = self.tree.nodeData(node);
            const pointee_node: Node.Index = switch (tag) {
                .ptr_type, .ptr_type_bit_range => d.extra_and_node[1],
                .ptr_type_aligned => d.opt_node_and_node[1],
                .ptr_type_sentinel => d.node_and_node[1],
                else => unreachable,
            };
            const pointee_name = self.resolveTypeName(pointee_node);
            // Detect slice types: []T vs *T
            // The main token for [] is l_bracket, for * it's asterisk
            const main_tok = self.tree.nodeMainToken(node);
            const tok_tag = self.tree.tokens.items(.tag)[main_tok];
            if (tok_tag == .l_bracket) {
                // Slice type: []T → !cir.slice<T>
                var buf2: [64]u8 = undefined;
                const slice_str = std.fmt.bufPrint(&buf2, "!cir.slice<{s}>", .{pointee_name}) catch return self.i32Type();
                return self.b.parseType(slice_str);
            }
            var buf2: [64]u8 = undefined;
            const ref_str = std.fmt.bufPrint(&buf2, "!cir.ref<{s}>", .{pointee_name}) catch return self.i32Type();
            return self.b.parseType(ref_str);
        }
        // Array type: [N]T
        if (tag == .array_type) {
            const d = self.tree.nodeData(node);
            const len_node = d.node_and_node[0];
            const elem_node = d.node_and_node[1];
            // Get length from number literal
            const len_tok = self.tree.nodeMainToken(len_node);
            const len_text = self.tree.tokenSlice(len_tok);
            const len_val = std.fmt.parseInt(i64, len_text, 10) catch 0;
            const elem_name = self.resolveTypeName(elem_node);
            var buf: [64]u8 = undefined;
            const type_str = std.fmt.bufPrint(&buf, "!cir.array<{d} x {s}>", .{ len_val, elem_name }) catch return self.i32Type();
            return self.b.parseType(type_str);
        }
        // Optional type: ?T
        if (tag == .optional_type) {
            const child_node = self.tree.nodeData(node).node;
            const child_type = self.resolveType(child_node);
            return mlir.cirOptionalTypeGet(self.ctx, child_type);
        }
        // Error union type: E!T → !cir.error_union<T>
        // Reference: Zig AstGen — error_union node has node_and_node data
        // [0] = error set type (ignored for now — CIR uses generic i16 error code)
        // [1] = payload type
        if (tag == .error_union) {
            const d = self.tree.nodeData(node).node_and_node;
            const payload_node = d[1];
            const payload_type = self.resolveType(payload_node);
            return mlir.cirErrorUnionTypeGet(self.ctx, payload_type);
        }
        return self.i32Type();
    }

    fn resolve(self: *Gen, name: []const u8) ?mlir.Value {
        for (self.param_names.items, 0..) |pname, i| {
            if (std.mem.eql(u8, pname, name)) return self.param_values.items[i];
        }
        return null;
    }

    fn resolveLocal(self: *Gen, name: []const u8) ?struct { addr: mlir.Value, elem_type: mlir.Type } {
        for (self.local_names.items, 0..) |lname, i| {
            if (std.mem.eql(u8, lname, name)) {
                return .{ .addr = self.local_addrs.items[i], .elem_type = self.local_types.items[i] };
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
        self.setLoc(node);
        const tag = self.tree.nodeTag(node);
        switch (tag) {
            .fn_decl => self.mapFnDecl(node),
            .test_decl => self.mapTestDecl(node),
            .simple_var_decl => self.mapTopLevelVarDecl(node),
            else => {},
        }
    }

    /// Handle top-level const declarations. If the init is a container
    /// declaration, register it as a struct or enum type. Otherwise ignore.
    /// Reference: Zig AstGen containerDecl — dispatches on main_token tag.
    fn mapTopLevelVarDecl(self: *Gen, node: Node.Index) void {
        const tree = self.tree;
        const d = tree.nodeData(node).opt_node_and_opt_node;
        const init_node = d[1].unwrap() orelse return;
        const init_tag = tree.nodeTag(init_node);
        // Get name: main_token is `const`/`var`, +1 is the identifier
        const name_tok = tree.nodeMainToken(node) + 1;
        const name = tree.tokenSlice(name_tok);

        // Check if init is a container declaration (struct or enum)
        if (init_tag == .container_decl_two or
            init_tag == .container_decl_two_trailing or
            init_tag == .container_decl or
            init_tag == .container_decl_trailing)
        {
            // Distinguish struct vs enum by main_token tag
            const main_tok = tree.nodeMainToken(init_node);
            const tok_tag = tree.tokens.items(.tag)[main_tok];
            if (tok_tag == .keyword_enum) {
                self.mapEnumDecl(name, init_node, .none);
            } else {
                self.mapStructDecl(name, init_node);
            }
        }
        // container_decl_arg: enum(u8) or struct(arg) with explicit tag/arg
        if (init_tag == .container_decl_arg or
            init_tag == .container_decl_arg_trailing)
        {
            const main_tok = tree.nodeMainToken(init_node);
            const tok_tag = tree.tokens.items(.tag)[main_tok];
            if (tok_tag == .keyword_enum) {
                self.mapEnumDecl(name, init_node, .none);
            }
        }

        // Tagged union: union(enum) { ... }
        // Zig AST uses specific node types for tagged unions.
        if (init_tag == .tagged_union or
            init_tag == .tagged_union_trailing or
            init_tag == .tagged_union_two or
            init_tag == .tagged_union_two_trailing or
            init_tag == .tagged_union_enum_tag or
            init_tag == .tagged_union_enum_tag_trailing)
        {
            self.mapUnionDecl(name, init_node);
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

        // Also store field names and types for struct init
        // Count fields first
        var field_count: usize = 0;
        for (members) |member| {
            const field_tag = tree.nodeTag(member);
            if (field_tag == .container_field_init or
                field_tag == .container_field or
                field_tag == .container_field_align)
            {
                field_count += 1;
            }
        }
        // Allocate slices for field names and types
        const f_names = self.gpa.alloc([]const u8, field_count) catch return;
        const f_types = self.gpa.alloc(mlir.Type, field_count) catch return;
        var fi: usize = 0;
        for (members) |member| {
            const field_tag = tree.nodeTag(member);
            if (field_tag == .container_field_init or
                field_tag == .container_field or
                field_tag == .container_field_align)
            {
                const field_main_token = tree.nodeMainToken(member);
                f_names[fi] = tree.tokenSlice(field_main_token);
                const type_node = switch (field_tag) {
                    .container_field_init => tree.nodeData(member).node_and_opt_node[0],
                    .container_field_align => tree.nodeData(member).node_and_node[0],
                    .container_field => tree.nodeData(member).node_and_extra[0],
                    else => unreachable,
                };
                f_types[fi] = self.resolveType(type_node);
                fi += 1;
            }
        }
        self.structs.append(self.gpa, .{
            .name = name,
            .mlir_type = struct_type,
            .field_names = f_names,
            .field_types = f_types,
        }) catch return;
    }

    /// Parse a Zig enum container declaration and register the !cir.enum type.
    /// Handles both `enum { a, b }` (container_decl/container_decl_two) and
    /// `enum(u8) { a, b }` (container_decl_arg).
    /// Reference: Zig AstGen containerDecl — main_token is keyword_enum.
    fn mapEnumDecl(self: *Gen, name: []const u8, node: Node.Index, _: Node.OptionalIndex) void {
        const tree = self.tree;
        const tag = tree.nodeTag(node);

        // Collect member nodes based on container variant
        var members_buf: [2]Node.Index = undefined;
        var tag_type_node: ?Node.Index = null;
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
            .container_decl_arg, .container_decl_arg_trailing => blk: {
                const d = tree.nodeData(node).node_and_extra;
                tag_type_node = d[0];
                const sub_range = tree.extraData(d[1], Node.SubRange);
                break :blk tree.extraDataSlice(sub_range, Node.Index);
            },
            else => return,
        };

        // Determine tag type: default to i32, or resolve from explicit arg
        var tag_type = self.b.intType(32);
        if (tag_type_node) |tn| {
            tag_type = self.resolveType(tn);
        }

        // Count enum variants (only container_field_init nodes without type annotations)
        var variant_count: usize = 0;
        for (members) |member| {
            const field_tag = tree.nodeTag(member);
            if (field_tag == .container_field_init or
                field_tag == .container_field or
                field_tag == .container_field_align)
            {
                variant_count += 1;
            }
        }

        // Build arrays for C API call
        const v_names = self.gpa.alloc(mlir.StringRef, variant_count) catch return;
        defer self.gpa.free(v_names);
        const v_values = self.gpa.alloc(i64, variant_count) catch return;
        defer self.gpa.free(v_values);
        const v_name_strs = self.gpa.alloc([]const u8, variant_count) catch return;

        var vi: usize = 0;
        for (members) |member| {
            const field_tag = tree.nodeTag(member);
            if (field_tag == .container_field_init or
                field_tag == .container_field or
                field_tag == .container_field_align)
            {
                const field_main_token = tree.nodeMainToken(member);
                const variant_name = tree.tokenSlice(field_main_token);
                v_names[vi] = mlir.StringRef.fromSlice(variant_name);
                v_values[vi] = @intCast(vi); // auto-assign sequential values
                v_name_strs[vi] = variant_name;
                vi += 1;
            }
        }

        // Create !cir.enum type via C API
        const enum_type = mlir.cirEnumTypeGet(
            self.ctx,
            mlir.StringRef.fromSlice(name),
            tag_type,
            @intCast(variant_count),
            v_names.ptr,
            v_values.ptr,
        );
        if (enum_type.ptr == null) return;

        // Register enum type
        self.enums.append(self.gpa, .{
            .name = name,
            .mlir_type = enum_type,
            .variant_names = v_name_strs,
        }) catch return;
    }

    /// Parse a Zig union(enum) container declaration and register the
    /// !cir.tagged_union type.
    /// Handles tagged_union, tagged_union_two, tagged_union_enum_tag variants.
    /// Reference: Zig AstGen containerDecl — specific node types for union(enum).
    fn mapUnionDecl(self: *Gen, name: []const u8, node: Node.Index) void {
        const tree = self.tree;
        const tag = tree.nodeTag(node);

        // Get member nodes based on AST node variant
        var members_buf: [2]Node.Index = undefined;
        const members: []const Node.Index = switch (tag) {
            .tagged_union_two, .tagged_union_two_trailing => blk: {
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
            .tagged_union, .tagged_union_trailing => blk: {
                break :blk tree.extraDataSlice(
                    tree.nodeData(node).extra_range, Node.Index);
            },
            .tagged_union_enum_tag, .tagged_union_enum_tag_trailing => blk: {
                const d = tree.nodeData(node).node_and_extra;
                const sub_range = tree.extraData(d[1], Node.SubRange);
                break :blk tree.extraDataSlice(sub_range, Node.Index);
            },
            else => return,
        };

        // Count variants
        var variant_count: usize = 0;
        for (members) |member| {
            const field_tag = tree.nodeTag(member);
            if (field_tag == .container_field_init or
                field_tag == .container_field or
                field_tag == .container_field_align)
            {
                variant_count += 1;
            }
        }

        // Build arrays for C API call
        const v_names = self.gpa.alloc(mlir.StringRef, variant_count) catch return;
        defer self.gpa.free(v_names);
        const v_types = self.gpa.alloc(mlir.Type, variant_count) catch return;
        defer self.gpa.free(v_types);
        const v_name_strs = self.gpa.alloc([]const u8, variant_count) catch return;
        const v_type_mlirs = self.gpa.alloc(mlir.Type, variant_count) catch return;

        var vi: usize = 0;
        for (members) |member| {
            const field_tag = tree.nodeTag(member);
            if (field_tag == .container_field_init or
                field_tag == .container_field or
                field_tag == .container_field_align)
            {
                const field_main_token = tree.nodeMainToken(member);
                const variant_name = tree.tokenSlice(field_main_token);
                v_names[vi] = mlir.StringRef.fromSlice(variant_name);
                v_name_strs[vi] = variant_name;

                // Get variant type node
                const type_node: Node.Index = switch (field_tag) {
                    .container_field_init => tree.nodeData(member).node_and_opt_node[0],
                    .container_field_align => tree.nodeData(member).node_and_node[0],
                    .container_field => tree.nodeData(member).node_and_extra[0],
                    else => unreachable,
                };

                // Check if the type node's identifier matches the field name.
                // For bare enum-like variants (e.g. `none,` with no `: type`),
                // the Zig parser sets the type node to point at the same
                // identifier. Detect this and treat as void (i0).
                const type_tag = tree.nodeTag(type_node);
                if (type_tag == .identifier) {
                    const type_name_text = tree.tokenSlice(tree.nodeMainToken(type_node));
                    if (std.mem.eql(u8, type_name_text, variant_name)) {
                        // Void variant: name == type (bare name, no colon)
                        v_types[vi] = self.b.intType(0);
                        v_type_mlirs[vi] = self.b.intType(0);
                    } else {
                        const resolved = self.resolveType(type_node);
                        v_types[vi] = resolved;
                        v_type_mlirs[vi] = resolved;
                    }
                } else {
                    const resolved = self.resolveType(type_node);
                    v_types[vi] = resolved;
                    v_type_mlirs[vi] = resolved;
                }

                vi += 1;
            }
        }

        // Create !cir.tagged_union type via C API
        const union_type = mlir.cirTaggedUnionTypeGet(
            self.ctx,
            mlir.StringRef.fromSlice(name),
            @intCast(variant_count),
            v_names.ptr,
            v_types.ptr,
        );
        if (union_type.ptr == null) return;

        // Register union type
        self.unions.append(self.gpa, .{
            .name = name,
            .mlir_type = union_type,
            .variant_names = v_name_strs,
            .variant_types = v_type_mlirs,
        }) catch return;
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

        // Detect generic functions: any param with comptime_noalias + type == "type"
        // Reference: ac frontend currentTypeParams_ pattern (libac/codegen.cpp)
        // Instead of monomorphizing, emit function with !cir.type_param types.
        // The GenericSpecializer pass in libcot handles monomorphization.
        var type_param_names_buf: [8][]const u8 = undefined;
        var n_type_params: usize = 0;
        {
            var it = proto.iterate(tree);
            while (it.next()) |param| {
                if (param.comptime_noalias) |_| {
                    // Check if this is `comptime T: type`
                    if (param.type_expr) |type_node| {
                        if (tree.nodeTag(type_node) == .identifier) {
                            const type_name = tree.tokenSlice(tree.nodeMainToken(type_node));
                            if (std.mem.eql(u8, type_name, "type")) {
                                if (param.name_token) |name_tok| {
                                    type_param_names_buf[n_type_params] = tree.tokenSlice(name_tok);
                                    n_type_params += 1;
                                }
                            }
                        }
                    }
                }
            }
        }

        // Set current type params so resolveType returns !cir.type_param<"T">
        const saved_type_params = self.current_type_params;
        if (n_type_params > 0) {
            self.current_type_params = type_param_names_buf[0..n_type_params];
            // Register this as a generic function for call-site detection
            const names = self.gpa.alloc([]const u8, n_type_params) catch @panic("OOM");
            @memcpy(names, type_param_names_buf[0..n_type_params]);
            self.generic_func_names.append(self.gpa, fn_name) catch @panic("OOM");
            self.generic_func_type_params.append(self.gpa, names) catch @panic("OOM");
        } else {
            self.current_type_params = &.{};
        }

        // Collect runtime parameter types (skip comptime type params)
        var param_count: usize = 0;
        var param_types: [16]mlir.Type = undefined;
        var param_name_tokens: [16]?Ast.TokenIndex = undefined;
        {
            var it = proto.iterate(tree);
            while (it.next()) |param| {
                // Skip comptime type params (they are not runtime params)
                if (param.comptime_noalias) |_| {
                    if (param.type_expr) |type_node| {
                        if (tree.nodeTag(type_node) == .identifier) {
                            const type_name = tree.tokenSlice(tree.nodeMainToken(type_node));
                            if (std.mem.eql(u8, type_name, "type")) continue;
                        }
                    }
                }
                if (param.type_expr) |type_node| {
                    param_types[param_count] = self.resolveType(type_node);
                } else {
                    param_types[param_count] = self.i32Type();
                }
                param_name_tokens[param_count] = param.name_token;
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

        // Track return type for enum literal context inference
        self.current_return_type = if (n_results > 0) result_types[0] else .{ .ptr = null };

        const func = self.b.createFunc(
            self.module,
            fn_name,
            param_types[0..param_count],
            result_types[0..n_results],
        );
        self.current_func = func.func_op;

        // Store generic parameter names as attribute for the specializer
        // Reference: ac frontend emitFn() — sets cir.generic_params attribute
        if (n_type_params > 0) {
            var param_attrs: [8]mlir.Attribute = undefined;
            for (0..n_type_params) |i| {
                param_attrs[i] = mlir.mlirStringAttrGet(self.ctx, mlir.StringRef.fromSlice(type_param_names_buf[i]));
            }
            const arr_attr = mlir.mlirArrayAttrGet(self.ctx, @intCast(n_type_params), &param_attrs);
            mlir.mlirOperationSetAttributeByName(
                func.func_op,
                mlir.StringRef.fromSlice("cir.generic_params"),
                arr_attr,
            );
        }

        self.param_names.clearRetainingCapacity();
        self.param_values.clearRetainingCapacity();
        self.local_names.clearRetainingCapacity();
        self.local_addrs.clearRetainingCapacity();
        self.local_types.clearRetainingCapacity();
        {
            for (0..param_count) |i| {
                if (param_name_tokens[i]) |name_tok| {
                    self.param_names.append(self.gpa, tree.tokenSlice(name_tok)) catch @panic("OOM");
                    self.param_values.append(self.gpa, mlir.mlirBlockGetArgument(func.entry_block, @intCast(i))) catch @panic("OOM");
                }
            }
        }

        self.mapBody(func.entry_block, body_node, result_types[0..n_results]);

        // Restore saved type params
        self.current_type_params = saved_type_params;
    }

    /// Resolve a type name string to an MLIR type (for generic call type args).
    fn resolveTypeByName(self: *Gen, name: []const u8) mlir.Type {
        if (std.mem.eql(u8, name, "i8") or std.mem.eql(u8, name, "u8")) return self.b.intType(8);
        if (std.mem.eql(u8, name, "i16") or std.mem.eql(u8, name, "u16")) return self.b.intType(16);
        if (std.mem.eql(u8, name, "i32") or std.mem.eql(u8, name, "u32")) return self.b.intType(32);
        if (std.mem.eql(u8, name, "i64") or std.mem.eql(u8, name, "u64")) return self.b.intType(64);
        if (std.mem.eql(u8, name, "bool")) return self.b.intType(1);
        if (std.mem.eql(u8, name, "f32")) return mlir.mlirF32TypeGet(self.ctx);
        if (std.mem.eql(u8, name, "f64")) return mlir.mlirF64TypeGet(self.ctx);
        // Check struct types
        for (self.structs.items) |s| {
            if (std.mem.eql(u8, s.name, name)) return s.mlir_type;
        }
        return self.b.intType(32); // default fallback
    }

    fn mapTestDecl(self: *Gen, node: Node.Index) void {
        const tree = self.tree;
        const data = tree.nodeData(node);
        const body_node = data.opt_token_and_node[1];

        var name_buf: [32]u8 = undefined;
        const name = std.fmt.bufPrint(&name_buf, "__test_{d}", .{node}) catch "test";

        const func = self.b.createFunc(self.module, name, &.{}, &.{});
        self.current_func = func.func_op;
        self.param_names.clearRetainingCapacity();
        self.param_values.clearRetainingCapacity();
        self.local_names.clearRetainingCapacity();
        self.local_addrs.clearRetainingCapacity();
        self.local_types.clearRetainingCapacity();
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
        self.setLoc(node);
        const tag = self.tree.nodeTag(node);
        const blk = self.current_block;
        switch (tag) {
            .@"return" => {
                const ret_opt = self.tree.nodeData(node).opt_node;
                if (ret_opt.unwrap()) |ret_expr| {
                    if (result_types.len > 0) {
                        const ret_type = result_types[0];
                        // If return type is error union and the return expr
                        // is NOT an error value, emit with payload type then
                        // auto-wrap. Error values need the full EU type.
                        var emit_type = ret_type;
                        if (mlir.cirTypeIsErrorUnion(ret_type)) {
                            const ret_tag = self.tree.nodeTag(ret_expr);
                            if (ret_tag != .error_value) {
                                emit_type = mlir.cirErrorUnionTypeGetPayload(ret_type);
                            }
                        }
                        var val = self.mapExpr(blk, ret_expr, emit_type);
                        // After mapExpr, current_block may have changed (e.g. switch expr).
                        // Use current_block for the return emission.
                        const ret_blk = self.current_block;
                        // Auto-wrap into error union if needed
                        if (mlir.cirTypeIsErrorUnion(ret_type) and !mlir.cirTypeIsErrorUnion(mlir.mlirValueGetType(val))) {
                            val = mlir.cirBuildWrapResult(ret_blk, self.b.loc, ret_type, val);
                        }
                        _ = self.b.emit(ret_blk, "func.return", &.{}, &.{val}, &.{});
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

                // Detect if-unwrap: if (opt) |val| { ... }
                // Payload capture is indicated by pipe token after condition
                const payload_pipe = self.tree.lastToken(cond_node) + 2;
                const has_payload = self.tree.tokenTag(payload_pipe) == .pipe;

                if (has_payload) {
                    // If-unwrap: emit is_non_null + condbr + optional_payload in then block
                    // First emit the optional value (not as bool)
                    const opt_val = self.mapExpr(blk, cond_node, self.i32Type());
                    const opt_type = mlir.mlirValueGetType(opt_val);

                    if (mlir.cirTypeIsOptional(opt_type)) {
                        const cond = mlir.cirBuildIsNonNull(blk, self.b.loc, opt_val);
                        const then_block = self.addBlock();
                        const merge_block = self.addBlock();
                        mlir.cirBuildCondBr(blk, self.b.loc, cond, then_block, merge_block);

                        // Then block: extract payload, bind as parameter
                        const payload_type = mlir.cirOptionalTypeGetPayload(opt_type);
                        const payload = mlir.cirBuildOptionalPayload(then_block, self.b.loc, payload_type, opt_val);

                        // Bind captured variable: payload_token is the name
                        const capture_name = self.tree.tokenSlice(payload_pipe + 1);
                        // Store payload in alloca so it's accessible by name
                        const alloca = mlir.cirBuildAlloca(then_block, self.b.loc, payload_type);
                        mlir.cirBuildStore(then_block, self.b.loc, payload, alloca);
                        self.local_names.append(self.gpa, capture_name) catch @panic("OOM");
                        self.local_addrs.append(self.gpa, alloca) catch @panic("OOM");
                        self.local_types.append(self.gpa, payload_type) catch @panic("OOM");

                        self.mapBlock(then_block, then_node, result_types);
                        if (!self.has_terminator) {
                            const empty_args: [0]mlir.Value = undefined;
                            mlir.cirBuildBr(self.current_block, self.b.loc, merge_block, 0, &empty_args);
                        }

                        // Remove captured variable from scope
                        _ = self.local_names.pop();
                        _ = self.local_addrs.pop();
                        _ = self.local_types.pop();

                        self.current_block = merge_block;
                        self.has_terminator = false;
                    } else {
                        // Fallback: treat as regular bool if
                        const cond = self.mapExpr(blk, cond_node, self.b.intType(1));
                        const then_block = self.addBlock();
                        const merge_block = self.addBlock();
                        mlir.cirBuildCondBr(blk, self.b.loc, cond, then_block, merge_block);
                        self.mapBlock(then_block, then_node, result_types);
                        if (!self.has_terminator) {
                            const empty_args: [0]mlir.Value = undefined;
                            mlir.cirBuildBr(self.current_block, self.b.loc, merge_block, 0, &empty_args);
                        }
                        self.current_block = merge_block;
                        self.has_terminator = false;
                    }
                } else {
                    // Regular if: evaluate condition as bool
                    const cond = self.mapExpr(blk, cond_node, self.b.intType(1));
                    const then_block = self.addBlock();
                    const merge_block = self.addBlock();
                    mlir.cirBuildCondBr(blk, self.b.loc, cond, then_block, merge_block);
                    self.mapBlock(then_block, then_node, result_types);
                    if (!self.has_terminator) {
                        const empty_args: [0]mlir.Value = undefined;
                        mlir.cirBuildBr(self.current_block, self.b.loc, merge_block, 0, &empty_args);
                    }
                    self.current_block = merge_block;
                    self.has_terminator = false;
                }
            },
            .while_simple => {
                const d = self.tree.nodeData(node).node_and_node;
                const cond_node = d[0];
                const body_node = d[1];
                const header_block = self.addBlock();
                const body_block = self.addBlock();
                const exit_block = self.addBlock();
                // br to header
                const empty_args: [0]mlir.Value = undefined;
                mlir.cirBuildBr(blk, self.b.loc, header_block, 0, &empty_args);
                // header: eval condition, condbr
                self.current_block = header_block;
                const cond = self.mapExpr(header_block, cond_node, self.b.intType(1));
                mlir.cirBuildCondBr(header_block, self.b.loc, cond, body_block, exit_block);
                // body: statements + back-edge
                self.mapBlock(body_block, body_node, result_types);
                if (!self.has_terminator) {
                    mlir.cirBuildBr(self.current_block, self.b.loc, header_block, 0, &empty_args);
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
                const addr = mlir.cirBuildAlloca(blk, self.b.loc, var_type);
                if (init_node.unwrap()) |init_expr| {
                    const val = self.mapExpr(blk, init_expr, var_type);
                    // After mapExpr, current_block may have changed (e.g. switch expr)
                    const cur = self.current_block;
                    mlir.cirBuildStore(cur, self.b.loc, val, addr);
                }
                const tok = self.tree.nodeMainToken(node);
                const name = self.tree.tokenSlice(tok + 1);
                self.local_names.append(self.gpa, name) catch @panic("OOM");
                self.local_addrs.append(self.gpa, addr) catch @panic("OOM");
                self.local_types.append(self.gpa, var_type) catch @panic("OOM");
            },
            .assign => {
                const d = self.tree.nodeData(node).node_and_node;
                const lhs_node = d[0];
                const rhs_node = d[1];
                const name = self.tree.tokenSlice(self.tree.nodeMainToken(lhs_node));
                if (self.resolveLocal(name)) |local| {
                    const val = self.mapExpr(blk, rhs_node, local.elem_type);
                    mlir.cirBuildStore(blk, self.b.loc, val, local.addr);
                }
            },
            .assign_add, .assign_sub, .assign_mul, .assign_div, .assign_mod => {
                const d = self.tree.nodeData(node).node_and_node;
                const lhs_node = d[0];
                const rhs_node = d[1];
                const name = self.tree.tokenSlice(self.tree.nodeMainToken(lhs_node));
                if (self.resolveLocal(name)) |local| {
                    const current = mlir.cirBuildLoad(blk, self.b.loc, local.elem_type, local.addr);
                    const rhs = self.mapExpr(blk, rhs_node, local.elem_type);
                    const op_fn: BinOpFn = switch (tag) {
                        .assign_add => mlir.cirBuildAdd,
                        .assign_sub => mlir.cirBuildSub,
                        .assign_mul => mlir.cirBuildMul,
                        .assign_div => mlir.cirBuildDiv,
                        .assign_mod => mlir.cirBuildRem,
                        else => unreachable,
                    };
                    const result = op_fn(blk, self.b.loc, local.elem_type, current, rhs);
                    mlir.cirBuildStore(blk, self.b.loc, result, local.addr);
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
        self.setLoc(node);
        const tree = self.tree;
        const tag = tree.nodeTag(node);
        return switch (tag) {
            .number_literal => self.mapNumberLit(block, node, result_type),
            .identifier => self.mapIdentifier(block, node),
            .negation => self.mapUnaryOp(block, node, mlir.cirBuildNeg, result_type),
            .bit_not => self.mapUnaryOp(block, node, mlir.cirBuildBitNot, result_type),
            .bit_and => self.mapBinOp(block, node, mlir.cirBuildBitAnd, result_type),
            .bit_or => self.mapBinOp(block, node, mlir.cirBuildBitOr, result_type),
            .bit_xor => self.mapBinOp(block, node, mlir.cirBuildBitXor, result_type),
            .shl => self.mapBinOp(block, node, mlir.cirBuildShl, result_type),
            .shr => self.mapBinOp(block, node, mlir.cirBuildShr, result_type),
            .add => self.mapBinOp(block, node, mlir.cirBuildAdd, result_type),
            .sub => self.mapBinOp(block, node, mlir.cirBuildSub, result_type),
            .mul => self.mapBinOp(block, node, mlir.cirBuildMul, result_type),
            .div => self.mapBinOp(block, node, mlir.cirBuildDiv, result_type),
            .mod => self.mapBinOp(block, node, mlir.cirBuildRem, result_type),
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
                const zero = mlir.cirBuildConstantInt(block, self.b.loc, result_type, 0);
                break :blk2 mlir.cirBuildSelect(block, self.b.loc, result_type, cond, then_val, zero);
            },
            .@"if" => blk2: {
                // if (cond) then_val else else_val — full if expression
                const cond_node, const extra_index = tree.nodeData(node).node_and_extra;
                const extra = tree.extraData(extra_index, Node.If);
                const cond = self.mapExpr(block, cond_node, self.b.intType(1));
                const then_val = self.mapExpr(block, extra.then_expr, result_type);
                const else_val = self.mapExpr(block, extra.else_expr, result_type);
                break :blk2 mlir.cirBuildSelect(block, self.b.loc, result_type, cond, then_val, else_val);
            },
            .grouped_expression => blk2: {
                const inner = tree.nodeData(node).node_and_token[0];
                break :blk2 self.mapExpr(block, inner, result_type);
            },
            // Address-of: &x → cir.addr_of
            .address_of => blk2: {
                const operand_node = tree.nodeData(node).node;
                // Get the alloca address for the local
                const operand_tok = tree.nodeMainToken(operand_node);
                const name = tree.tokenSlice(operand_tok);
                if (self.resolveLocal(name)) |local| {
                    // Build !cir.ref<T> type string
                    const elem_name = self.resolveTypeName(tree.nodeData(operand_node).opt_node_and_opt_node[0].unwrap() orelse operand_node);
                    _ = elem_name;
                    // Use parseType to build the ref type
                    var buf3: [64]u8 = undefined;
                    const ref_type_str = std.fmt.bufPrint(&buf3, "!cir.ref<{s}>", .{self.resolveTypeName2(local.elem_type)}) catch break :blk2 mlir.Value{ .ptr = null };
                    const ref_type = self.b.parseType(ref_type_str);
                    break :blk2 mlir.cirBuildAddrOf(block, self.b.loc, ref_type, local.addr);
                }
                break :blk2 mlir.Value{ .ptr = null };
            },
            // Dereference: p.* → cir.deref
            .deref => blk2: {
                const operand_node = tree.nodeData(node).node;
                const operand = self.mapExpr(block, operand_node, result_type);
                break :blk2 mlir.cirBuildDeref(block, self.b.loc, result_type, operand);
            },
            // Field access: p.x → cir.field_val
            // Auto-deref: if p is *Point (!cir.ref<StructType>), insert implicit deref
            // Reference: Zig/Rust/Go auto-deref through pointers on field access
            .field_access => blk2: {
                const d = tree.nodeData(node).node_and_token;
                const obj_node = d[0];
                const field_tok = d[1];
                const field_name = tree.tokenSlice(field_tok);
                var obj = self.mapExpr(block, obj_node, result_type);
                var obj_type = mlir.mlirValueGetType(obj);
                // Slice field access: s.len → slice_len, s.ptr → slice_ptr
                if (mlir.cirTypeIsSlice(obj_type)) {
                    if (std.mem.eql(u8, field_name, "len"))
                        break :blk2 mlir.cirBuildSliceLen(block, self.b.loc, obj);
                    if (std.mem.eql(u8, field_name, "ptr"))
                        break :blk2 mlir.cirBuildSlicePtr(block, self.b.loc, obj);
                    break :blk2 mlir.Value{ .ptr = null };
                }
                // Auto-deref: if field lookup fails, try deref first (pointer to struct)
                var field_idx = self.findFieldIndex(obj_type, field_name);
                if (field_idx < 0) {
                    // Try deref — obj might be !cir.ref<StructType>
                    obj = mlir.cirBuildDeref(block, self.b.loc, result_type, obj);
                    obj_type = mlir.mlirValueGetType(obj);
                    field_idx = self.findFieldIndex(obj_type, field_name);
                }
                if (field_idx < 0) break :blk2 mlir.Value{ .ptr = null };
                break :blk2 mlir.cirBuildFieldVal(block, self.b.loc, result_type, obj, field_idx);
            },
            // Struct init: Point{ .x = 1, .y = 2 }
            // Reference: ~/claude/references/zig/lib/std/zig/AstGen.zig structInitExpr
            .struct_init_one, .struct_init_one_comma,
            .struct_init, .struct_init_comma,
            => blk2: {
                break :blk2 self.mapStructInit(block, node, result_type);
            },
            // Array init: .{ 1, 2, 3 } or [3]i32{ 1, 2, 3 }
            .array_init_dot_two, .array_init_dot_two_comma,
            .array_init_dot, .array_init_dot_comma,
            .array_init_one, .array_init_one_comma,
            .array_init, .array_init_comma,
            => blk2: {
                break :blk2 self.mapArrayInit(block, node, result_type);
            },
            // Array access: arr[i]
            .array_access => blk2: {
                break :blk2 self.mapArrayAccess(block, node, result_type);
            },
            // Zig builtins: @intCast, @floatCast, @truncate, @floatFromInt
            // Reference: ~/claude/references/zig/lib/std/zig/AstGen.zig typeCast
            .builtin_call_two, .builtin_call_two_comma => blk2: {
                break :blk2 self.mapBuiltinCall(block, node, result_type);
            },
            // String literal: "hello" → cir.string_constant
            .string_literal => blk2: {
                break :blk2 self.mapStringLit(block, node);
            },
            // try expr — error union unwrap with error propagation
            // Reference: Zig AstGen — try node has data.node (the operand)
            .@"try" => blk2: {
                break :blk2 self.mapTryExpr(block, node, result_type);
            },
            // catch expr — error union unwrap with fallback
            // Reference: Zig AstGen — catch node has data.node_and_node
            .@"catch" => blk2: {
                break :blk2 self.mapCatchExpr(block, node, result_type);
            },
            // error.Name — error set value → i16 constant
            // Reference: Zig AstGen — error_value main_token is `error`, name at main_token + 2
            .error_value => blk2: {
                break :blk2 self.mapErrorValue(block, node, result_type);
            },
            // Enum literal: .red → cir.enum_constant
            // The main_token is the variant identifier (e.g. "red").
            // The enum type is inferred from result_type (context).
            .enum_literal => blk2: {
                break :blk2 self.mapEnumLiteral(block, node, result_type);
            },
            // Switch expression: switch (c) { .red => 1, .green => 2, .blue => 3 }
            // Reference: Zig AstGen switchExpr — fullSwitch + fullSwitchCase
            .@"switch", .switch_comma => blk2: {
                break :blk2 self.mapSwitchExpr(block, node, result_type);
            },
            else => mlir.cirBuildConstantInt(block, self.b.loc, result_type, 0),
        };
    }

    fn mapStringLit(self: *Gen, block: mlir.Block, node: Node.Index) mlir.Value {
        const tok = self.tree.nodeMainToken(node);
        const raw = self.tree.tokenSlice(tok);
        // Strip surrounding quotes: "hello" → hello
        const str_content = if (raw.len >= 2 and raw[0] == '"' and raw[raw.len - 1] == '"')
            raw[1 .. raw.len - 1]
        else
            raw;
        return mlir.cirBuildStringConstant(block, self.b.loc, mlir.StringRef.fromSlice(str_content));
    }

    fn mapNumberLit(self: *Gen, block: mlir.Block, node: Node.Index, result_type: mlir.Type) mlir.Value {
        const tok = self.tree.nodeMainToken(node);
        const text = self.tree.tokenSlice(tok);
        const val = std.fmt.parseInt(i64, text, 10) catch 0;
        // If result type is error union, emit constant with payload type then wrap
        if (mlir.cirTypeIsErrorUnion(result_type)) {
            const payload_type = mlir.cirErrorUnionTypeGetPayload(result_type);
            const payload_val = mlir.cirBuildConstantInt(block, self.b.loc, payload_type, val);
            return mlir.cirBuildWrapResult(block, self.b.loc, result_type, payload_val);
        }
        return mlir.cirBuildConstantInt(block, self.b.loc, result_type, val);
    }

    fn mapIdentifier(self: *Gen, block: mlir.Block, node: Node.Index) mlir.Value {
        const tok = self.tree.nodeMainToken(node);
        const name = self.tree.tokenSlice(tok);
        if (std.mem.eql(u8, name, "true")) {
            return mlir.cirBuildConstantBool(block, self.b.loc, true);
        }
        if (std.mem.eql(u8, name, "false")) {
            return mlir.cirBuildConstantBool(block, self.b.loc, false);
        }
        if (std.mem.eql(u8, name, "null")) {
            // null literal — need optional type from context
            // For now, use i32 optional as default
            const opt_type = mlir.cirOptionalTypeGet(self.ctx, self.b.intType(32));
            return mlir.cirBuildNone(block, self.b.loc, opt_type);
        }
        if (self.resolveLocal(name)) |local| {
            return mlir.cirBuildLoad(block, self.b.loc, local.elem_type, local.addr);
        }
        return self.resolve(name) orelse mlir.Value{ .ptr = null };
    }

    fn mapUnaryOp(self: *Gen, block: mlir.Block, node: Node.Index, op_fn: UnaryOpFn, result_type: mlir.Type) mlir.Value {
        const operand_node = self.tree.nodeData(node).node;
        const operand = self.mapExpr(block, operand_node, result_type);
        return op_fn(block, self.b.loc, result_type, operand);
    }

    fn mapBinOp(self: *Gen, block: mlir.Block, node: Node.Index, op_fn: BinOpFn, result_type: mlir.Type) mlir.Value {
        const d = self.tree.nodeData(node).node_and_node;
        const lhs = self.mapExpr(block, d[0], result_type);
        const rhs = self.mapExpr(block, d[1], result_type);
        return op_fn(block, self.b.loc, result_type, lhs, rhs);
    }

    fn mapCmp(self: *Gen, block: mlir.Block, node: Node.Index, predicate: c_int) mlir.Value {
        const d = self.tree.nodeData(node).node_and_node;
        const operand_type = self.i32Type();
        const lhs = self.mapExpr(block, d[0], operand_type);
        const rhs = self.mapExpr(block, d[1], operand_type);
        return mlir.cirBuildCmp(block, self.b.loc, predicate, lhs, rhs);
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
        if (std.mem.eql(u8, builtin_name, "@divTrunc")) {
            // @divTrunc(a, b): signed integer division → cir.div
            const arg2_node = d[1].unwrap() orelse return mlir.Value{ .ptr = null };
            const lhs = self.mapExpr(block, arg_node, result_type);
            const rhs = self.mapExpr(block, arg2_node, result_type);
            return mlir.cirBuildDiv(block, self.b.loc, result_type, lhs, rhs);
        }
        if (std.mem.eql(u8, builtin_name, "@mod")) {
            // @mod(a, b): signed integer remainder → cir.rem
            const arg2_node = d[1].unwrap() orelse return mlir.Value{ .ptr = null };
            const lhs = self.mapExpr(block, arg_node, result_type);
            const rhs = self.mapExpr(block, arg2_node, result_type);
            return mlir.cirBuildRem(block, self.b.loc, result_type, lhs, rhs);
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
                return mlir.cirBuildExtSI(block, self.b.loc, dst_type, src);
            }
            if (dst_w < src_w) {
                return mlir.cirBuildTruncI(block, self.b.loc, dst_type, src);
            }
            return src;
        }
        if (src_int and dst_float)
            return mlir.cirBuildSIToFP(block, self.b.loc, dst_type, src);
        if (src_float and dst_int)
            return mlir.cirBuildFPToSI(block, self.b.loc, dst_type, src);
        if (src_float and dst_float) {
            const src_w = mlir.mlirFloatTypeGetWidth(src_type);
            const dst_w = mlir.mlirFloatTypeGetWidth(dst_type);
            if (dst_w > src_w)
                return mlir.cirBuildExtF(block, self.b.loc, dst_type, src);
            if (dst_w < src_w)
                return mlir.cirBuildTruncF(block, self.b.loc, dst_type, src);
            return src;
        }
        return src; // unsupported — fallback
    }

    /// Get MLIR type name string from an MLIR Type value.
    /// Used to construct composite type strings like !cir.ref<i32>.
    fn resolveTypeName2(_: *Gen, ty: mlir.Type) []const u8 {
        if (mlir.mlirTypeIsAInteger(ty)) {
            const w = mlir.mlirIntegerTypeGetWidth(ty);
            return switch (w) {
                1 => "i1",
                8 => "i8",
                16 => "i16",
                32 => "i32",
                64 => "i64",
                else => "i32",
            };
        }
        if (mlir.mlirTypeIsAFloat(ty)) {
            const w = mlir.mlirFloatTypeGetWidth(ty);
            return if (w == 32) "f32" else "f64";
        }
        return "i32";
    }

    /// Find field index by name in a struct type.
    /// Matches against registered StructInfo entries.
    fn findFieldIndex(self: *Gen, struct_type: mlir.Type, field_name: []const u8) i64 {
        for (self.structs.items) |si| {
            if (mlir.mlirTypeEqual(si.mlir_type, struct_type)) {
                for (si.field_names, 0..) |fn_name, j| {
                    if (std.mem.eql(u8, fn_name, field_name)) return @intCast(j);
                }
                return -1;
            }
        }
        return -1;
    }

    /// Handle Zig struct init: Point{ .x = 1, .y = 2 }
    /// Reference: Zig AstGen structInitExprTyped — field name at firstToken(field) - 2
    fn mapStructInit(self: *Gen, block: mlir.Block, node: Node.Index, _: mlir.Type) mlir.Value {
        const tree = self.tree;
        const tag = tree.nodeTag(node);

        // Get type expression and field nodes (handle one-field and multi-field variants)
        var fields_buf: [1]Node.Index = undefined;
        var type_expr_node: Node.Index = undefined;
        var fields: []const Node.Index = undefined;

        switch (tag) {
            .struct_init_one, .struct_init_one_comma => {
                const d = tree.nodeData(node).node_and_opt_node;
                type_expr_node = d[0];
                if (d[1].unwrap()) |f| {
                    fields_buf[0] = f;
                    fields = fields_buf[0..1];
                } else {
                    fields = fields_buf[0..0];
                }
            },
            .struct_init, .struct_init_comma => {
                const d = tree.nodeData(node).node_and_extra;
                type_expr_node = d[0];
                const sub_range = tree.extraData(d[1], Node.SubRange);
                fields = tree.extraDataSlice(sub_range, Node.Index);
            },
            else => return mlir.Value{ .ptr = null },
        }

        // Resolve type from the type expression identifier
        const type_name = tree.tokenSlice(tree.nodeMainToken(type_expr_node));

        // Check if this is a tagged union init: Shape{ .circle = r }
        // Tagged unions use struct_init syntax but emit cir.union_init.
        for (self.unions.items) |ui| {
            if (std.mem.eql(u8, ui.name, type_name)) {
                return self.mapUnionInit(block, fields, &ui);
            }
        }

        // Otherwise, it's a struct init
        var found_struct: ?StructInfo = null;
        for (self.structs.items) |s| {
            if (std.mem.eql(u8, s.name, type_name)) {
                found_struct = s;
                break;
            }
        }
        const si = found_struct orelse return mlir.Value{ .ptr = null };
        const struct_type = si.mlir_type;
        const n_fields = si.field_types.len;

        // Build field values in struct declaration order.
        // For each source field (.name = val), find its position in the struct.
        const field_values = self.gpa.alloc(mlir.Value, n_fields) catch return mlir.Value{ .ptr = null };
        defer self.gpa.free(field_values);
        // Initialize all to zero (in case source doesn't provide all fields)
        for (0..n_fields) |i| {
            field_values[i] = mlir.cirBuildConstantInt(block, self.b.loc, si.field_types[i], 0);
        }
        for (fields) |field_node| {
            // Field name is at firstToken(value_expr) - 2 (Zig AstGen pattern)
            const first_tok = tree.firstToken(field_node);
            const field_name = tree.tokenSlice(first_tok - 2);
            // Find index in struct declaration
            for (0..n_fields) |j| {
                if (std.mem.eql(u8, si.field_names[j], field_name)) {
                    field_values[j] = self.mapExpr(block, field_node, si.field_types[j]);
                    break;
                }
            }
        }

        return mlir.cirBuildStructInit(block, self.b.loc, struct_type, @intCast(n_fields), field_values[0..n_fields].ptr);
    }

    /// Handle tagged union init: Shape{ .circle = r } → cir.union_init "circle"
    /// Union init uses struct_init syntax in Zig, but we detect the union type
    /// and emit cir.union_init (with payload) or cir.union_init_void (no payload).
    fn mapUnionInit(self: *Gen, block: mlir.Block, fields: []const Node.Index, ui: *const UnionInfo) mlir.Value {
        const tree = self.tree;
        const union_type = ui.mlir_type;

        // Tagged union init has exactly one field: Shape{ .circle = r }
        // (or zero fields for void variant, which would be unusual syntax)
        if (fields.len == 0) {
            // No variant specified — shouldn't happen in valid Zig
            return mlir.Value{ .ptr = null };
        }

        // Extract variant name: field name is at firstToken(value_expr) - 2
        const field_node = fields[0];
        const first_tok = tree.firstToken(field_node);
        const variant_name = tree.tokenSlice(first_tok - 2);
        const variant_ref = mlir.StringRef.fromSlice(variant_name);

        // Find variant type
        var variant_type: mlir.Type = self.b.intType(0); // default void
        for (ui.variant_names, 0..) |vn, i| {
            if (std.mem.eql(u8, vn, variant_name)) {
                variant_type = ui.variant_types[i];
                break;
            }
        }

        // Check if this is a void variant (i0 type)
        if (mlir.mlirTypeIsAInteger(variant_type) and mlir.mlirIntegerTypeGetWidth(variant_type) == 0) {
            return mlir.cirBuildUnionInitVoid(block, self.b.loc, union_type, variant_ref);
        }

        // Emit payload expression and build union_init
        const payload = self.mapExpr(block, field_node, variant_type);
        return mlir.cirBuildUnionInit(block, self.b.loc, union_type, variant_ref, payload);
    }

    /// Handle array init: .{ 1, 2, 3 } → cir.array_init
    fn mapArrayInit(self: *Gen, block: mlir.Block, node: Node.Index, _: mlir.Type) mlir.Value {
        const tree = self.tree;
        const tag = tree.nodeTag(node);
        // Get element nodes based on variant
        var elems_buf: [2]Node.Index = undefined;
        var elements: []const Node.Index = undefined;
        switch (tag) {
            .array_init_dot_two, .array_init_dot_two_comma => {
                const d = tree.nodeData(node).opt_node_and_opt_node;
                var count: usize = 0;
                if (d[0].unwrap()) |n| { elems_buf[count] = n; count += 1; }
                if (d[1].unwrap()) |n| { elems_buf[count] = n; count += 1; }
                elements = elems_buf[0..count];
            },
            .array_init_dot, .array_init_dot_comma => {
                elements = tree.extraDataSlice(tree.nodeData(node).extra_range, Node.Index);
            },
            .array_init_one, .array_init_one_comma => {
                const d = tree.nodeData(node).node_and_opt_node;
                if (d[1].unwrap()) |n| {
                    elems_buf[0] = n;
                    elements = elems_buf[0..1];
                } else {
                    elements = elems_buf[0..0];
                }
            },
            .array_init, .array_init_comma => {
                const d = tree.nodeData(node).node_and_extra;
                const sub_range = tree.extraData(d[1], Node.SubRange);
                elements = tree.extraDataSlice(sub_range, Node.Index);
            },
            else => return mlir.Value{ .ptr = null },
        }
        // Build array type string and parse it
        var type_buf: [64]u8 = undefined;
        const type_str = std.fmt.bufPrint(&type_buf, "!cir.array<{d} x i32>", .{elements.len}) catch return mlir.Value{ .ptr = null };
        const array_type = self.b.parseType(type_str);
        // Emit elements
        const elem_vals = self.gpa.alloc(mlir.Value, elements.len) catch @panic("OOM");
        defer self.gpa.free(elem_vals);
        for (elements, 0..) |elem_node, i| {
            elem_vals[i] = self.mapExpr(block, elem_node, self.i32Type());
        }
        return mlir.cirBuildArrayInit(block, self.b.loc, array_type, @intCast(elem_vals.len), elem_vals.ptr);
    }

    /// Handle array access: arr[i] → cir.elem_val for constant index
    fn mapArrayAccess(self: *Gen, block: mlir.Block, node: Node.Index, result_type: mlir.Type) mlir.Value {
        const tree = self.tree;
        const d = tree.nodeData(node).node_and_node;
        const arr_node = d[0];
        const idx_node = d[1];
        // Get the array/slice value
        const arr = self.mapExpr(block, arr_node, result_type);
        const arr_type = mlir.mlirValueGetType(arr);
        // Slice indexing: s[i] → cir.slice_elem
        if (mlir.cirTypeIsSlice(arr_type)) {
            const idx = self.mapExpr(block, idx_node, self.b.intType(64));
            return mlir.cirBuildSliceElem(block, self.b.loc, result_type, arr, idx);
        }
        // Array indexing: arr[i] → cir.elem_val (constant index)
        var idx_val: i64 = 0;
        if (tree.nodeTag(idx_node) == .number_literal) {
            const tok = tree.nodeMainToken(idx_node);
            const text = tree.tokenSlice(tok);
            idx_val = std.fmt.parseInt(i64, text, 10) catch 0;
        }
        return mlir.cirBuildElemVal(block, self.b.loc, result_type, arr, idx_val);
    }

    fn mapCall(self: *Gen, block: mlir.Block, node: Node.Index, result_type: mlir.Type) mlir.Value {
        const tree = self.tree;
        var call_buf: [1]Node.Index = undefined;
        const call = tree.fullCall(&call_buf, node) orelse return mlir.Value{ .ptr = null };
        const fn_expr_tag = tree.nodeTag(call.ast.fn_expr);

        // Method call: p.distance() — callee is a field_access node
        // Reference: Zig AstGen — methods desugar to function call with receiver as first arg
        // Phase 7b+: If receiver is type_param, emit cir.method_call (structural dispatch)
        // Reference: Zig ZIR field_call — resolved by Sema's fieldCallBind()
        if (fn_expr_tag == .field_access) {
            const d = tree.nodeData(call.ast.fn_expr).node_and_token;
            const obj_node = d[0];
            const method_tok = d[1];
            const method_name = tree.tokenSlice(method_tok);
            // Emit receiver as first argument
            const receiver = self.mapExpr(block, obj_node, result_type);
            const n_params = call.ast.params.len;
            const args = self.gpa.alloc(mlir.Value, n_params + 1) catch @panic("OOM");
            defer self.gpa.free(args);
            args[0] = receiver;
            for (call.ast.params, 0..) |param_node, i| {
                args[i + 1] = self.mapExpr(block, param_node, result_type);
            }

            // Check if receiver is a type_param — use cir.method_call for structural dispatch
            // Reference: Zig ZIR field_call → Sema fieldCallBind() name lookup
            const receiver_type = mlir.mlirValueGetType(receiver);
            if (mlir.cirTypeIsTypeParam(receiver_type)) {
                return mlir.cirBuildMethodCall(block, self.b.loc, mlir.StringRef.fromSlice(method_name), @intCast(n_params + 1), args.ptr, result_type);
            }

            return self.b.emit(block, "func.call", &.{result_type}, args, &.{
                self.b.attr("callee", mlir.mlirFlatSymbolRefAttrGet(self.ctx, mlir.StringRef.fromSlice(method_name))),
            });
        }

        // Regular function call
        const callee_name = tree.tokenSlice(tree.nodeMainToken(call.ast.fn_expr));

        // Check if callee is a generic function — emit cir.generic_apply
        // Reference: ac frontend GenericCall handling in libac/codegen.cpp
        // Frontends emit cir.generic_apply; GenericSpecializer pass monomorphizes.
        for (self.generic_func_names.items, 0..) |gname, gi| {
            if (std.mem.eql(u8, gname, callee_name)) {
                const tp_names = self.generic_func_type_params.items[gi];
                const n_type_params = tp_names.len;
                // First N args are comptime type args (identifiers)
                var subs_keys: [8]mlir.StringRef = undefined;
                var subs_types: [8]mlir.Type = undefined;
                for (0..n_type_params) |ti| {
                    if (ti >= call.ast.params.len) break;
                    const type_arg_node = call.ast.params[ti];
                    // The type arg should be an identifier (e.g., "i32")
                    const type_arg_name = tree.tokenSlice(tree.nodeMainToken(type_arg_node));
                    subs_keys[ti] = mlir.StringRef.fromSlice(tp_names[ti]);
                    subs_types[ti] = self.resolveTypeByName(type_arg_name);
                }
                // Emit runtime (non-type) args
                const n_runtime_args = call.ast.params.len - n_type_params;
                const args = self.gpa.alloc(mlir.Value, n_runtime_args) catch @panic("OOM");
                defer self.gpa.free(args);
                for (0..n_runtime_args) |i| {
                    args[i] = self.mapExpr(block, call.ast.params[n_type_params + i], result_type);
                }
                // Emit cir.generic_apply op
                return mlir.cirBuildGenericApply(
                    block,
                    self.b.loc,
                    mlir.StringRef.fromSlice(callee_name),
                    @intCast(n_runtime_args),
                    if (n_runtime_args > 0) args.ptr else undefined,
                    result_type,
                    @intCast(n_type_params),
                    &subs_keys,
                    &subs_types,
                );
            }
        }

        // Non-generic function call
        const args = self.gpa.alloc(mlir.Value, call.ast.params.len) catch @panic("OOM");
        defer self.gpa.free(args);
        for (call.ast.params, 0..) |param_node, i| {
            args[i] = self.mapExpr(block, param_node, result_type);
        }
        return self.b.emit(block, "func.call", &.{result_type}, args, &.{
            self.b.attr("callee", mlir.mlirFlatSymbolRefAttrGet(self.ctx, mlir.StringRef.fromSlice(callee_name))),
        });
    }

    // ============================================================
    // Error union handling — try/catch/error.Name
    // Reference: Zig AstGen — try unwraps error union, propagates on error
    // ============================================================

    /// `try expr` — evaluate expr, if error propagate it (return error),
    /// otherwise unwrap to payload.
    /// Emits: is_error check → condbr → error path (return error code) / success path (payload)
    fn mapTryExpr(self: *Gen, block: mlir.Block, node: Node.Index, result_type: mlir.Type) mlir.Value {
        const operand_node = self.tree.nodeData(node).node;
        // Build the error union type from the expected payload (result_type)
        const eu_type = mlir.cirErrorUnionTypeGet(self.ctx, result_type);
        const eu_val = self.mapExpr(block, operand_node, eu_type);

        // Check if the value is an error
        const is_err = mlir.cirBuildIsError(block, self.b.loc, eu_val);

        // Create blocks: error path and success path
        const err_block = self.addBlock();
        const ok_block = self.addBlock();
        mlir.cirBuildCondBr(block, self.b.loc, is_err, err_block, ok_block);

        // Error path: extract error code, wrap in function's return EU type, return it
        const err_code = mlir.cirBuildErrorCode(err_block, self.b.loc, eu_val);
        // Propagate: wrap error code in the function's return error union type and return
        // For now, return the error code as i16 via func.return
        // (The caller's return type should be an error union — the verifier will catch mismatches)
        const ret_eu_type = mlir.cirErrorUnionTypeGet(self.ctx, result_type);
        const wrapped_err = mlir.cirBuildWrapError(err_block, self.b.loc, ret_eu_type, err_code);
        _ = self.b.emit(err_block, "func.return", &.{}, &.{wrapped_err}, &.{});

        // Success path: extract payload — this becomes our current insertion block
        const payload = mlir.cirBuildErrorPayload(ok_block, self.b.loc, result_type, eu_val);
        self.current_block = ok_block;
        return payload;
    }

    /// `expr catch fallback` — evaluate expr, if error use fallback, otherwise payload.
    /// Emits: is_error check → condbr → error path (eval fallback) / success path (payload)
    /// Both paths branch to a merge block with a block argument for the result.
    fn mapCatchExpr(self: *Gen, block: mlir.Block, node: Node.Index, result_type: mlir.Type) mlir.Value {
        const d = self.tree.nodeData(node).node_and_node;
        const lhs_node = d[0]; // error union expression
        const rhs_node = d[1]; // fallback expression

        // Build the error union type from the expected payload (result_type)
        const eu_type = mlir.cirErrorUnionTypeGet(self.ctx, result_type);
        const eu_val = self.mapExpr(block, lhs_node, eu_type);

        // Check if the value is an error
        const is_err = mlir.cirBuildIsError(block, self.b.loc, eu_val);

        // Create blocks: error (fallback) path, success (payload) path, merge
        const err_block = self.addBlock();
        const ok_block = self.addBlock();
        const merge_block = self.b.createBlock(&.{result_type});
        // Add merge block to function region
        const region = mlir.mlirOperationGetRegion(self.current_func, 0);
        mlir.mlirRegionAppendOwnedBlock(region, merge_block);

        mlir.cirBuildCondBr(block, self.b.loc, is_err, err_block, ok_block);

        // Error path: evaluate fallback, branch to merge with fallback value
        const fallback_val = self.mapExpr(err_block, rhs_node, result_type);
        mlir.cirBuildBr(err_block, self.b.loc, merge_block, 1, &[_]mlir.Value{fallback_val});

        // Success path: extract payload, branch to merge with payload value
        const payload = mlir.cirBuildErrorPayload(ok_block, self.b.loc, result_type, eu_val);
        mlir.cirBuildBr(ok_block, self.b.loc, merge_block, 1, &[_]mlir.Value{payload});

        // Continue in merge block — result is the block argument
        self.current_block = merge_block;
        return mlir.mlirBlockGetArgument(merge_block, 0);
    }

    /// `error.Name` — Zig error set literal → i16 constant.
    /// Maps error names to unique i16 codes via simple hashing.
    /// Reference: Zig AstGen — error_value main_token is `error`, name at main_token + 2
    fn mapErrorValue(self: *Gen, block: mlir.Block, node: Node.Index, result_type: mlir.Type) mlir.Value {
        const main_tok = self.tree.nodeMainToken(node);
        // error.Name — the name token is at main_token + 2 (skip `error` and `.`)
        const name_tok = main_tok + 2;
        const name = self.tree.tokenSlice(name_tok);

        // Map error name to a stable i16 code via simple hash.
        // Code 0 is reserved for "no error" (success), so start from 1.
        var hash: u16 = 0;
        for (name) |c| {
            hash = hash *% 31 +% @as(u16, c);
        }
        if (hash == 0) hash = 1; // avoid 0 (success sentinel)
        const code: i64 = @intCast(hash);

        // If result_type is an error union, wrap the code
        if (mlir.cirTypeIsErrorUnion(result_type)) {
            const err_code = mlir.cirBuildConstantInt(block, self.b.loc, self.b.intType(16), code);
            return mlir.cirBuildWrapError(block, self.b.loc, result_type, err_code);
        }

        // Otherwise return raw i16 error code
        return mlir.cirBuildConstantInt(block, self.b.loc, self.b.intType(16), code);
    }

    /// `.red` — Zig enum literal. Resolve type from context (result_type) or
    /// current function return type. Emit cir.enum_constant with the enum type.
    /// Reference: Zig AstGen — enum_literal main_token is the variant identifier.
    fn mapEnumLiteral(self: *Gen, block: mlir.Block, node: Node.Index, result_type: mlir.Type) mlir.Value {
        const tok = self.tree.nodeMainToken(node);
        const variant_name = self.tree.tokenSlice(tok);

        // Try to determine the enum type:
        // 1. If result_type is an enum type, use it directly
        // 2. Fall back to current function return type
        var enum_type = result_type;
        if (!mlir.cirTypeIsEnum(enum_type)) {
            enum_type = self.current_return_type;
        }
        if (!mlir.cirTypeIsEnum(enum_type)) {
            // Cannot resolve enum type — search enums for a matching variant
            for (self.enums.items) |e| {
                for (e.variant_names) |vn| {
                    if (std.mem.eql(u8, vn, variant_name)) {
                        enum_type = e.mlir_type;
                        break;
                    }
                }
                if (mlir.cirTypeIsEnum(enum_type)) break;
            }
        }
        if (!mlir.cirTypeIsEnum(enum_type)) {
            // Still can't resolve — emit zero constant as fallback
            return mlir.cirBuildConstantInt(block, self.b.loc, result_type, 0);
        }

        return mlir.cirBuildEnumConstant(block, self.b.loc, enum_type, mlir.StringRef.fromSlice(variant_name));
    }

    /// Handle Zig switch expression: switch (c) { .red => 1, .green => 2, .blue => 3 }
    /// Emits cir.enum_value to extract integer tag, then cir.switch for multi-way branch.
    /// Each case block evaluates the arm expression and branches to merge with the result.
    /// Reference: Zig AstGen switchExpr — fullSwitch, fullSwitchCase
    fn mapSwitchExpr(self: *Gen, block: mlir.Block, node: Node.Index, result_type: mlir.Type) mlir.Value {
        const tree = self.tree;
        const d = tree.nodeData(node).node_and_extra;
        const cond_node = d[0];
        const sub_range = tree.extraData(d[1], Node.SubRange);
        const cases = tree.extraDataSlice(sub_range, Node.Index);

        // Evaluate the switch condition
        const cond_val = self.mapExpr(block, cond_node, self.i32Type());
        const cond_type = mlir.mlirValueGetType(cond_val);

        // If condition is an enum, extract the integer tag
        var switch_val = cond_val;
        var tag_type = cond_type;
        if (mlir.cirTypeIsEnum(cond_type)) {
            tag_type = mlir.cirEnumTypeGetTagType(cond_type);
            switch_val = mlir.cirBuildEnumValue(block, self.b.loc, tag_type, cond_val);
        }

        // Create merge block with a block argument for the result value
        const merge_block = self.b.createBlock(&.{result_type});
        const region = mlir.mlirOperationGetRegion(self.current_func, 0);
        mlir.mlirRegionAppendOwnedBlock(region, merge_block);

        // Collect case values and create case blocks
        var case_values_buf: [32]i64 = undefined;
        var case_blocks_buf: [32]mlir.Block = undefined;
        var n_cases: usize = 0;
        var default_block: mlir.Block = .{ .ptr = null };

        for (cases) |case_node| {
            const case_tag = tree.nodeTag(case_node);

            // Create a block for this case arm
            const arm_block = self.addBlock();

            switch (case_tag) {
                .switch_case_one, .switch_case_inline_one => {
                    const case_data = tree.nodeData(case_node).opt_node_and_node;
                    const value_opt = case_data[0];
                    const target_expr = case_data[1];

                    if (value_opt.unwrap()) |value_node| {
                        // Non-else case: resolve the value
                        const val_tag = tree.nodeTag(value_node);
                        var case_val: i64 = 0;
                        if (val_tag == .enum_literal) {
                            // .red, .green, etc. — look up variant value
                            const vtok = tree.nodeMainToken(value_node);
                            const vname = tree.tokenSlice(vtok);
                            if (mlir.cirTypeIsEnum(cond_type)) {
                                case_val = mlir.cirEnumTypeGetVariantValue(cond_type, mlir.StringRef.fromSlice(vname));
                            }
                        } else if (val_tag == .number_literal) {
                            const vtok = tree.nodeMainToken(value_node);
                            const vtext = tree.tokenSlice(vtok);
                            case_val = std.fmt.parseInt(i64, vtext, 10) catch 0;
                        }

                        case_values_buf[n_cases] = case_val;
                        case_blocks_buf[n_cases] = arm_block;
                        n_cases += 1;
                    } else {
                        // else case
                        default_block = arm_block;
                    }

                    // Emit the target expression in the arm block, branch to merge
                    const arm_val = self.mapExpr(arm_block, target_expr, result_type);
                    mlir.cirBuildBr(arm_block, self.b.loc, merge_block, 1, &[_]mlir.Value{arm_val});
                },
                .switch_case, .switch_case_inline => {
                    const case_data = tree.nodeData(case_node).extra_and_node;
                    const values_range = tree.extraData(case_data[0], Node.SubRange);
                    const values = tree.extraDataSlice(values_range, Node.Index);
                    const target_expr = case_data[1];

                    // Multi-value case: each value maps to the same block
                    for (values) |value_node| {
                        const val_tag = tree.nodeTag(value_node);
                        var case_val: i64 = 0;
                        if (val_tag == .enum_literal) {
                            const vtok = tree.nodeMainToken(value_node);
                            const vname = tree.tokenSlice(vtok);
                            if (mlir.cirTypeIsEnum(cond_type)) {
                                case_val = mlir.cirEnumTypeGetVariantValue(cond_type, mlir.StringRef.fromSlice(vname));
                            }
                        } else if (val_tag == .number_literal) {
                            const vtok = tree.nodeMainToken(value_node);
                            const vtext = tree.tokenSlice(vtok);
                            case_val = std.fmt.parseInt(i64, vtext, 10) catch 0;
                        }

                        case_values_buf[n_cases] = case_val;
                        case_blocks_buf[n_cases] = arm_block;
                        n_cases += 1;
                    }

                    // Emit the target expression in the arm block, branch to merge
                    const arm_val = self.mapExpr(arm_block, target_expr, result_type);
                    mlir.cirBuildBr(arm_block, self.b.loc, merge_block, 1, &[_]mlir.Value{arm_val});
                },
                else => {},
            }
        }

        // If no default case, create a trap block
        if (default_block.ptr == null) {
            default_block = self.addBlock();
            // Default: use zero as fallback and branch to merge
            const zero = mlir.cirBuildConstantInt(default_block, self.b.loc, result_type, 0);
            mlir.cirBuildBr(default_block, self.b.loc, merge_block, 1, &[_]mlir.Value{zero});
        }

        // Emit cir.switch in the original block
        mlir.cirBuildSwitch(
            block,
            self.b.loc,
            switch_val,
            @intCast(n_cases),
            &case_values_buf,
            &case_blocks_buf,
            default_block,
        );

        // Continue codegen in the merge block
        self.current_block = merge_block;
        return mlir.mlirBlockGetArgument(merge_block, 0);
    }
};
