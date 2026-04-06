// Scanner for the ac language.
//
// Architecture ported from:
//   Zig Tokenizer — state machine with labeled switch dispatch
//     ~/claude/references/zig/lib/std/zig/Tokenizer.zig (1,778 lines)
//   Go scanner — insertSemi boolean for automatic semicolon insertion
//     ~/claude/references/go/src/go/scanner/scanner.go (1,000 lines)
//
// The Zig tokenizer works like this:
//   1. Start in State::start
//   2. Look at current char, switch to a new state or produce a token
//   3. Each state consumes chars until it can produce a token
//   4. Return token with (tag, start, end) — text is a span into source
//
// Go's semicolon insertion works like this:
//   1. After producing a token, check if it triggers semicolon insertion
//   2. If so, set insertSemi = true
//   3. On next newline or EOF, if insertSemi is true, return synthetic semicolon
//   4. In skipWhitespace, stop at newlines when insertSemi is true

#include "scanner.h"
#include <unordered_map>

namespace ac {

// Keyword lookup — Zig pattern: static map from string to tag.
// Zig uses StaticStringMap; we use unordered_map (could optimize to perfect hash later).
static const std::unordered_map<std::string_view, Tag> keywords = {
    {"fn", Tag::kw_fn},           {"return", Tag::kw_return},
    {"let", Tag::kw_let},         {"var", Tag::kw_var},
    {"if", Tag::kw_if},           {"else", Tag::kw_else},
    {"while", Tag::kw_while},     {"for", Tag::kw_for},
    {"in", Tag::kw_in},           {"break", Tag::kw_break},
    {"continue", Tag::kw_continue}, {"struct", Tag::kw_struct},
    {"enum", Tag::kw_enum},       {"union", Tag::kw_union},
    {"match", Tag::kw_match},     {"true", Tag::kw_true},
    {"false", Tag::kw_false},     {"and", Tag::kw_and},
    {"or", Tag::kw_or},           {"not", Tag::kw_not},
    {"pub", Tag::kw_pub},         {"import", Tag::kw_import},
    {"as", Tag::kw_as},           {"defer", Tag::kw_defer},
    {"comptime", Tag::kw_comptime}, {"async", Tag::kw_async},
    {"await", Tag::kw_await},     {"try", Tag::kw_try},
    {"catch", Tag::kw_catch},     {"throw", Tag::kw_throw},
    {"error", Tag::kw_error},
    {"null", Tag::kw_null},
    {"self", Tag::kw_self},       {"type", Tag::kw_type},
    {"test", Tag::kw_test},       {"assert", Tag::kw_assert},
    {"trait", Tag::kw_trait},     {"impl", Tag::kw_impl},
    // Type keywords
    {"i8", Tag::kw_i8},     {"i16", Tag::kw_i16},
    {"i32", Tag::kw_i32},   {"i64", Tag::kw_i64},
    {"u8", Tag::kw_u8},     {"u16", Tag::kw_u16},
    {"u32", Tag::kw_u32},   {"u64", Tag::kw_u64},
    {"f32", Tag::kw_f32},   {"f64", Tag::kw_f64},
    {"bool", Tag::kw_bool}, {"void", Tag::kw_void},
    {"string", Tag::kw_string},
};

Scanner::Scanner(std::string_view source) : source_(source) {}

std::string_view Scanner::text(const Token &tok) const {
  return source_.substr(tok.start, tok.end - tok.start);
}

// Go pattern: these tokens trigger semicolon insertion before the next newline.
// From Go spec: "a semicolon is automatically inserted into the token stream
// immediately after a line's final token if that token is:
//   - an identifier, literal, or one of: break continue return ++ -- ) ] }"
// Adapted for ac: identifiers, all literals, type keywords, true/false/null,
// return/break/continue, closing delimiters.
bool Scanner::triggersSemicolon(Tag tag) {
  switch (tag) {
    case Tag::identifier:
    case Tag::int_literal:
    case Tag::float_literal:
    case Tag::string_literal:
    case Tag::char_literal:
    case Tag::kw_return:
    case Tag::kw_break:
    case Tag::kw_continue:
    case Tag::kw_true:
    case Tag::kw_false:
    case Tag::kw_null:
    case Tag::kw_self:
    // Type keywords end expressions (e.g., "-> i32\n")
    case Tag::kw_i8: case Tag::kw_i16: case Tag::kw_i32: case Tag::kw_i64:
    case Tag::kw_u8: case Tag::kw_u16: case Tag::kw_u32: case Tag::kw_u64:
    case Tag::kw_f32: case Tag::kw_f64:
    case Tag::kw_bool: case Tag::kw_void: case Tag::kw_string:
    // Closing delimiters
    case Tag::r_paren:
    case Tag::r_brace:
    case Tag::r_bracket:
      return true;
    default:
      return false;
  }
}

// Main scanning function — Zig's state machine pattern.
// Each iteration: look at current char, decide what token to produce.
// Go's semicolon logic wraps the outside.
Token Scanner::next() {
  // Zig pattern: skip whitespace, but Go pattern: stop at newlines when insertSemi.
  while (index_ < source_.size()) {
    char c = source_[index_];
    if (c == ' ' || c == '\t' || c == '\r') {
      index_++;
      continue;
    }
    if (c == '\n') {
      index_++;
      // Go pattern: newline produces semicolon if insertSemi is set.
      if (insert_semi_) {
        insert_semi_ = false;
        return Token{Tag::semicolon, index_ - 1, index_};
      }
      continue;
    }
    break;
  }

  // EOF
  if (index_ >= source_.size()) {
    // Go pattern: EOF also produces semicolon if insertSemi.
    if (insert_semi_) {
      insert_semi_ = false;
      return Token{Tag::semicolon, index_, index_};
    }
    return Token{Tag::eof, index_, index_};
  }

  size_t start = index_;
  char c = source_[index_];
  Tag tag = Tag::invalid;

  // Zig pattern: switch on first character to enter scanning state.
  // Simple cases produce tokens immediately. Complex cases enter a state loop.

  // --- Line comments (Zig: slash → line_comment_start → line_comment) ---
  if (c == '/' && index_ + 1 < source_.size() && source_[index_ + 1] == '/') {
    index_ += 2;
    while (index_ < source_.size() && source_[index_] != '\n') index_++;
    // Comments don't produce tokens (Zig pattern). Recurse to get next real token.
    return next();
  }

  // --- Identifiers and keywords (Zig: 'a'...'z','A'...'Z','_' → identifier) ---
  if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_') {
    index_++;
    while (index_ < source_.size()) {
      char ch = source_[index_];
      if ((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') ||
          (ch >= '0' && ch <= '9') || ch == '_') {
        index_++;
      } else {
        break;
      }
    }
    std::string_view word = source_.substr(start, index_ - start);
    auto it = keywords.find(word);
    tag = (it != keywords.end()) ? it->second : Tag::identifier;
    insert_semi_ = triggersSemicolon(tag);
    return Token{tag, start, index_};
  }

  // --- Numbers (Zig: '0'...'9' → int state, may transition to float) ---
  if (c >= '0' && c <= '9') {
    index_++;
    while (index_ < source_.size() && (source_[index_] >= '0' && source_[index_] <= '9' || source_[index_] == '_'))
      index_++;
    tag = Tag::int_literal;
    // Zig pattern: check for period followed by digit → float
    if (index_ < source_.size() && source_[index_] == '.' &&
        index_ + 1 < source_.size() && source_[index_ + 1] >= '0' && source_[index_ + 1] <= '9') {
      index_++; // consume '.'
      while (index_ < source_.size() && (source_[index_] >= '0' && source_[index_] <= '9' || source_[index_] == '_'))
        index_++;
      tag = Tag::float_literal;
    }
    insert_semi_ = true;
    return Token{tag, start, index_};
  }

  // --- String literals (Zig: '"' → string_literal state) ---
  if (c == '"') {
    index_++; // skip opening quote
    while (index_ < source_.size() && source_[index_] != '"') {
      if (source_[index_] == '\\' && index_ + 1 < source_.size())
        index_++; // skip escaped char
      index_++;
    }
    if (index_ < source_.size()) index_++; // skip closing quote
    insert_semi_ = true;
    return Token{Tag::string_literal, start, index_};
  }

  // --- Char literals ---
  if (c == '\'') {
    index_++;
    if (index_ < source_.size() && source_[index_] == '\\' && index_ + 1 < source_.size())
      index_++;
    if (index_ < source_.size()) index_++;
    if (index_ < source_.size() && source_[index_] == '\'') index_++;
    insert_semi_ = true;
    return Token{Tag::char_literal, start, index_};
  }

  // --- Multi-character operators (Zig: enter state, check next char) ---
  index_++;
  switch (c) {
    // Two-char operators: check next char
    case '-':
      if (index_ < source_.size() && source_[index_] == '>') { index_++; tag = Tag::arrow; }
      else if (index_ < source_.size() && source_[index_] == '=') { index_++; tag = Tag::minus_eq; }
      else tag = Tag::minus;
      break;
    case '=':
      if (index_ < source_.size() && source_[index_] == '=') { index_++; tag = Tag::eq_eq; }
      else if (index_ < source_.size() && source_[index_] == '>') { index_++; tag = Tag::fat_arrow; }
      else tag = Tag::equal;
      break;
    case '!':
      if (index_ < source_.size() && source_[index_] == '=') { index_++; tag = Tag::bang_eq; }
      else tag = Tag::bang;
      break;
    case '<':
      if (index_ < source_.size() && source_[index_] == '=') { index_++; tag = Tag::less_eq; }
      else if (index_ < source_.size() && source_[index_] == '<') { index_++; tag = Tag::shl; }
      else tag = Tag::less;
      break;
    case '>':
      if (index_ < source_.size() && source_[index_] == '=') { index_++; tag = Tag::greater_eq; }
      else if (index_ < source_.size() && source_[index_] == '>') { index_++; tag = Tag::shr; }
      else tag = Tag::greater;
      break;
    case '&':
      if (index_ < source_.size() && source_[index_] == '&') { index_++; tag = Tag::amp_amp; }
      else if (index_ < source_.size() && source_[index_] == '=') { index_++; tag = Tag::amp_eq; }
      else tag = Tag::ampersand;
      break;
    case '|':
      if (index_ < source_.size() && source_[index_] == '|') { index_++; tag = Tag::pipe_pipe; }
      else if (index_ < source_.size() && source_[index_] == '=') { index_++; tag = Tag::pipe_eq; }
      else tag = Tag::pipe;
      break;
    case '+':
      if (index_ < source_.size() && source_[index_] == '=') { index_++; tag = Tag::plus_eq; }
      else tag = Tag::plus;
      break;
    case '*':
      if (index_ < source_.size() && source_[index_] == '=') { index_++; tag = Tag::star_eq; }
      else tag = Tag::star;
      break;
    case '/':
      if (index_ < source_.size() && source_[index_] == '=') { index_++; tag = Tag::slash_eq; }
      else tag = Tag::slash;
      break;
    case '%':
      if (index_ < source_.size() && source_[index_] == '=') { index_++; tag = Tag::percent_eq; }
      else tag = Tag::percent;
      break;
    case '^':
      if (index_ < source_.size() && source_[index_] == '=') { index_++; tag = Tag::caret_eq; }
      else tag = Tag::caret;
      break;
    case '.':
      if (index_ < source_.size() && source_[index_] == '.') { index_++; tag = Tag::dot_dot; }
      else tag = Tag::dot;
      break;

    // Single-char tokens
    case '(': tag = Tag::l_paren; break;
    case ')': tag = Tag::r_paren; break;
    case '{': tag = Tag::l_brace; break;
    case '}': tag = Tag::r_brace; break;
    case '[': tag = Tag::l_bracket; break;
    case ']': tag = Tag::r_bracket; break;
    case ',': tag = Tag::comma; break;
    case ':': tag = Tag::colon; break;
    case ';': tag = Tag::semicolon; break;
    case '~': tag = Tag::tilde; break;
    case '?': tag = Tag::question; break;

    default: tag = Tag::invalid; break;
  }

  // Go pattern: set insertSemi based on produced token.
  insert_semi_ = triggersSemicolon(tag);
  return Token{tag, start, index_};
}

// Convenience: scan everything.
std::vector<Token> scanAll(std::string_view source) {
  Scanner scanner(source);
  std::vector<Token> tokens;
  while (true) {
    Token tok = scanner.next();
    tokens.push_back(tok);
    if (tok.tag == Tag::eof) break;
  }
  return tokens;
}

} // namespace ac
