// Parser for the ac language.
//
// Architecture ported from:
//   Go parser — recursive descent with precedence climbing
//     ~/claude/references/go/src/go/parser/parser.go (2,962 lines)
//   Zig parser — explicit operator precedence table
//     ~/claude/references/zig/lib/std/zig/Parse.zig (3,725 lines)
//
// Go's parser pattern:
//   1. Each grammar rule is a method: parseExpr(), parseStmt(), parseDecl()
//   2. Binary operators use precedence climbing: parseBinaryExpr(x, prec1)
//   3. One-token lookahead via peek()
//   4. Error recovery: advance to sync tokens (}, ;, EOF)
//
// Zig's precedence table pattern:
//   operTable maps token → (precedence, associativity)
//   parseBinaryExpr checks operTable to decide when to recurse

#include "parser.h"
#include "llvm/Support/raw_ostream.h"

namespace ac {

// Zig pattern: operator precedence table.
// Maps token tag → integer precedence (higher = tighter binding).
// 0 = not an operator.
static int precedence(Tag tag) {
  switch (tag) {
    case Tag::pipe_pipe:                             return 10; // ||
    case Tag::amp_amp:                               return 20; // &&
    case Tag::eq_eq: case Tag::bang_eq:              return 30; // == !=
    case Tag::less: case Tag::less_eq:
    case Tag::greater: case Tag::greater_eq:         return 40; // < <= > >=
    case Tag::pipe:                                  return 50; // |
    case Tag::caret:                                 return 60; // ^
    case Tag::ampersand:                             return 70; // &
    case Tag::shl: case Tag::shr:                    return 80; // << >>
    case Tag::plus: case Tag::minus:                 return 90; // + -
    case Tag::star: case Tag::slash: case Tag::percent: return 100; // * / %
    default:                                         return 0;
  }
}

class Parser {
  std::string_view source_;
  const std::vector<Token> &tokens_;
  size_t pos_ = 0;

  const Token &peek() const { return tokens_[pos_]; }
  const Token &advance() { return tokens_[pos_++]; }
  bool check(Tag t) const { return peek().tag == t; }

  bool match(Tag t) {
    if (check(t)) { advance(); return true; }
    return false;
  }

  std::string_view tokenText(const Token &tok) const {
    return source_.substr(tok.start, tok.end - tok.start);
  }

  // Go pattern: expect token or report error.
  const Token &expect(Tag t) {
    if (!check(t)) {
      llvm::errs() << "error: expected token " << static_cast<int>(t)
                    << " got '" << tokenText(peek()) << "'\n";
    }
    return advance();
  }

  // Go pattern: skip semicolons (synthetic newlines).
  void skipSemis() { while (check(Tag::semicolon)) advance(); }

  // ---- Type reference ----
  TypeRef parseType() {
    auto &tok = advance();
    return TypeRef{tokenText(tok)};
  }

  // ---- Expressions: Go's precedence climbing ----
  // Go: parseBinaryExpr(x Expr, prec1 int) Expr
  //   oprec := s.tokPrec(); if oprec < prec1 { return x }
  //   y := parseBinaryExpr(nil, oprec+1)
  //   x = BinaryExpr{x, op, y}

  ExprPtr parsePrimary() {
    auto &tok = peek();

    if (tok.tag == Tag::int_literal) {
      advance();
      auto e = std::make_unique<Expr>();
      e->kind = ExprKind::IntLit;
      e->pos = tok.start;
      // Parse integer (skip underscores)
      std::string clean;
      for (char c : tokenText(tok)) if (c != '_') clean += c;
      e->intVal = std::stoll(clean);
      return e;
    }

    if (tok.tag == Tag::kw_true || tok.tag == Tag::kw_false) {
      advance();
      auto e = std::make_unique<Expr>();
      e->kind = ExprKind::BoolLit;
      e->pos = tok.start;
      e->boolVal = (tok.tag == Tag::kw_true);
      return e;
    }

    if (tok.tag == Tag::identifier) {
      auto name = tokenText(tok);
      size_t p = tok.start;
      advance();

      // Function call: ident '(' args ')'
      if (check(Tag::l_paren)) {
        advance();
        auto e = std::make_unique<Expr>();
        e->kind = ExprKind::Call;
        e->name = name;
        e->pos = p;
        if (!check(Tag::r_paren)) {
          e->args.push_back(parseExpr());
          while (match(Tag::comma))
            e->args.push_back(parseExpr());
        }
        expect(Tag::r_paren);
        return e;
      }

      auto e = std::make_unique<Expr>();
      e->kind = ExprKind::Ident;
      e->name = name;
      e->pos = p;
      return e;
    }

    if (tok.tag == Tag::l_paren) {
      advance();
      auto e = parseExpr();
      expect(Tag::r_paren);
      return e;
    }

    // Unary prefix: - !
    if (tok.tag == Tag::minus || tok.tag == Tag::bang) {
      auto op = advance().tag;
      auto operand = parsePrimary();
      auto e = std::make_unique<Expr>();
      e->kind = ExprKind::UnaryOp;
      e->op = op;
      e->rhs = std::move(operand);
      e->pos = tok.start;
      return e;
    }

    llvm::errs() << "error: unexpected '" << tokenText(tok) << "'\n";
    advance();
    return std::make_unique<Expr>();
  }

