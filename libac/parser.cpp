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

  // Lookahead: is this '{' the start of a struct init (Name { field: val })?
  // Returns true if tokens after '{' match: [semis] identifier ':'.
  bool isStructInitLookahead() {
    size_t saved = pos_;
    // pos_ is on '{', look past it
    size_t look = pos_ + 1;
    // Skip semicolons (synthetic newlines)
    while (look < tokens_.size() && tokens_[look].tag == Tag::semicolon)
      look++;
    // Must see identifier followed by ':'
    bool result = look + 1 < tokens_.size() &&
        tokens_[look].tag == Tag::identifier &&
        tokens_[look + 1].tag == Tag::colon;
    return result;
  }

  // ---- Type reference ----
  TypeRef parseType() {
    // Array type [N]T or slice type []T
    if (check(Tag::l_bracket)) {
      advance(); // consume '['
      // Slice type: []T (no size)
      if (check(Tag::r_bracket)) {
        advance(); // consume ']'
        auto elemType = tokenText(advance());
        TypeRef t;
        t.arrayElemType = elemType;
        t.isSlice = true;
        return t;
      }
      // Array type: [N]T
      auto sizeText = tokenText(expect(Tag::int_literal));
      int64_t size = std::stoll(std::string(sizeText));
      expect(Tag::r_bracket);
      auto elemType = tokenText(advance());
      return TypeRef{"", size, elemType};
    }
    // Optional type: ?T
    if (check(Tag::question)) {
      advance(); // consume '?'
      auto inner = tokenText(advance());
      TypeRef t;
      t.name = inner;
      t.isOptional = true;
      return t;
    }
    // Error union type: !T
    if (check(Tag::bang)) {
      advance(); // consume '!'
      auto inner = tokenText(advance());
      TypeRef t;
      t.name = inner;
      t.isErrorUnion = true;
      return t;
    }
    // Pointer/ref type: *T
    if (check(Tag::star)) {
      advance(); // consume '*'
      auto pointee = tokenText(advance());
      TypeRef t;
      t.name = pointee;
      t.isRef = true;
      return t;
    }
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

    if (tok.tag == Tag::string_literal) {
      advance();
      auto e = std::make_unique<Expr>();
      e->kind = ExprKind::StringLit;
      e->pos = tok.start;
      // Extract string contents (strip quotes, process escapes)
      auto text = tokenText(tok);
      // Remove surrounding quotes
      if (text.size() >= 2 && text.front() == '"' && text.back() == '"')
        text = text.substr(1, text.size() - 2);
      // Process escape sequences
      std::string result;
      for (size_t i = 0; i < text.size(); i++) {
        if (text[i] == '\\' && i + 1 < text.size()) {
          switch (text[i + 1]) {
            case 'n': result += '\n'; break;
            case 't': result += '\t'; break;
            case 'r': result += '\r'; break;
            case '\\': result += '\\'; break;
            case '"': result += '"'; break;
            case '0': result += '\0'; break;
            default: result += text[i + 1]; break;
          }
          i++;
        } else {
          result += text[i];
        }
      }
      e->strVal = std::move(result);
      return e;
    }

    if (tok.tag == Tag::kw_null) {
      advance();
      auto e = std::make_unique<Expr>();
      e->kind = ExprKind::NullLit;
      e->pos = tok.start;
      return e;
    }

    // error(N) literal — construct error value
    if (tok.tag == Tag::kw_error) {
      advance();
      auto e = std::make_unique<Expr>();
      e->kind = ExprKind::ErrorLit;
      e->pos = tok.start;
      expect(Tag::l_paren);
      e->intVal = std::stoll(std::string(tokenText(expect(Tag::int_literal))));
      expect(Tag::r_paren);
      return e;
    }

    // try expr — unwrap error union or propagate error
    if (tok.tag == Tag::kw_try) {
      advance();
      auto e = std::make_unique<Expr>();
      e->kind = ExprKind::TryExpr;
      e->pos = tok.start;
      e->lhs = parsePrimary(); // parse the error-union-producing expression
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

      // Struct init: Name { field: expr, ... }
      // Disambiguate from blocks: require ident ':' pattern inside braces.
      // Look ahead: '{' [semi*] identifier ':' means struct init.
      if (check(Tag::l_brace) && isStructInitLookahead()) {
        advance(); // consume '{'
        skipSemis();
        auto e = std::make_unique<Expr>();
        e->kind = ExprKind::StructInit;
        e->name = name; // struct type name
        e->pos = p;
        while (!check(Tag::r_brace) && !check(Tag::eof)) {
          auto fieldName = tokenText(expect(Tag::identifier));
          expect(Tag::colon);
          e->fieldNames.push_back(fieldName);
          e->args.push_back(parseExpr());
          match(Tag::comma);
          skipSemis();
        }
        expect(Tag::r_brace);
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

    // If expression: if cond { expr } else { expr }
    if (tok.tag == Tag::kw_if) {
      size_t p = advance().start;
      auto cond = parseBinaryExpr(1); // condition (not full parseExpr to avoid consuming {)
      expect(Tag::l_brace);
      skipSemis();
      auto thenVal = parseExpr();
      skipSemis();
      expect(Tag::r_brace);
      expect(Tag::kw_else);
      expect(Tag::l_brace);
      skipSemis();
      auto elseVal = parseExpr();
      skipSemis();
      expect(Tag::r_brace);
      auto e = std::make_unique<Expr>();
      e->kind = ExprKind::IfExpr;
      e->pos = p;
      e->args.push_back(std::move(cond));
      e->args.push_back(std::move(thenVal));
      e->args.push_back(std::move(elseVal));
      return e;
    }

    // Array literal: [expr, expr, ...]
    if (tok.tag == Tag::l_bracket) {
      size_t p = advance().start; // consume '['
      auto e = std::make_unique<Expr>();
      e->kind = ExprKind::ArrayLit;
      e->pos = p;
      if (!check(Tag::r_bracket)) {
        e->args.push_back(parseExpr());
        while (match(Tag::comma))
          e->args.push_back(parseExpr());
      }
      expect(Tag::r_bracket);
      return e;
    }

    // Unary prefix: - !
    if (tok.tag == Tag::minus || tok.tag == Tag::bang || tok.tag == Tag::tilde ||
        tok.tag == Tag::ampersand || tok.tag == Tag::star) {
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

  // Parse postfix operations: 'as' cast and '.' field access.
  ExprPtr parsePostfix() {
    auto expr = parsePrimary();
    while (true) {
      if (check(Tag::kw_as)) {
        size_t p = advance().start; // consume 'as'
        auto type = parseType();
        auto cast = std::make_unique<Expr>();
        cast->kind = ExprKind::Cast;
        cast->pos = p;
        cast->lhs = std::move(expr);
        cast->targetType = type;
        expr = std::move(cast);
      } else if (check(Tag::dot)) {
        size_t p = advance().start; // consume '.'
        auto fieldName = tokenText(expect(Tag::identifier));
        // Method call: expr.name(args) → desugar to call with expr as first arg
        if (check(Tag::l_paren)) {
          advance(); // consume '('
          auto mc = std::make_unique<Expr>();
          mc->kind = ExprKind::MethodCall;
          mc->pos = p;
          mc->lhs = std::move(expr);
          mc->name = fieldName;
          if (!check(Tag::r_paren)) {
            mc->args.push_back(parseExpr());
            while (match(Tag::comma))
              mc->args.push_back(parseExpr());
          }
          expect(Tag::r_paren);
          expr = std::move(mc);
        } else {
          // Field access: expr.name
          auto fa = std::make_unique<Expr>();
          fa->kind = ExprKind::FieldAccess;
          fa->pos = p;
          fa->lhs = std::move(expr);
          fa->name = fieldName;
          expr = std::move(fa);
        }
      } else if (check(Tag::l_bracket)) {
        // Array/slice indexing: expr[index] or expr[lo..hi]
        size_t p = advance().start; // consume '['
        auto first = parseExpr();
        if (match(Tag::dot_dot)) {
          // Range/slice: expr[lo..hi] → SliceExpr
          auto hi = parseExpr();
          expect(Tag::r_bracket);
          auto se = std::make_unique<Expr>();
          se->kind = ExprKind::SliceExpr;
          se->pos = p;
          se->lhs = std::move(expr);    // array
          se->rhs = std::move(first);   // lo (reuse rhs for first index)
          se->args.push_back(std::move(hi)); // hi
          expr = std::move(se);
        } else {
          // Normal index: expr[index]
          expect(Tag::r_bracket);
          auto ia = std::make_unique<Expr>();
          ia->kind = ExprKind::IndexAccess;
          ia->pos = p;
          ia->lhs = std::move(expr);
          ia->rhs = std::move(first);
          expr = std::move(ia);
        }
      } else if (check(Tag::kw_catch)) {
        // catch: expr catch |e| { handler }
        size_t p = advance().start; // consume 'catch'
        auto ce = std::make_unique<Expr>();
        ce->kind = ExprKind::CatchExpr;
        ce->pos = p;
        ce->lhs = std::move(expr);
        // Parse capture: |e|
        expect(Tag::pipe);
        ce->name = tokenText(expect(Tag::identifier));
        expect(Tag::pipe);
        // Parse handler block { ... } as a single expression
        // For now, parse as: catch |e| { returnExpr }
        expect(Tag::l_brace);
        skipSemis();
        ce->rhs = parseExpr();
        skipSemis();
        expect(Tag::r_brace);
        expr = std::move(ce);
      } else {
        break;
      }
    }
    return expr;
  }

  // Go pattern: precedence climbing for binary operators.
  ExprPtr parseBinaryExpr(int minPrec) {
    auto left = parsePostfix();
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

    // Throw statement: throw expr
    if (check(Tag::kw_throw)) {
      size_t p = advance().start;
      auto s = std::make_unique<Stmt>();
      s->kind = StmtKind::Throw;
      s->pos = p;
      s->expr = parseExpr();
      match(Tag::semicolon);
      return s;
    }

    // Try/catch statement (exception-style): try { body } catch |e| { handler }
    // Distinct from error-union try (which is an expression: try expr)
    if (check(Tag::kw_try) && pos_ + 1 < tokens_.size() &&
        tokens_[pos_ + 1].tag == Tag::l_brace) {
      size_t p = advance().start; // consume 'try'
      auto s = std::make_unique<Stmt>();
      s->kind = StmtKind::TryCatch;
      s->pos = p;
      // Parse try body
      expect(Tag::l_brace);
      skipSemis();
      while (!check(Tag::r_brace) && !check(Tag::eof)) {
        s->thenBody.push_back(parseStmt());
        skipSemis();
      }
      expect(Tag::r_brace);
      // Parse catch clause
      expect(Tag::kw_catch);
      expect(Tag::pipe);
      s->varName = tokenText(expect(Tag::identifier));
      expect(Tag::pipe);
      expect(Tag::l_brace);
      skipSemis();
      while (!check(Tag::r_brace) && !check(Tag::eof)) {
        s->elseBody.push_back(parseStmt());
        skipSemis();
      }
      expect(Tag::r_brace);
      match(Tag::semicolon);
      return s;
    }

    // Match statement: match expr { pattern => stmt, ... }
    if (check(Tag::kw_match)) {
      size_t p = advance().start; // consume 'match'
      auto s = std::make_unique<Stmt>();
      s->kind = StmtKind::Match;
      s->pos = p;
      s->expr = parseExpr(); // the value being matched
      expect(Tag::l_brace);
      skipSemis();
      while (!check(Tag::r_brace) && !check(Tag::eof)) {
        MatchArm arm;
        arm.pattern = parseExpr(); // parse the pattern value (Color.Red, 0, etc.)
        expect(Tag::fat_arrow);
        // Parse arm body — single statement or block
        arm.body.push_back(parseStmt());
        s->matchArms.push_back(std::move(arm));
        skipSemis();
      }
      expect(Tag::r_brace);
      match(Tag::semicolon);
      return s;
    }

    // If statement: if cond { } else { }
    if (check(Tag::kw_if)) {
      size_t p = advance().start;
      auto s = std::make_unique<Stmt>();
      s->pos = p;
      // Detect if-unwrap: if <ident> |<ident>| { — lookahead for pipe after primary
      // Check: next is identifier, then next+1 is pipe
      if (check(Tag::identifier) && pos_ + 1 < tokens_.size() &&
          tokens_[pos_ + 1].tag == Tag::pipe) {
        // if-unwrap: if optVar |captureVar| { ... }
        s->kind = StmtKind::IfUnwrap;
        s->expr = parsePrimary();  // parse just the optional variable (no binary ops)
        expect(Tag::pipe);         // consume '|'
        s->varName = tokenText(expect(Tag::identifier));
        expect(Tag::pipe);         // consume '|'
      } else {
        s->kind = StmtKind::If;
        s->expr = parseExpr();     // regular condition
      }
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

    // For loop: for i in start..end { body }
    if (check(Tag::kw_for)) {
      size_t p = advance().start;
      auto s = std::make_unique<Stmt>();
      s->kind = StmtKind::For;
      s->pos = p;
      s->varName = tokenText(expect(Tag::identifier));
      expect(Tag::kw_in);
      s->expr = parseExpr();     // start
      expect(Tag::dot_dot);
      s->rangeEnd = parseExpr(); // end
      expect(Tag::l_brace);
      skipSemis();
      while (!check(Tag::r_brace) && !check(Tag::eof)) {
        s->thenBody.push_back(parseStmt());
        skipSemis();
      }
      expect(Tag::r_brace);
      match(Tag::semicolon);
      return s;
    }

    // While loop: while cond { body }
    if (check(Tag::kw_while)) {
      size_t p = advance().start;
      auto s = std::make_unique<Stmt>();
      s->kind = StmtKind::While;
      s->pos = p;
      s->expr = parseExpr(); // condition
      expect(Tag::l_brace);
      skipSemis();
      while (!check(Tag::r_brace) && !check(Tag::eof)) {
        s->thenBody.push_back(parseStmt());
        skipSemis();
      }
      expect(Tag::r_brace);
      match(Tag::semicolon);
      return s;
    }

    // Break
    if (check(Tag::kw_break)) {
      size_t p = advance().start;
      auto s = std::make_unique<Stmt>();
      s->kind = StmtKind::Break;
      s->pos = p;
      match(Tag::semicolon);
      return s;
    }

    // Continue
    if (check(Tag::kw_continue)) {
      size_t p = advance().start;
      auto s = std::make_unique<Stmt>();
      s->kind = StmtKind::Continue;
      s->pos = p;
      match(Tag::semicolon);
      return s;
    }

    // Let binding: let x: i32 = expr
    if (check(Tag::kw_let)) {
      size_t p = advance().start;
      auto s = std::make_unique<Stmt>();
      s->kind = StmtKind::Let;
      s->pos = p;
      s->varName = tokenText(expect(Tag::identifier));
      expect(Tag::colon);
      s->varType = parseType();
      expect(Tag::equal);
      s->expr = parseExpr();
      match(Tag::semicolon);
      return s;
    }

    // Var binding: var x: i32 = expr
    if (check(Tag::kw_var)) {
      size_t p = advance().start;
      auto s = std::make_unique<Stmt>();
      s->kind = StmtKind::Var;
      s->pos = p;
      s->varName = tokenText(expect(Tag::identifier));
      expect(Tag::colon);
      s->varType = parseType();
      expect(Tag::equal);
      s->expr = parseExpr();
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

    // Assignment / compound assignment: ident = expr, ident += expr, etc.
    // Also field assignment: ident.field = expr
    // Also index assignment: ident[index] = expr
    if (check(Tag::identifier) && pos_ + 1 < tokens_.size()) {
      auto nextTag = tokens_[pos_ + 1].tag;

      // Field assignment: p.x = expr (ident.ident = expr)
      if (nextTag == Tag::dot && pos_ + 3 < tokens_.size() &&
          tokens_[pos_ + 2].tag == Tag::identifier &&
          tokens_[pos_ + 3].tag == Tag::equal) {
        size_t p = peek().start;
        auto objName = tokenText(advance()); // consume ident
        advance(); // consume '.'
        auto fieldName = tokenText(advance()); // consume field
        advance(); // consume '='
        auto s = std::make_unique<Stmt>();
        s->kind = StmtKind::Assign;
        s->pos = p;
        s->varName = objName;
        // Store field name in the expr's name field (reuse Expr for field info)
        auto fieldExpr = std::make_unique<Expr>();
        fieldExpr->kind = ExprKind::FieldAccess;
        fieldExpr->name = fieldName;
        fieldExpr->lhs = std::make_unique<Expr>();
        fieldExpr->lhs->kind = ExprKind::Ident;
        fieldExpr->lhs->name = objName;
        fieldExpr->pos = p;
        s->expr = parseExpr();
        // Pack field info into rangeEnd for codegen to detect
        s->rangeEnd = std::move(fieldExpr);
        match(Tag::semicolon);
        return s;
      }

      // Index assignment: arr[i] = expr (ident[expr] = expr)
      if (nextTag == Tag::l_bracket) {
        // Save position, try to parse as index assignment
        size_t saved = pos_;
        size_t p = peek().start;
        auto name = tokenText(advance()); // consume ident
        advance(); // consume '['
        auto indexExpr = parseExpr();
        if (check(Tag::r_bracket) && pos_ + 1 < tokens_.size() &&
            tokens_[pos_ + 1].tag == Tag::equal) {
          advance(); // consume ']'
          advance(); // consume '='
          auto s = std::make_unique<Stmt>();
          s->kind = StmtKind::Assign;
          s->pos = p;
          s->varName = name;
          s->expr = parseExpr();
          s->rangeEnd = std::move(indexExpr); // store index in rangeEnd
          // Mark as index assignment by setting op to l_bracket
          s->op = Tag::l_bracket;
          match(Tag::semicolon);
          return s;
        }
        // Not an index assignment — restore and fall through
        pos_ = saved;
      }

      // Simple assignment: x = expr
      if (nextTag == Tag::equal) {
        size_t p = peek().start;
        auto name = tokenText(advance());
        advance(); // consume '='
        auto s = std::make_unique<Stmt>();
        s->kind = StmtKind::Assign;
        s->pos = p;
        s->varName = name;
        s->expr = parseExpr();
        match(Tag::semicolon);
        return s;
      }
      // Compound assignment: x += expr, x -= expr, etc.
      Tag compoundOp = Tag::invalid;
      if (nextTag == Tag::plus_eq) compoundOp = Tag::plus;
      else if (nextTag == Tag::minus_eq) compoundOp = Tag::minus;
      else if (nextTag == Tag::star_eq) compoundOp = Tag::star;
      else if (nextTag == Tag::slash_eq) compoundOp = Tag::slash;
      else if (nextTag == Tag::percent_eq) compoundOp = Tag::percent;
      if (compoundOp != Tag::invalid) {
        size_t p = peek().start;
        auto name = tokenText(advance());
        advance(); // consume '+=' etc.
        auto s = std::make_unique<Stmt>();
        s->kind = StmtKind::CompoundAssign;
        s->pos = p;
        s->varName = name;
        s->op = compoundOp;
        s->expr = parseExpr();
        match(Tag::semicolon);
        return s;
      }
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

  // ---- Struct declaration: struct Name { field: type, ... } ----
  StructDecl parseStructDecl() {
    expect(Tag::kw_struct);
    StructDecl sd;
    sd.pos = peek().start;
    sd.name = tokenText(expect(Tag::identifier));
    expect(Tag::l_brace);
    skipSemis();
    while (!check(Tag::r_brace) && !check(Tag::eof)) {
      StructField f;
      f.name = tokenText(expect(Tag::identifier));
      expect(Tag::colon);
      f.type = parseType();
      sd.fields.push_back(f);
      match(Tag::comma);
      skipSemis();
    }
    expect(Tag::r_brace);
    match(Tag::semicolon);
    return sd;
  }

  // ---- Enum declaration: enum Name { Variant1, Variant2, ... } ----
  EnumDecl parseEnumDecl() {
    expect(Tag::kw_enum);
    EnumDecl ed;
    ed.pos = peek().start;
    ed.name = tokenText(expect(Tag::identifier));
    expect(Tag::l_brace);
    skipSemis();
    int64_t nextValue = 0;
    while (!check(Tag::r_brace) && !check(Tag::eof)) {
      EnumVariant v;
      v.name = tokenText(expect(Tag::identifier));
      // Optional explicit value: Variant = 10
      if (match(Tag::equal)) {
        v.value = std::stoll(std::string(tokenText(expect(Tag::int_literal))));
        nextValue = v.value + 1;
      } else {
        v.value = nextValue++;
      }
      ed.variants.push_back(v);
      match(Tag::comma);
      skipSemis();
    }
    expect(Tag::r_brace);
    match(Tag::semicolon);
    return ed;
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
      } else if (check(Tag::kw_struct)) {
        mod.structs.push_back(parseStructDecl());
      } else if (check(Tag::kw_enum)) {
        mod.enums.push_back(parseEnumDecl());
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
