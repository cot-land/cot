//! textDocument/completion — autocomplete suggestions.

const std = @import("std");
const analysis = @import("analysis.zig");
const checker_mod = @import("../frontend/checker.zig");

const AnalysisResult = analysis.AnalysisResult;

/// LSP CompletionItemKind values.
const CompletionItemKind = struct {
    const function = 3;
    const variable = 6;
    const class = 7;
    const constant = 21; // LSP spec: Constant = 21
    const keyword = 14;
    const type_param = 25; // LSP spec: TypeParameter = 25
};

pub const CompletionItem = struct {
    label: []const u8,
    kind: u32,
    detail: ?[]const u8 = null,
};

/// Builtin names for @ completions (sorted for display).
const builtin_names = [_][]const u8{
    "abs",           "alignOf",       "alloc",         "arg_len",
    "arg_ptr",       "args_count",    "assert",        "assert_eq",
    "ceil",          "compileError",  "dealloc",       "environ_count",
    "environ_len",   "environ_ptr",   "exit",          "fmax",
    "fmin",          "fd_close",      "fd_open",       "fd_read",
    "fd_seek",       "fd_write",      "floor",         "intCast",
    "intToPtr",      "lenOf",         "memcpy",        "ptrCast",
    "ptrOf",         "ptrToInt",      "random",        "realloc",
    "round",         "sizeOf",        "sqrt",          "string",
    "target",        "target_arch",   "target_os",     "time",
    "trap",          "trunc",
};

/// Cot keywords for statement-position completions.
const keyword_names = [_][]const u8{
    "break",    "comptime",  "const",    "continue", "defer",
    "else",     "enum",      "errdefer", "error",    "extern",
    "false",    "fn",        "for",      "if",       "impl",
    "import",   "in",        "let",      "new",      "not",
    "null",     "or",        "and",      "return",   "struct",
    "switch",   "test",      "trait",    "true",     "try",
    "type",     "undefined", "union",    "var",      "void",
    "where",    "while",
};

/// Get completion items for the given byte offset.
pub fn getCompletions(allocator: std.mem.Allocator, result: *AnalysisResult, byte_offset: u32) ![]CompletionItem {
    var items = std.ArrayListUnmanaged(CompletionItem){};

    // Determine trigger context: is the char before the cursor '@'?
    const is_at_trigger = byte_offset > 0 and byte_offset <= result.src.content.len and result.src.content[byte_offset - 1] == '@';

    if (is_at_trigger) {
        // @ trigger: show builtins
        for (&builtin_names) |name| {
            try items.append(allocator, .{
                .label = name,
                .kind = CompletionItemKind.function,
                .detail = "builtin",
            });
        }
    } else {
        // General completion: scope symbols + keywords
        // Scope symbols
        var scope_iter = result.global_scope.symbols.iterator();
        while (scope_iter.next()) |entry| {
            const sym = entry.value_ptr.*;
            const kind: u32 = switch (sym.kind) {
                .function => CompletionItemKind.function,
                .type_name => CompletionItemKind.class,
                .constant => CompletionItemKind.constant,
                .variable, .parameter => CompletionItemKind.variable,
            };
            try items.append(allocator, .{
                .label = entry.key_ptr.*,
                .kind = kind,
            });
        }

        // Keywords
        for (&keyword_names) |name| {
            try items.append(allocator, .{
                .label = name,
                .kind = CompletionItemKind.keyword,
                .detail = "keyword",
            });
        }
    }

    return items.toOwnedSlice(allocator);
}