  // Go pattern: precedence climbing for binary operators.
  ExprPtr parseBinaryExpr(int minPrec) {
    auto left = parsePrimary();
    while (true) {
      int prec = precedence(peek().tag);
      if (prec == 0 || prec < minPrec) break;
      Tag op = advance().tag;
      // Left-associative: recurse with prec+1 (Go pattern).
      auto right = parseBinaryExpr(prec + 1);
      auto e = std::make_unique<Expr>();
      e->kind = ExprKind::BinOp;
      e->op = op;
      e->lhs = std::move(left);
      e->rhs = std::move(right);
      e->pos = e->lhs->pos;
      left = std::move(e);
    }
    return left;
  }

  ExprPtr parseExpr() { return parseBinaryExpr(1); }

  // ---- Statements ----
  StmtPtr parseStmt() {
    skipSemis();

    if (check(Tag::kw_return)) {
      size_t p = advance().start;
      auto s = std::make_unique<Stmt>();
      s->kind = StmtKind::Return;
      s->pos = p;
      if (!check(Tag::semicolon) && !check(Tag::r_brace) && !check(Tag::eof))
        s->expr = parseExpr();
      match(Tag::semicolon);
      return s;
    }

    // If statement: if cond { } else { }
    if (check(Tag::kw_if)) {
      size_t p = advance().start;
      auto s = std::make_unique<Stmt>();
      s->kind = StmtKind::If;
      s->pos = p;
      s->expr = parseExpr();  // condition (no parens — Go/Rust pattern)
      expect(Tag::l_brace);
      skipSemis();
      while (!check(Tag::r_brace) && !check(Tag::eof)) {
        s->thenBody.push_back(parseStmt());
        skipSemis();
      }
      expect(Tag::r_brace);
      if (match(Tag::kw_else)) {
        expect(Tag::l_brace);
        skipSemis();
        while (!check(Tag::r_brace) && !check(Tag::eof)) {
          s->elseBody.push_back(parseStmt());
          skipSemis();
        }
        expect(Tag::r_brace);
      }
      match(Tag::semicolon);
      return s;
    }

    // Assert statement: assert(expr)
    if (check(Tag::kw_assert)) {
      size_t p = advance().start;
      auto s = std::make_unique<Stmt>();
      s->kind = StmtKind::Assert;
      s->pos = p;
      expect(Tag::l_paren);
      s->expr = parseExpr();
      expect(Tag::r_paren);
      match(Tag::semicolon);
      return s;
    }

    // Expression statement
    auto s = std::make_unique<Stmt>();
    s->kind = StmtKind::ExprStmt;
    s->pos = peek().start;
    s->expr = parseExpr();
    match(Tag::semicolon);
    return s;
  }

  // ---- Function declaration ----
  FnDecl parseFnDecl() {
    expect(Tag::kw_fn);
    FnDecl fn;
    fn.pos = peek().start;
    fn.name = tokenText(expect(Tag::identifier));

    expect(Tag::l_paren);
    if (!check(Tag::r_paren)) {
      Param p;
      p.name = tokenText(expect(Tag::identifier));
      expect(Tag::colon);
      p.type = parseType();
      fn.params.push_back(p);
      while (match(Tag::comma)) {
        Param p2;
        p2.name = tokenText(expect(Tag::identifier));
        expect(Tag::colon);
        p2.type = parseType();
        fn.params.push_back(p2);
      }
    }
    expect(Tag::r_paren);

    if (match(Tag::arrow)) {
      fn.returnType = parseType();
    } else {
      fn.returnType = TypeRef{"void"};
    }

    expect(Tag::l_brace);
    skipSemis();
    while (!check(Tag::r_brace) && !check(Tag::eof)) {
      fn.body.push_back(parseStmt());
      skipSemis();
    }
    expect(Tag::r_brace);
    match(Tag::semicolon);

    return fn;
  }

  // ---- Test declaration (Zig pattern: test "name" { body }) ----
  TestDecl parseTestDecl() {
    expect(Tag::kw_test);
    TestDecl td;
    td.pos = peek().start;

    // Test name is a string literal
    if (check(Tag::string_literal)) {
      auto &tok = advance();
      // Strip quotes from string literal
      auto text = tokenText(tok);
      td.name = text.substr(1, text.size() - 2);
    } else {
      td.name = "anonymous";
    }

    expect(Tag::l_brace);
    skipSemis();
    while (!check(Tag::r_brace) && !check(Tag::eof)) {
      td.body.push_back(parseStmt());
      skipSemis();
    }
    expect(Tag::r_brace);
    match(Tag::semicolon);
    return td;
  }

public:
  Parser(std::string_view source, const std::vector<Token> &tokens)
      : source_(source), tokens_(tokens) {}

  Module parseModule() {
    Module mod;
    skipSemis();
    while (!check(Tag::eof)) {
      if (check(Tag::kw_fn)) {
        mod.functions.push_back(parseFnDecl());
      } else if (check(Tag::kw_test)) {
        mod.tests.push_back(parseTestDecl());
      } else {
        llvm::errs() << "error: unexpected '" << tokenText(peek()) << "' at top level\n";
        advance();
      }
      skipSemis();
    }
    return mod;
  }
};

Module parse(std::string_view source, const std::vector<Token> &tokens) {
  Parser p(source, tokens);
  return p.parseModule();
}

} // namespace ac
