//===- scanner.h - ac language scanner --------------------------*- C++ -*-===//
#ifndef AC_SCANNER_H
#define AC_SCANNER_H
// Scanner for the ac language.
//
// Architecture: Zig Tokenizer state machine (~/claude/references/zig/lib/std/zig/Tokenizer.zig)
// Semicolons: Go scanner insertSemi pattern (~/claude/references/go/src/go/scanner/scanner.go)
//
// Zig's tokenizer uses an explicit State enum with labeled switch dispatch.
// Each state transitions to another state or produces a token.
// Go's scanner uses a single boolean (insertSemi) to track whether a
// newline should produce a synthetic semicolon token.

#include <string>
#include <string_view>
#include <vector>

namespace ac {

// Token tag — ported from Zig's Token.Tag pattern (exhaustive enum of all tokens).
// ac-specific tokens replace Zig-specific ones (no @builtins, no pipe operators).
enum class Tag {
  // Sentinel
  eof,
  invalid,

  // Literals (variable-length, text in source)
  identifier,
  int_literal,
  float_literal,
  string_literal,
  char_literal,

  // Keywords (ac syntax — LLM-biased toward Rust/Go/Zig/Swift/TS consensus)
  kw_fn,
  kw_return,
  kw_let,
  kw_var,
  kw_if,
  kw_else,
  kw_while,
  kw_for,
  kw_in,
  kw_break,
  kw_continue,
  kw_struct,
  kw_enum,
  kw_union,
  kw_match,
  kw_true,
  kw_false,
  kw_and,
  kw_or,
  kw_not,
  kw_pub,
  kw_import,
  kw_as,
  kw_defer,
  kw_comptime,
  kw_async,
  kw_await,
  kw_try,
  kw_catch,
  kw_throw,
  kw_error,
  kw_null,
  kw_self,
  kw_type,
  kw_test,
  kw_assert,

  // Types (built-in type keywords)
  kw_i8, kw_i16, kw_i32, kw_i64,
  kw_u8, kw_u16, kw_u32, kw_u64,
  kw_f32, kw_f64,
  kw_bool,
  kw_void,
  kw_string,

  // Punctuation (single char)
  l_paren,     // (
  r_paren,     // )
  l_brace,     // {
  r_brace,     // }
  l_bracket,   // [
  r_bracket,   // ]
  comma,       // ,
  colon,       // :
  semicolon,   // ; (synthetic from newline — Go pattern)
  dot,         // .

  // Operators (single char)
  plus,        // +
  minus,       // -
  star,        // *
  slash,       // /
  percent,     // %
  ampersand,   // &
  pipe,        // |
  caret,       // ^
  tilde,       // ~
  bang,        // !
  equal,       // =
  less,        // <
  greater,     // >

  // Operators (multi char)
  arrow,       // ->
  fat_arrow,   // =>
  question,    // ?
  dot_dot,     // ..
  plus_eq,     // +=
  minus_eq,    // -=
  star_eq,     // *=
  slash_eq,    // /=
  percent_eq,  // %=
  amp_eq,      // &=
  pipe_eq,     // |=
  caret_eq,    // ^=
  eq_eq,       // ==
  bang_eq,     // !=
  less_eq,     // <=
  greater_eq,  // >=
  shl,         // <<
  shr,         // >>
  amp_amp,     // &&
  pipe_pipe,   // ||

  // Comments (skipped during scanning, not returned as tokens)
  // Following Zig's pattern: comments don't produce tokens.
};

// Token — ported from Zig's Token struct (tag + location span).
// Text is a view into the source buffer (no copies).
struct Token {
  Tag tag;
  size_t start;  // byte offset into source
  size_t end;    // byte offset (exclusive)
};

// Scanner — Zig's Tokenizer state machine + Go's insertSemi.
//
// Usage:
//   Scanner scanner(source);
//   while (true) {
//     Token tok = scanner.next();
//     if (tok.tag == Tag::eof) break;
//   }
class Scanner {
public:
  explicit Scanner(std::string_view source);

  // Return the next token. Zig pattern: always makes progress, returns eof at end.
  Token next();

  // Get the text of a token (view into source buffer).
  std::string_view text(const Token &tok) const;

private:
  std::string_view source_;
  size_t index_ = 0;

  // Go's insertSemi pattern: track whether a newline should produce a semicolon.
  bool insert_semi_ = false;

  // Check if a token tag triggers semicolon insertion (Go pattern).
  // Go inserts semicolons after: identifiers, literals, keywords that end
  // statements (return, break, continue), and closing delimiters ), ], }.
  static bool triggersSemicolon(Tag tag);
};

// Convenience: scan entire source into token vector.
std::vector<Token> scanAll(std::string_view source);

} // namespace ac

#endif // AC_SCANNER_H
