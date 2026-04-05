// libsc — Swift-Cot frontend: Swift source -> CIR via MLIR C API
//
// Architecture: Same pattern as libzc (Zig) and libtc (Go).
// Recursive-descent parser for Swift syntax, walks AST, calls cirBuild*
// C API functions directly. No CIR text generation.
//
// Reference: Swift parser (~/claude/references/swift/lib/Parse/)
// Reference: libzc/astgen.zig — Zig AstGen single-pass recursive dispatch
// Reference: libtc/codegen.go — Go frontend CIR emission

import Foundation

// =============================================================================
// MARK: - Token
// =============================================================================

enum TokenKind: Equatable {
    case eof
    case identifier(String)
    case intLiteral(Int64)
    case floatLiteral(Double)
    case stringLiteral(String)
    case boolLiteral(Bool)
    case nilLiteral

    // Keywords
    case kwFunc, kwLet, kwVar, kwReturn, kwIf, kwElse, kwWhile
    case kwStruct, kwEnum, kwCase, kwSwitch, kwDefault, kwBreak, kwContinue

    // Delimiters
    case lParen, rParen, lBrace, rBrace, lBracket, rBracket
    case comma, colon, semicolon, dot, arrow

    // Operators
    case plus, minus, star, slash, percent
    case eq, neq, lt, gt, leq, geq
    case assign
    case ampersand, pipe, caret, tilde
    case shiftLeft, shiftRight

    // Compound assignment
    case plusAssign, minusAssign, starAssign, slashAssign, percentAssign
}

struct Token {
    let kind: TokenKind
    let line: UInt32
    let col: UInt32
}

// =============================================================================
// MARK: - Scanner
// =============================================================================

struct Scanner {
    let source: [UInt8]
    var pos: Int = 0
    var line: UInt32 = 1
    var col: UInt32 = 0
    var lineStart: Int = 0

    init(source: String) {
        self.source = Array(source.utf8)
    }

    var isAtEnd: Bool { pos >= source.count }

    mutating func peek() -> UInt8? {
        guard pos < source.count else { return nil }
        return source[pos]
    }

    mutating func peekNext() -> UInt8? {
        let n = pos + 1
        guard n < source.count else { return nil }
        return source[n]
    }

    mutating func advance() -> UInt8 {
        let c = source[pos]
        pos += 1
        if c == UInt8(ascii: "\n") {
            line += 1
            lineStart = pos
            col = 0
        } else {
            col += 1
        }
        return c
    }

    mutating func skipWhitespaceAndComments() {
        while !isAtEnd {
            guard let c = peek() else { break }
            if c == UInt8(ascii: " ") || c == UInt8(ascii: "\t") ||
               c == UInt8(ascii: "\n") || c == UInt8(ascii: "\r") {
                _ = advance()
                continue
            }
            // Line comment //
            if c == UInt8(ascii: "/"), let n = peekNext(), n == UInt8(ascii: "/") {
                while !isAtEnd, let ch = peek(), ch != UInt8(ascii: "\n") {
                    _ = advance()
                }
                continue
            }
            // Block comment /* */
            if c == UInt8(ascii: "/"), let n = peekNext(), n == UInt8(ascii: "*") {
                _ = advance() // /
                _ = advance() // *
                var depth = 1
                while !isAtEnd && depth > 0 {
                    let ch = advance()
                    if ch == UInt8(ascii: "/"), let nx = peek(), nx == UInt8(ascii: "*") {
                        _ = advance()
                        depth += 1
                    } else if ch == UInt8(ascii: "*"), let nx = peek(), nx == UInt8(ascii: "/") {
                        _ = advance()
                        depth -= 1
                    }
                }
                continue
            }
            break
        }
    }

    mutating func scanToken() -> Token {
        skipWhitespaceAndComments()
        guard !isAtEnd else {
            return Token(kind: .eof, line: line, col: UInt32(pos - lineStart))
        }

        let tokLine = line
        let tokCol = UInt32(pos - lineStart)

        let c = advance()

        // Single-character tokens
        switch c {
        case UInt8(ascii: "("): return Token(kind: .lParen, line: tokLine, col: tokCol)
        case UInt8(ascii: ")"): return Token(kind: .rParen, line: tokLine, col: tokCol)
        case UInt8(ascii: "{"): return Token(kind: .lBrace, line: tokLine, col: tokCol)
        case UInt8(ascii: "}"): return Token(kind: .rBrace, line: tokLine, col: tokCol)
        case UInt8(ascii: "["): return Token(kind: .lBracket, line: tokLine, col: tokCol)
        case UInt8(ascii: "]"): return Token(kind: .rBracket, line: tokLine, col: tokCol)
        case UInt8(ascii: ","): return Token(kind: .comma, line: tokLine, col: tokCol)
        case UInt8(ascii: ":"): return Token(kind: .colon, line: tokLine, col: tokCol)
        case UInt8(ascii: ";"): return Token(kind: .semicolon, line: tokLine, col: tokCol)
        case UInt8(ascii: "~"): return Token(kind: .tilde, line: tokLine, col: tokCol)
        case UInt8(ascii: "."): return Token(kind: .dot, line: tokLine, col: tokCol)
        default: break
        }

        // Two-character tokens
        switch c {
        case UInt8(ascii: "+"):
            if let n = peek(), n == UInt8(ascii: "=") { _ = advance(); return Token(kind: .plusAssign, line: tokLine, col: tokCol) }
            return Token(kind: .plus, line: tokLine, col: tokCol)
        case UInt8(ascii: "-"):
            if let n = peek(), n == UInt8(ascii: ">") { _ = advance(); return Token(kind: .arrow, line: tokLine, col: tokCol) }
            if let n = peek(), n == UInt8(ascii: "=") { _ = advance(); return Token(kind: .minusAssign, line: tokLine, col: tokCol) }
            return Token(kind: .minus, line: tokLine, col: tokCol)
        case UInt8(ascii: "*"):
            if let n = peek(), n == UInt8(ascii: "=") { _ = advance(); return Token(kind: .starAssign, line: tokLine, col: tokCol) }
            return Token(kind: .star, line: tokLine, col: tokCol)
        case UInt8(ascii: "/"):
            if let n = peek(), n == UInt8(ascii: "=") { _ = advance(); return Token(kind: .slashAssign, line: tokLine, col: tokCol) }
            return Token(kind: .slash, line: tokLine, col: tokCol)
        case UInt8(ascii: "%"):
            if let n = peek(), n == UInt8(ascii: "=") { _ = advance(); return Token(kind: .percentAssign, line: tokLine, col: tokCol) }
            return Token(kind: .percent, line: tokLine, col: tokCol)
        case UInt8(ascii: "="):
            if let n = peek(), n == UInt8(ascii: "=") { _ = advance(); return Token(kind: .eq, line: tokLine, col: tokCol) }
            return Token(kind: .assign, line: tokLine, col: tokCol)
        case UInt8(ascii: "!"):
            if let n = peek(), n == UInt8(ascii: "=") { _ = advance(); return Token(kind: .neq, line: tokLine, col: tokCol) }
            return Token(kind: .identifier("!"), line: tokLine, col: tokCol)
        case UInt8(ascii: "<"):
            if let n = peek(), n == UInt8(ascii: "=") { _ = advance(); return Token(kind: .leq, line: tokLine, col: tokCol) }
            if let n = peek(), n == UInt8(ascii: "<") { _ = advance(); return Token(kind: .shiftLeft, line: tokLine, col: tokCol) }
            return Token(kind: .lt, line: tokLine, col: tokCol)
        case UInt8(ascii: ">"):
            if let n = peek(), n == UInt8(ascii: "=") { _ = advance(); return Token(kind: .geq, line: tokLine, col: tokCol) }
            if let n = peek(), n == UInt8(ascii: ">") { _ = advance(); return Token(kind: .shiftRight, line: tokLine, col: tokCol) }
            return Token(kind: .gt, line: tokLine, col: tokCol)
        case UInt8(ascii: "&"):
            return Token(kind: .ampersand, line: tokLine, col: tokCol)
        case UInt8(ascii: "|"):
            return Token(kind: .pipe, line: tokLine, col: tokCol)
        case UInt8(ascii: "^"):
            return Token(kind: .caret, line: tokLine, col: tokCol)
        default: break
        }

        // Number literal
        if isDigit(c) {
            var numStr = [c]
            var isFloat = false
            while let n = peek(), isDigit(n) || n == UInt8(ascii: ".") || n == UInt8(ascii: "_") {
                if n == UInt8(ascii: ".") {
                    // Check it's not a method call like 42.foo
                    if let after = peekNext(), !isDigit(after) { break }
                    isFloat = true
                }
                if n != UInt8(ascii: "_") {
                    numStr.append(n)
                }
                _ = advance()
            }
            let s = String(bytes: numStr, encoding: .utf8)!
            if isFloat {
                let val = Double(s) ?? 0.0
                return Token(kind: .floatLiteral(val), line: tokLine, col: tokCol)
            } else {
                let val = Int64(s) ?? 0
                return Token(kind: .intLiteral(val), line: tokLine, col: tokCol)
            }
        }

        // String literal
        if c == UInt8(ascii: "\"") {
            var strBytes: [UInt8] = []
            while let n = peek(), n != UInt8(ascii: "\"") {
                if n == UInt8(ascii: "\\") {
                    _ = advance()
                    if let esc = peek() {
                        _ = advance()
                        switch esc {
                        case UInt8(ascii: "n"): strBytes.append(UInt8(ascii: "\n"))
                        case UInt8(ascii: "t"): strBytes.append(UInt8(ascii: "\t"))
                        case UInt8(ascii: "\\"): strBytes.append(UInt8(ascii: "\\"))
                        case UInt8(ascii: "\""): strBytes.append(UInt8(ascii: "\""))
                        default: strBytes.append(esc)
                        }
                    }
                } else {
                    strBytes.append(advance())
                }
            }
            if !isAtEnd { _ = advance() } // closing "
            let s = String(bytes: strBytes, encoding: .utf8) ?? ""
            return Token(kind: .stringLiteral(s), line: tokLine, col: tokCol)
        }

        // Identifier / keyword
        if isIdentStart(c) {
            var idBytes = [c]
            while let n = peek(), isIdentContinue(n) {
                idBytes.append(advance())
            }
            let s = String(bytes: idBytes, encoding: .utf8)!
            let kind = keywordKind(s)
            return Token(kind: kind, line: tokLine, col: tokCol)
        }

        // Unknown character — skip
        return Token(kind: .identifier(String(UnicodeScalar(c))), line: tokLine, col: tokCol)
    }

    mutating func scanAll() -> [Token] {
        var tokens: [Token] = []
        while true {
            let tok = scanToken()
            tokens.append(tok)
            if case .eof = tok.kind { break }
        }
        return tokens
    }
}

private func isDigit(_ c: UInt8) -> Bool { c >= UInt8(ascii: "0") && c <= UInt8(ascii: "9") }
private func isIdentStart(_ c: UInt8) -> Bool {
    (c >= UInt8(ascii: "a") && c <= UInt8(ascii: "z")) ||
    (c >= UInt8(ascii: "A") && c <= UInt8(ascii: "Z")) ||
    c == UInt8(ascii: "_")
}
private func isIdentContinue(_ c: UInt8) -> Bool { isIdentStart(c) || isDigit(c) }

private func keywordKind(_ s: String) -> TokenKind {
    switch s {
    case "func":     return .kwFunc
    case "let":      return .kwLet
    case "var":      return .kwVar
    case "return":   return .kwReturn
    case "if":       return .kwIf
    case "else":     return .kwElse
    case "while":    return .kwWhile
    case "struct":   return .kwStruct
    case "enum":     return .kwEnum
    case "case":     return .kwCase
    case "switch":   return .kwSwitch
    case "default":  return .kwDefault
    case "break":    return .kwBreak
    case "continue": return .kwContinue
    case "true":     return .boolLiteral(true)
    case "false":    return .boolLiteral(false)
    case "nil":      return .nilLiteral
    default:         return .identifier(s)
    }
}

// =============================================================================
// MARK: - AST
// =============================================================================

indirect enum Expr {
    case intLit(Int64)
    case floatLit(Double)
    case stringLit(String)
    case boolLit(Bool)
    case nilLit
    case ident(String)
    case binary(BinOp, Expr, Expr)
    case unaryMinus(Expr)
    case call(String, [Expr])
    case memberAccess(Expr, String)        // expr.field
    case structInit(String, [(String, Expr)]) // TypeName(field: val, ...)
}

enum BinOp {
    case add, sub, mul, div, rem
    case eq, neq, lt, gt, leq, geq
    case bitAnd, bitOr, bitXor, shl, shr
}

indirect enum Stmt {
    case returnStmt(Expr?)
    case exprStmt(Expr)
    case letDecl(String, SwiftType?, Expr?)
    case varDecl(String, SwiftType?, Expr?)
    case assign(String, Expr)
    case compoundAssign(BinOp, String, Expr)
    case ifStmt(Expr, [Stmt], [Stmt]?)
    case whileStmt(Expr, [Stmt])
    case breakStmt
    case continueStmt
    case switchStmt(Expr, [(SwitchCase, [Stmt])], [Stmt]?)
}

enum SwitchCase {
    case expr(Expr)
    case defaultCase
}

enum SwiftType {
    case named(String)  // Int32, Bool, String, MyStruct...
}

struct FuncParam {
    let name: String
    let type: SwiftType
}

enum Decl {
    case funcDecl(String, [FuncParam], SwiftType?, [Stmt])
    case structDecl(String, [(String, SwiftType)])
    case enumDecl(String, [(String, Int64?)])
}

// =============================================================================
// MARK: - Parser
// =============================================================================

struct Parser {
    var tokens: [Token]
    var pos: Int = 0

    init(tokens: [Token]) {
        self.tokens = tokens
    }

    var current: Token { tokens[pos] }

    mutating func peek() -> TokenKind { tokens[pos].kind }

    mutating func advance() -> Token {
        let tok = tokens[pos]
        if pos < tokens.count - 1 { pos += 1 }
        return tok
    }

    mutating func expect(_ kind: TokenKind) -> Bool {
        if tokenMatches(peek(), kind) {
            _ = advance()
            return true
        }
        return false
    }

    mutating func expectIdentifier() -> String? {
        if case .identifier(let s) = peek() {
            _ = advance()
            return s
        }
        return nil
    }

    // Parse all top-level declarations
    mutating func parseModule() -> [Decl] {
        var decls: [Decl] = []
        while !isEof() {
            if let d = parseDecl() {
                decls.append(d)
            } else {
                _ = advance() // skip unrecognized token
            }
        }
        return decls
    }

    mutating func isEof() -> Bool {
        if case .eof = peek() { return true }
        return false
    }

    // MARK: Declarations

    mutating func parseDecl() -> Decl? {
        switch peek() {
        case .kwFunc:   return parseFuncDecl()
        case .kwStruct: return parseStructDecl()
        case .kwEnum:   return parseEnumDecl()
        default:        return nil
        }
    }

    // func name(params) -> RetType { body }
    mutating func parseFuncDecl() -> Decl? {
        _ = advance() // func
        guard let name = expectIdentifier() else { return nil }
        guard expect(.lParen) else { return nil }

        var params: [FuncParam] = []
        while !tokenMatches(peek(), .rParen) && !isEof() {
            // Swift param: name: Type  or  _ name: Type
            var paramName: String
            if case .identifier(let s) = peek() {
                _ = advance()
                // Check if next is colon (name: Type) or another ident (_ name: Type)
                if tokenMatches(peek(), .colon) {
                    paramName = s
                } else if case .identifier(let actualName) = peek() {
                    // External label was s, actual name is next
                    _ = advance()
                    paramName = actualName
                } else {
                    paramName = s
                }
            } else {
                break
            }

            guard expect(.colon) else { break }
            guard let ptype = parseType() else { break }
            params.append(FuncParam(name: paramName, type: ptype))
            if !tokenMatches(peek(), .rParen) {
                _ = expect(.comma)
            }
        }
        _ = expect(.rParen)

        // Return type
        var retType: SwiftType? = nil
        if tokenMatches(peek(), .arrow) {
            _ = advance() // ->
            retType = parseType()
        }

        // Body
        guard expect(.lBrace) else { return nil }
        let body = parseStmtList()
        _ = expect(.rBrace)

        return .funcDecl(name, params, retType, body)
    }

    // struct Name { let field: Type; ... }
    mutating func parseStructDecl() -> Decl? {
        _ = advance() // struct
        guard let name = expectIdentifier() else { return nil }
        guard expect(.lBrace) else { return nil }

        var fields: [(String, SwiftType)] = []
        while !tokenMatches(peek(), .rBrace) && !isEof() {
            // Expect let/var fieldName: Type
            if tokenMatches(peek(), .kwLet) || tokenMatches(peek(), .kwVar) {
                _ = advance()
            }
            guard let fname = expectIdentifier() else { break }
            guard expect(.colon) else { break }
            guard let ftype = parseType() else { break }
            fields.append((fname, ftype))
            // optional semicolons/newlines handled by scanner
        }
        _ = expect(.rBrace)
        return .structDecl(name, fields)
    }

    // enum Name { case a, b, c } or enum Name: Int32 { case a = 0 ... }
    mutating func parseEnumDecl() -> Decl? {
        _ = advance() // enum
        guard let name = expectIdentifier() else { return nil }

        // Optional raw type annotation (enum Color: Int32)
        if tokenMatches(peek(), .colon) {
            _ = advance() // :
            _ = parseType() // consume raw type (we use i32 by default)
        }

        guard expect(.lBrace) else { return nil }

        var variants: [(String, Int64?)] = []
        while !tokenMatches(peek(), .rBrace) && !isEof() {
            guard expect(.kwCase) else {
                _ = advance() // skip unknown
                continue
            }
            // case name [= value] [, name2 [= value2], ...]
            repeat {
                guard let vname = expectIdentifier() else { break }
                var val: Int64? = nil
                if tokenMatches(peek(), .assign) {
                    _ = advance()
                    if case .intLiteral(let v) = peek() {
                        _ = advance()
                        val = v
                    }
                }
                variants.append((vname, val))
            } while expect(.comma)
        }
        _ = expect(.rBrace)
        return .enumDecl(name, variants)
    }

    mutating func parseType() -> SwiftType? {
        if case .identifier(let s) = peek() {
            _ = advance()
            return .named(s)
        }
        return nil
    }

    // MARK: Statements

    mutating func parseStmtList() -> [Stmt] {
        var stmts: [Stmt] = []
        while !tokenMatches(peek(), .rBrace) && !isEof() {
            if let s = parseStmt() {
                stmts.append(s)
            } else {
                _ = advance() // skip unrecognized
            }
        }
        return stmts
    }

    mutating func parseStmt() -> Stmt? {
        // Skip stray semicolons
        while tokenMatches(peek(), .semicolon) { _ = advance() }
        if tokenMatches(peek(), .rBrace) || isEof() { return nil }

        switch peek() {
        case .kwReturn:   return parseReturn()
        case .kwLet:      return parseLetDecl()
        case .kwVar:      return parseVarDecl()
        case .kwIf:       return parseIfStmt()
        case .kwWhile:    return parseWhileStmt()
        case .kwBreak:    _ = advance(); return .breakStmt
        case .kwContinue: _ = advance(); return .continueStmt
        case .kwSwitch:   return parseSwitchStmt()
        default:          return parseExprOrAssignStmt()
        }
    }

    mutating func parseReturn() -> Stmt? {
        _ = advance() // return
        // If next is } or ;, return void
        if tokenMatches(peek(), .rBrace) || tokenMatches(peek(), .semicolon) || isEof() {
            return .returnStmt(nil)
        }
        let expr = parseExpr()
        return .returnStmt(expr)
    }

    mutating func parseLetDecl() -> Stmt? {
        _ = advance() // let
        guard let name = expectIdentifier() else { return nil }
        var ty: SwiftType? = nil
        if tokenMatches(peek(), .colon) {
            _ = advance()
            ty = parseType()
        }
        var init_: Expr? = nil
        if tokenMatches(peek(), .assign) {
            _ = advance()
            init_ = parseExpr()
        }
        return .letDecl(name, ty, init_)
    }

    mutating func parseVarDecl() -> Stmt? {
        _ = advance() // var
        guard let name = expectIdentifier() else { return nil }
        var ty: SwiftType? = nil
        if tokenMatches(peek(), .colon) {
            _ = advance()
            ty = parseType()
        }
        var init_: Expr? = nil
        if tokenMatches(peek(), .assign) {
            _ = advance()
            init_ = parseExpr()
        }
        return .varDecl(name, ty, init_)
    }

    mutating func parseIfStmt() -> Stmt? {
        _ = advance() // if
        let cond = parseExpr()!
        guard expect(.lBrace) else { return nil }
        let thenBody = parseStmtList()
        _ = expect(.rBrace)

        var elseBody: [Stmt]? = nil
        if tokenMatches(peek(), .kwElse) {
            _ = advance()
            if tokenMatches(peek(), .kwIf) {
                // else if -> treat as single else block with nested if
                if let nested = parseIfStmt() {
                    elseBody = [nested]
                }
            } else {
                guard expect(.lBrace) else { return nil }
                elseBody = parseStmtList()
                _ = expect(.rBrace)
            }
        }

        return .ifStmt(cond, thenBody, elseBody)
    }

    mutating func parseWhileStmt() -> Stmt? {
        _ = advance() // while
        let cond = parseExpr()!
        guard expect(.lBrace) else { return nil }
        let body = parseStmtList()
        _ = expect(.rBrace)
        return .whileStmt(cond, body)
    }

    mutating func parseSwitchStmt() -> Stmt? {
        _ = advance() // switch
        let disc = parseExpr()!
        guard expect(.lBrace) else { return nil }

        var cases: [(SwitchCase, [Stmt])] = []
        var defaultBody: [Stmt]? = nil

        while !tokenMatches(peek(), .rBrace) && !isEof() {
            if tokenMatches(peek(), .kwCase) {
                _ = advance() // case
                let caseExpr = parseExpr()!
                _ = expect(.colon)
                var stmts: [Stmt] = []
                while !tokenMatches(peek(), .kwCase) && !tokenMatches(peek(), .kwDefault) &&
                      !tokenMatches(peek(), .rBrace) && !isEof() {
                    if let s = parseStmt() {
                        stmts.append(s)
                    } else {
                        _ = advance()
                    }
                }
                cases.append((.expr(caseExpr), stmts))
            } else if tokenMatches(peek(), .kwDefault) {
                _ = advance() // default
                _ = expect(.colon)
                var stmts: [Stmt] = []
                while !tokenMatches(peek(), .kwCase) && !tokenMatches(peek(), .kwDefault) &&
                      !tokenMatches(peek(), .rBrace) && !isEof() {
                    if let s = parseStmt() {
                        stmts.append(s)
                    } else {
                        _ = advance()
                    }
                }
                defaultBody = stmts
            } else {
                _ = advance()
            }
        }
        _ = expect(.rBrace)
        return .switchStmt(disc, cases, defaultBody)
    }

    mutating func parseExprOrAssignStmt() -> Stmt? {
        guard let expr = parseExpr() else { return nil }
        // Check for assignment: ident = expr
        if case .ident(let name) = expr {
            if tokenMatches(peek(), .assign) {
                _ = advance()
                guard let rhs = parseExpr() else { return nil }
                return .assign(name, rhs)
            }
            if let op = compoundAssignOp(peek()) {
                _ = advance()
                guard let rhs = parseExpr() else { return nil }
                return .compoundAssign(op, name, rhs)
            }
        }
        return .exprStmt(expr)
    }

    // MARK: Expressions (precedence climbing)

    mutating func parseExpr() -> Expr? {
        return parseComparison()
    }

    mutating func parseComparison() -> Expr? {
        guard var lhs = parseBitOr() else { return nil }
        while true {
            let op: BinOp
            switch peek() {
            case .eq:  _ = advance(); op = .eq
            case .neq: _ = advance(); op = .neq
            case .lt:  _ = advance(); op = .lt
            case .gt:  _ = advance(); op = .gt
            case .leq: _ = advance(); op = .leq
            case .geq: _ = advance(); op = .geq
            default: return lhs
            }
            guard let rhs = parseBitOr() else { return nil }
            lhs = .binary(op, lhs, rhs)
        }
    }

    mutating func parseBitOr() -> Expr? {
        guard var lhs = parseBitXor() else { return nil }
        while tokenMatches(peek(), .pipe) {
            _ = advance()
            guard let rhs = parseBitXor() else { return nil }
            lhs = .binary(.bitOr, lhs, rhs)
        }
        return lhs
    }

    mutating func parseBitXor() -> Expr? {
        guard var lhs = parseBitAnd() else { return nil }
        while tokenMatches(peek(), .caret) {
            _ = advance()
            guard let rhs = parseBitAnd() else { return nil }
            lhs = .binary(.bitXor, lhs, rhs)
        }
        return lhs
    }

    mutating func parseBitAnd() -> Expr? {
        guard var lhs = parseShift() else { return nil }
        while tokenMatches(peek(), .ampersand) {
            _ = advance()
            guard let rhs = parseShift() else { return nil }
            lhs = .binary(.bitAnd, lhs, rhs)
        }
        return lhs
    }

    mutating func parseShift() -> Expr? {
        guard var lhs = parseAddSub() else { return nil }
        while true {
            let op: BinOp
            switch peek() {
            case .shiftLeft:  _ = advance(); op = .shl
            case .shiftRight: _ = advance(); op = .shr
            default: return lhs
            }
            guard let rhs = parseAddSub() else { return nil }
            lhs = .binary(op, lhs, rhs)
        }
    }

    mutating func parseAddSub() -> Expr? {
        guard var lhs = parseMulDiv() else { return nil }
        while true {
            let op: BinOp
            switch peek() {
            case .plus:  _ = advance(); op = .add
            case .minus: _ = advance(); op = .sub
            default: return lhs
            }
            guard let rhs = parseMulDiv() else { return nil }
            lhs = .binary(op, lhs, rhs)
        }
    }

    mutating func parseMulDiv() -> Expr? {
        guard var lhs = parseUnary() else { return nil }
        while true {
            let op: BinOp
            switch peek() {
            case .star:    _ = advance(); op = .mul
            case .slash:   _ = advance(); op = .div
            case .percent: _ = advance(); op = .rem
            default: return lhs
            }
            guard let rhs = parseUnary() else { return nil }
            lhs = .binary(op, lhs, rhs)
        }
    }

    mutating func parseUnary() -> Expr? {
        if tokenMatches(peek(), .minus) {
            _ = advance()
            guard let operand = parseUnary() else { return nil }
            return .unaryMinus(operand)
        }
        return parsePostfix()
    }

    mutating func parsePostfix() -> Expr? {
        guard var expr = parsePrimary() else { return nil }
        while true {
            if tokenMatches(peek(), .dot) {
                _ = advance()
                guard let field = expectIdentifier() else { return nil }
                expr = .memberAccess(expr, field)
            } else {
                break
            }
        }
        return expr
    }

    mutating func parsePrimary() -> Expr? {
        switch peek() {
        case .intLiteral(let v):
            _ = advance()
            return .intLit(v)
        case .floatLiteral(let v):
            _ = advance()
            return .floatLit(v)
        case .stringLiteral(let s):
            _ = advance()
            return .stringLit(s)
        case .boolLiteral(let v):
            _ = advance()
            return .boolLit(v)
        case .nilLiteral:
            _ = advance()
            return .nilLit
        case .identifier(let name):
            _ = advance()
            // Check for function call or struct init: Name(...)
            if tokenMatches(peek(), .lParen) {
                _ = advance() // (
                var args: [Expr] = []
                var labeledArgs: [(String, Expr)] = []
                var isLabeled = false
                while !tokenMatches(peek(), .rParen) && !isEof() {
                    // Check if this is labeled: name: expr
                    if case .identifier(let argName) = peek() {
                        let savedPos = pos
                        _ = advance()
                        if tokenMatches(peek(), .colon) {
                            _ = advance() // :
                            isLabeled = true
                            guard let argVal = parseExpr() else { break }
                            labeledArgs.append((argName, argVal))
                            if !tokenMatches(peek(), .rParen) { _ = expect(.comma) }
                            continue
                        } else {
                            // Not labeled, rewind
                            pos = savedPos
                        }
                    }
                    guard let arg = parseExpr() else { break }
                    args.append(arg)
                    if !tokenMatches(peek(), .rParen) { _ = expect(.comma) }
                }
                _ = expect(.rParen)
                if isLabeled {
                    return .structInit(name, labeledArgs)
                }
                return .call(name, args)
            }
            return .ident(name)
        case .lParen:
            _ = advance() // (
            let expr = parseExpr()
            _ = expect(.rParen)
            return expr
        default:
            return nil
        }
    }
}

private func tokenMatches(_ a: TokenKind, _ b: TokenKind) -> Bool {
    switch (a, b) {
    case (.eof, .eof): return true
    case (.lParen, .lParen): return true
    case (.rParen, .rParen): return true
    case (.lBrace, .lBrace): return true
    case (.rBrace, .rBrace): return true
    case (.lBracket, .lBracket): return true
    case (.rBracket, .rBracket): return true
    case (.comma, .comma): return true
    case (.colon, .colon): return true
    case (.semicolon, .semicolon): return true
    case (.dot, .dot): return true
    case (.arrow, .arrow): return true
    case (.plus, .plus): return true
    case (.minus, .minus): return true
    case (.star, .star): return true
    case (.slash, .slash): return true
    case (.percent, .percent): return true
    case (.eq, .eq): return true
    case (.neq, .neq): return true
    case (.lt, .lt): return true
    case (.gt, .gt): return true
    case (.leq, .leq): return true
    case (.geq, .geq): return true
    case (.assign, .assign): return true
    case (.ampersand, .ampersand): return true
    case (.pipe, .pipe): return true
    case (.caret, .caret): return true
    case (.tilde, .tilde): return true
    case (.shiftLeft, .shiftLeft): return true
    case (.shiftRight, .shiftRight): return true
    case (.plusAssign, .plusAssign): return true
    case (.minusAssign, .minusAssign): return true
    case (.starAssign, .starAssign): return true
    case (.slashAssign, .slashAssign): return true
    case (.percentAssign, .percentAssign): return true
    case (.kwFunc, .kwFunc): return true
    case (.kwLet, .kwLet): return true
    case (.kwVar, .kwVar): return true
    case (.kwReturn, .kwReturn): return true
    case (.kwIf, .kwIf): return true
    case (.kwElse, .kwElse): return true
    case (.kwWhile, .kwWhile): return true
    case (.kwStruct, .kwStruct): return true
    case (.kwEnum, .kwEnum): return true
    case (.kwCase, .kwCase): return true
    case (.kwSwitch, .kwSwitch): return true
    case (.kwDefault, .kwDefault): return true
    case (.kwBreak, .kwBreak): return true
    case (.kwContinue, .kwContinue): return true
    case (.nilLiteral, .nilLiteral): return true
    default: return false
    }
}

private func compoundAssignOp(_ kind: TokenKind) -> BinOp? {
    switch kind {
    case .plusAssign:    return .add
    case .minusAssign:  return .sub
    case .starAssign:   return .mul
    case .slashAssign:  return .div
    case .percentAssign: return .rem
    default: return nil
    }
}

// =============================================================================
// MARK: - Codegen: AST -> CIR via MLIR C API
// =============================================================================

/// Code generator: walks AST, calls CIR C API to build MLIR ops.
/// Mirrors Gen struct from libzc/astgen.zig and libtc/codegen.go.
final class Gen {
    let ctx: MlirContext
    let module: MlirModule
    let filename: String

    // Current function state
    var currentFunc: MlirOperation = MlirOperation(ptr: nil)
    var currentBlock: MlirBlock = MlirBlock(ptr: nil)
    var hasTerminator: Bool = false
    var currentRetType: MlirType = MlirType(ptr: nil)

    // Scope: parameter names and values
    var paramNames: [String] = []
    var paramValues: [MlirValue] = []

    // Scope: local variable names, addresses (from alloca), types
    var localNames: [String] = []
    var localAddrs: [MlirValue] = []
    var localTypes: [MlirType] = []

    // Loop context for break/continue
    struct LoopCtx {
        let header: MlirBlock
        let exit: MlirBlock
    }
    var loopStack: [LoopCtx] = []

    // Struct type registry
    struct StructInfo {
        let name: String
        let mlirType: MlirType
        let fieldNames: [String]
        let fieldTypes: [MlirType]
    }
    var structs: [StructInfo] = []

    // Enum type registry
    struct EnumInfo {
        let name: String
        let mlirType: MlirType
        let variantNames: [String]
        let variantValues: [Int64]
    }
    var enums: [EnumInfo] = []

    init(filename: String) {
        self.filename = filename
        let c = mlirContextCreate()
        cirRegisterDialect(c)
        mlirContextSetAllowUnregisteredDialects(c, true)
        self.ctx = c
        self.module = mlirModuleCreateEmpty(mlirLocationUnknownGet(c))
    }

    func destroy() {
        mlirModuleDestroy(module)
        mlirContextDestroy(ctx)
    }

    // MARK: Location helpers

    func loc(_ line: UInt32, _ col: UInt32) -> MlirLocation {
        return filename.withCString { cstr in
            let ref = mlirStringRefCreateFromCString(cstr)
            return cirLocationFileLineCol(ctx, ref, UInt32(line), UInt32(col))
        }
    }

    var unknownLoc: MlirLocation { mlirLocationUnknownGet(ctx) }

    // MARK: Type helpers

    func intType(_ bits: UInt32) -> MlirType {
        return mlirIntegerTypeGet(ctx, bits)
    }

    func f32Type() -> MlirType { return mlirF32TypeGet(ctx) }
    func f64Type() -> MlirType { return mlirF64TypeGet(ctx) }

    func resolveType(_ ty: SwiftType) -> MlirType {
        switch ty {
        case .named(let name):
            switch name {
            case "Int8", "UInt8":   return intType(8)
            case "Int16", "UInt16": return intType(16)
            case "Int32", "UInt32": return intType(32)
            case "Int64", "UInt64", "Int": return intType(64)
            case "Float":  return f32Type()
            case "Double": return f64Type()
            case "Bool":   return intType(1)
            case "String":
                // String -> !cir.slice<i8>
                return cirSliceTypeGet(ctx, intType(8))
            case "Void":
                return intType(0)
            default:
                // Check struct types
                for s in structs {
                    if s.name == name { return s.mlirType }
                }
                // Check enum types
                for e in enums {
                    if e.name == name { return e.mlirType }
                }
                return intType(32) // default fallback
            }
        }
    }

    // MARK: MLIR builder helpers

    func strAttr(_ s: String) -> MlirAttribute {
        return s.withCString { cstr in
            let ref = mlirStringRefCreateFromCString(cstr)
            return mlirStringAttrGet(ctx, ref)
        }
    }

    func typeAttr(_ ty: MlirType) -> MlirAttribute {
        return mlirTypeAttrGet(ty)
    }

    func namedAttr(_ name: String, _ attr: MlirAttribute) -> MlirNamedAttribute {
        return name.withCString { cstr in
            let ref = mlirStringRefCreateFromCString(cstr)
            let id = mlirIdentifierGet(ctx, ref)
            return mlirNamedAttributeGet(id, attr)
        }
    }

    /// Create a new empty block and attach it to the current function's region.
    func addBlock() -> MlirBlock {
        let block = mlirBlockCreate(0, nil, nil)
        let region = mlirOperationGetRegion(currentFunc, 0)
        mlirRegionAppendOwnedBlock(region, block)
        return block
    }

    /// Emit a generic MLIR operation.
    func emit(block: MlirBlock, name: String, resultTypes: [MlirType],
              operands: [MlirValue], attrs: [MlirNamedAttribute],
              location: MlirLocation) -> MlirValue {
        return name.withCString { cstr in
            let ref = mlirStringRefCreateFromCString(cstr)
            var state = mlirOperationStateGet(ref, location)

            resultTypes.withUnsafeBufferPointer { rtBuf in
                if rtBuf.count > 0 {
                    mlirOperationStateAddResults(&state, rtBuf.count, rtBuf.baseAddress)
                }
            }
            operands.withUnsafeBufferPointer { opBuf in
                if opBuf.count > 0 {
                    mlirOperationStateAddOperands(&state, opBuf.count, opBuf.baseAddress)
                }
            }
            var mutableAttrs = attrs
            mutableAttrs.withUnsafeMutableBufferPointer { atBuf in
                if atBuf.count > 0 {
                    mlirOperationStateAddAttributes(&state, atBuf.count, atBuf.baseAddress)
                }
            }

            let op = mlirOperationCreate(&state)
            mlirBlockAppendOwnedOperation(block, op)

            if resultTypes.count > 0 {
                return mlirOperationGetResult(op, 0)
            }
            return MlirValue(ptr: nil)
        }
    }

    /// Create func.func: create region, entry block, operation, attach to module.
    func createFunc(name: String, paramTypes: [MlirType], returnTypes: [MlirType],
                    location: MlirLocation) -> (MlirOperation, MlirBlock) {
        // Build function type
        let funcType: MlirType = paramTypes.withUnsafeBufferPointer { inBuf in
            returnTypes.withUnsafeBufferPointer { outBuf in
                mlirFunctionTypeGet(ctx,
                    inBuf.count, inBuf.baseAddress,
                    outBuf.count, outBuf.baseAddress)
            }
        }

        // Create entry block with parameter types as block arguments
        let entryBlock: MlirBlock = paramTypes.withUnsafeBufferPointer { ptBuf in
            var locs = [MlirLocation](repeating: location, count: paramTypes.count)
            return locs.withUnsafeMutableBufferPointer { locBuf in
                return mlirBlockCreate(ptBuf.count,
                    ptBuf.count > 0 ? ptBuf.baseAddress : nil,
                    locBuf.count > 0 ? locBuf.baseAddress : nil)
            }
        }

        // Create region, add entry block
        let region = mlirRegionCreate()
        mlirRegionAppendOwnedBlock(region, entryBlock)

        // Build func.func operation
        let funcOp: MlirOperation = "func.func".withCString { cstr in
            let ref = mlirStringRefCreateFromCString(cstr)
            var state = mlirOperationStateGet(ref, location)
            withUnsafePointer(to: region) { rPtr in
                mlirOperationStateAddOwnedRegions(&state, 1, rPtr)
            }
            var attrs = [
                namedAttr("sym_name", strAttr(name)),
                namedAttr("function_type", typeAttr(funcType))
            ]
            attrs.withUnsafeMutableBufferPointer { buf in
                mlirOperationStateAddAttributes(&state, buf.count, buf.baseAddress)
            }
            return mlirOperationCreate(&state)
        }

        // Append to module body
        let moduleBody = mlirModuleGetBody(module)
        mlirBlockAppendOwnedOperation(moduleBody, funcOp)

        return (funcOp, entryBlock)
    }

    // MARK: Generate from declarations

    func generate(_ decls: [Decl]) {
        for decl in decls {
            mapDecl(decl)
        }
    }

    func mapDecl(_ decl: Decl) {
        switch decl {
        case .funcDecl(let name, let params, let retType, let body):
            mapFuncDecl(name: name, params: params, retType: retType, body: body)
        case .structDecl(let name, let fields):
            mapStructDecl(name: name, fields: fields)
        case .enumDecl(let name, let variants):
            mapEnumDecl(name: name, variants: variants)
        }
    }

    func mapStructDecl(name: String, fields: [(String, SwiftType)]) {
        let fieldNames = fields.map { $0.0 }
        let fieldTypes = fields.map { resolveType($0.1) }

        // Build CIR struct type via parsing type string
        // (matches libtc/codegen.go mapInterfaceDecl approach)
        var typeStr = "!cir.struct<\"\(name)\""
        for (fname, ftype) in fields {
            let ftypeStr = swiftTypeToString(ftype)
            typeStr += ", \(fname): \(ftypeStr)"
        }
        typeStr += ">"

        let structType = typeStr.withCString { cstr in
            let ref = mlirStringRefCreateFromCString(cstr)
            return mlirTypeParseGet(ctx, ref)
        }

        structs.append(StructInfo(name: name, mlirType: structType,
                                  fieldNames: fieldNames, fieldTypes: fieldTypes))
    }

    func mapEnumDecl(name: String, variants: [(String, Int64?)]) {
        var variantNames: [String] = []
        var variantValues: [Int64] = []
        var nextVal: Int64 = 0

        for (vname, explicitVal) in variants {
            variantNames.append(vname)
            if let v = explicitVal {
                variantValues.append(v)
                nextVal = v + 1
            } else {
                variantValues.append(nextVal)
                nextVal += 1
            }
        }

        let tagType = intType(32)

        // Create CIR enum type via C API
        let enumType = withArrayOfCStrings(variantNames) { _, refs in
            var mutableRefs = refs
            var mutableVals = variantValues
            return name.withCString { nameCs in
                let nameRef = mlirStringRefCreateFromCString(nameCs)
                return mutableRefs.withUnsafeMutableBufferPointer { refBuf in
                    mutableVals.withUnsafeMutableBufferPointer { valBuf in
                        return cirEnumTypeGet(ctx, nameRef, tagType,
                            refBuf.count,
                            refBuf.count > 0 ? refBuf.baseAddress : nil,
                            valBuf.count > 0 ? valBuf.baseAddress : nil)
                    }
                }
            }
        }

        enums.append(EnumInfo(name: name, mlirType: enumType,
                              variantNames: variantNames, variantValues: variantValues))
    }

    func mapFuncDecl(name: String, params: [FuncParam], retType: SwiftType?, body: [Stmt]) {
        let paramTypes = params.map { resolveType($0.type) }
        var returnTypes: [MlirType] = []
        if let rt = retType {
            let resolved = resolveType(rt)
            returnTypes.append(resolved)
            currentRetType = resolved
        } else {
            currentRetType = MlirType(ptr: nil)
        }

        let location = unknownLoc
        let (funcOp, entryBlock) = createFunc(name: name, paramTypes: paramTypes,
                                               returnTypes: returnTypes, location: location)
        currentFunc = funcOp
        currentBlock = entryBlock
        hasTerminator = false

        // Set up parameter scope
        paramNames = params.map { $0.name }
        paramValues = []
        for i in 0..<paramTypes.count {
            paramValues.append(mlirBlockGetArgument(entryBlock, i))
        }

        // Reset local scope
        localNames = []
        localAddrs = []
        localTypes = []
        loopStack = []

        // Emit body statements
        for stmt in body {
            if hasTerminator { break }
            mapStmt(stmt)
        }

        // Emit implicit void return if needed
        if !hasTerminator {
            _ = emit(block: currentBlock, name: "func.return",
                     resultTypes: [], operands: [], attrs: [], location: unknownLoc)
        }
    }

    // MARK: Statement codegen

    func mapStmt(_ stmt: Stmt) {
        switch stmt {
        case .returnStmt(let expr):
            mapReturn(expr)
        case .exprStmt(let expr):
            _ = mapExpr(expr, expectedType: intType(32))
        case .letDecl(let name, let ty, let init_):
            mapVarBinding(name: name, ty: ty, init_: init_)
        case .varDecl(let name, let ty, let init_):
            mapVarBinding(name: name, ty: ty, init_: init_)
        case .assign(let name, let expr):
            mapAssign(name: name, expr: expr)
        case .compoundAssign(let op, let name, let expr):
            mapCompoundAssign(op: op, name: name, expr: expr)
        case .ifStmt(let cond, let thenBody, let elseBody):
            mapIfStmt(cond: cond, thenBody: thenBody, elseBody: elseBody)
        case .whileStmt(let cond, let body):
            mapWhileStmt(cond: cond, body: body)
        case .breakStmt:
            if let loop = loopStack.last {
                cirBuildBr(currentBlock, unknownLoc, loop.exit, 0, nil)
                hasTerminator = true
            }
        case .continueStmt:
            if let loop = loopStack.last {
                cirBuildBr(currentBlock, unknownLoc, loop.header, 0, nil)
                hasTerminator = true
            }
        case .switchStmt(let disc, let cases, let defaultBody):
            mapSwitchStmt(disc: disc, cases: cases, defaultBody: defaultBody)
        }
    }

    func mapReturn(_ expr: Expr?) {
        if let expr = expr {
            var val = mapExpr(expr, expectedType: currentRetType)
            // Auto-cast integer width mismatches
            let valType = mlirValueGetType(val)
            if mlirTypeIsAInteger(valType) && mlirTypeIsAInteger(currentRetType) {
                let vw = mlirIntegerTypeGetWidth(valType)
                let rw = mlirIntegerTypeGetWidth(currentRetType)
                if vw > 0 && rw > 0 && vw != rw {
                    if vw > rw {
                        val = cirBuildTruncI(currentBlock, unknownLoc, currentRetType, val)
                    } else {
                        val = cirBuildExtSI(currentBlock, unknownLoc, currentRetType, val)
                    }
                }
            }
            _ = emit(block: currentBlock, name: "func.return",
                     resultTypes: [], operands: [val], attrs: [], location: unknownLoc)
        } else {
            _ = emit(block: currentBlock, name: "func.return",
                     resultTypes: [], operands: [], attrs: [], location: unknownLoc)
        }
        hasTerminator = true
    }

    func mapVarBinding(name: String, ty: SwiftType?, init_: Expr?) {
        var varType: MlirType
        if let ty = ty {
            varType = resolveType(ty)
        } else {
            varType = intType(32)
        }

        let addr = cirBuildAlloca(currentBlock, unknownLoc, varType)

        if let init_ = init_ {
            let val = mapExpr(init_, expectedType: varType)
            cirBuildStore(currentBlock, unknownLoc, val, addr)
        }

        localNames.append(name)
        localAddrs.append(addr)
        localTypes.append(varType)
    }

    func mapAssign(name: String, expr: Expr) {
        for i in stride(from: localNames.count - 1, through: 0, by: -1) {
            if localNames[i] == name {
                let val = mapExpr(expr, expectedType: localTypes[i])
                cirBuildStore(currentBlock, unknownLoc, val, localAddrs[i])
                return
            }
        }
    }

    func mapCompoundAssign(op: BinOp, name: String, expr: Expr) {
        for i in stride(from: localNames.count - 1, through: 0, by: -1) {
            if localNames[i] == name {
                let current = cirBuildLoad(currentBlock, unknownLoc, localTypes[i], localAddrs[i])
                let rhs = mapExpr(expr, expectedType: localTypes[i])
                let result = emitBinOp(op, localTypes[i], current, rhs)
                cirBuildStore(currentBlock, unknownLoc, result, localAddrs[i])
                return
            }
        }
    }

    func mapIfStmt(cond: Expr, thenBody: [Stmt], elseBody: [Stmt]?) {
        let condVal = mapExpr(cond, expectedType: intType(1))

        let thenBlock = addBlock()
        let elseBlock = addBlock()
        let mergeBlock = addBlock()

        cirBuildCondBr(currentBlock, unknownLoc, condVal, thenBlock, elseBlock)

        // Then branch
        currentBlock = thenBlock
        hasTerminator = false
        for stmt in thenBody {
            if hasTerminator { break }
            mapStmt(stmt)
        }
        let thenTerminated = hasTerminator
        if !thenTerminated {
            cirBuildBr(currentBlock, unknownLoc, mergeBlock, 0, nil)
        }

        // Else branch
        currentBlock = elseBlock
        hasTerminator = false
        if let elseBody = elseBody {
            for stmt in elseBody {
                if hasTerminator { break }
                mapStmt(stmt)
            }
        }
        let elseTerminated = hasTerminator
        if !elseTerminated {
            cirBuildBr(currentBlock, unknownLoc, mergeBlock, 0, nil)
        }

        currentBlock = mergeBlock
        if thenTerminated && elseTerminated {
            cirBuildTrap(mergeBlock, unknownLoc)
            hasTerminator = true
        } else {
            hasTerminator = false
        }
    }

    func mapWhileStmt(cond: Expr, body: [Stmt]) {
        let headerBlock = addBlock()
        let bodyBlock = addBlock()
        let exitBlock = addBlock()

        cirBuildBr(currentBlock, unknownLoc, headerBlock, 0, nil)

        // Header: evaluate condition
        currentBlock = headerBlock
        let condVal = mapExpr(cond, expectedType: intType(1))
        cirBuildCondBr(headerBlock, unknownLoc, condVal, bodyBlock, exitBlock)

        // Body
        loopStack.append(LoopCtx(header: headerBlock, exit: exitBlock))
        currentBlock = bodyBlock
        hasTerminator = false
        for stmt in body {
            if hasTerminator { break }
            mapStmt(stmt)
        }
        loopStack.removeLast()
        if !hasTerminator {
            cirBuildBr(currentBlock, unknownLoc, headerBlock, 0, nil)
        }

        currentBlock = exitBlock
        hasTerminator = false
    }

    func mapSwitchStmt(disc: Expr, cases: [(SwitchCase, [Stmt])], defaultBody: [Stmt]?) {
        let condVal = mapExpr(disc, expectedType: intType(32))
        let condType = mlirValueGetType(condVal)

        // If condition is an enum, extract tag value
        var switchVal = condVal
        if cirTypeIsEnum(condType) {
            let tagType = cirEnumTypeGetTagType(condType)
            switchVal = cirBuildEnumValue(currentBlock, unknownLoc, tagType, condVal)
        }

        let mergeBlock = addBlock()

        var caseValues: [Int64] = []
        var caseBlocks: [MlirBlock] = []
        var caseStmts: [[Stmt]] = []
        var defaultBlock: MlirBlock = MlirBlock(ptr: nil)
        var defaultStmts: [Stmt] = []

        for (sc, stmts) in cases {
            let armBlock = addBlock()
            if case .expr(let e) = sc {
                if case .intLit(let v) = e {
                    caseValues.append(v)
                    caseBlocks.append(armBlock)
                    caseStmts.append(stmts)
                } else if case .memberAccess(let enumExpr, let member) = e,
                          case .ident(let enumName) = enumExpr {
                    // Look up enum variant value
                    for ei in enums {
                        if ei.name == enumName {
                            for (j, vn) in ei.variantNames.enumerated() {
                                if vn == member {
                                    caseValues.append(ei.variantValues[j])
                                    break
                                }
                            }
                            break
                        }
                    }
                    caseBlocks.append(armBlock)
                    caseStmts.append(stmts)
                }
            } else {
                defaultBlock = armBlock
                defaultStmts = stmts
            }
        }

        // Create default block if needed
        if defaultBlock.ptr == nil {
            if let db = defaultBody {
                defaultBlock = addBlock()
                defaultStmts = db
            } else {
                defaultBlock = addBlock()
                cirBuildBr(defaultBlock, unknownLoc, mergeBlock, 0, nil)
            }
        }

        // Emit switch
        caseValues.withUnsafeMutableBufferPointer { valBuf in
            caseBlocks.withUnsafeMutableBufferPointer { blockBuf in
                cirBuildSwitch(currentBlock, unknownLoc, switchVal,
                    valBuf.count,
                    valBuf.count > 0 ? valBuf.baseAddress : nil,
                    blockBuf.count > 0 ? blockBuf.baseAddress : nil,
                    defaultBlock)
            }
        }

        // Emit case bodies
        for (i, stmts) in caseStmts.enumerated() {
            currentBlock = caseBlocks[i]
            hasTerminator = false
            for stmt in stmts {
                if hasTerminator { break }
                mapStmt(stmt)
            }
            if !hasTerminator {
                cirBuildBr(currentBlock, unknownLoc, mergeBlock, 0, nil)
            }
        }

        // Emit default body
        if !defaultStmts.isEmpty {
            currentBlock = defaultBlock
            hasTerminator = false
            for stmt in defaultStmts {
                if hasTerminator { break }
                mapStmt(stmt)
            }
            if !hasTerminator {
                cirBuildBr(currentBlock, unknownLoc, mergeBlock, 0, nil)
            }
        }

        currentBlock = mergeBlock
        hasTerminator = false
    }

    // MARK: Expression codegen

    func mapExpr(_ expr: Expr, expectedType: MlirType) -> MlirValue {
        switch expr {
        case .intLit(let v):
            return cirBuildConstantInt(currentBlock, unknownLoc, expectedType, v)
        case .floatLit(let v):
            return cirBuildConstantFloat(currentBlock, unknownLoc, expectedType, v)
        case .stringLit(let s):
            return s.withCString { cstr in
                let ref = MlirStringRef(data: cstr, length: s.utf8.count)
                return cirBuildStringConstant(currentBlock, unknownLoc, ref)
            }
        case .boolLit(let v):
            return cirBuildConstantBool(currentBlock, unknownLoc, v)
        case .nilLit:
            return cirBuildConstantInt(currentBlock, unknownLoc, intType(64), 0)
        case .ident(let name):
            return lookupName(name, expectedType: expectedType)
        case .binary(let op, let lhs, let rhs):
            return mapBinary(op, lhs, rhs, expectedType: expectedType)
        case .unaryMinus(let operand):
            let val = mapExpr(operand, expectedType: expectedType)
            return cirBuildNeg(currentBlock, unknownLoc, expectedType, val)
        case .call(let name, let args):
            return mapCall(name: name, args: args, expectedType: expectedType)
        case .memberAccess(let base, let field):
            return mapMemberAccess(base: base, field: field, expectedType: expectedType)
        case .structInit(let name, let fieldInits):
            return mapStructInit(name: name, fieldInits: fieldInits)
        }
    }

    func lookupName(_ name: String, expectedType: MlirType) -> MlirValue {
        // Search locals (reverse for inner scope)
        for i in stride(from: localNames.count - 1, through: 0, by: -1) {
            if localNames[i] == name {
                return cirBuildLoad(currentBlock, unknownLoc, localTypes[i], localAddrs[i])
            }
        }
        // Search params
        for i in 0..<paramNames.count {
            if paramNames[i] == name {
                return paramValues[i]
            }
        }
        // Enum type name — return zero for now
        return cirBuildConstantInt(currentBlock, unknownLoc, expectedType, 0)
    }

    func mapBinary(_ op: BinOp, _ lhs: Expr, _ rhs: Expr, expectedType: MlirType) -> MlirValue {
        // For comparison ops, evaluate operands with i32 type, result is i1
        switch op {
        case .eq, .neq, .lt, .gt, .leq, .geq:
            // Determine operand type from context
            let operandType: MlirType
            if mlirTypeIsAInteger(expectedType) && mlirIntegerTypeGetWidth(expectedType) == 1 {
                // Expected is bool — use i32 for operands
                operandType = intType(32)
            } else {
                operandType = expectedType
            }
            var lhsVal = mapExpr(lhs, expectedType: operandType)
            var rhsVal = mapExpr(rhs, expectedType: operandType)
            // If operands are enum types, extract integer tag for comparison
            let lhsType = mlirValueGetType(lhsVal)
            let rhsType = mlirValueGetType(rhsVal)
            if cirTypeIsEnum(lhsType) {
                let tagType = cirEnumTypeGetTagType(lhsType)
                lhsVal = cirBuildEnumValue(currentBlock, unknownLoc, tagType, lhsVal)
            }
            if cirTypeIsEnum(rhsType) {
                let tagType = cirEnumTypeGetTagType(rhsType)
                rhsVal = cirBuildEnumValue(currentBlock, unknownLoc, tagType, rhsVal)
            }
            let pred: CirCmpPredicate
            switch op {
            case .eq:  pred = CIR_CMP_EQ
            case .neq: pred = CIR_CMP_NE
            case .lt:  pred = CIR_CMP_SLT
            case .gt:  pred = CIR_CMP_SGT
            case .leq: pred = CIR_CMP_SLE
            case .geq: pred = CIR_CMP_SGE
            default: fatalError()
            }
            return cirBuildCmp(currentBlock, unknownLoc, pred, lhsVal, rhsVal)
        default:
            let lhsVal = mapExpr(lhs, expectedType: expectedType)
            let rhsVal = mapExpr(rhs, expectedType: expectedType)
            return emitBinOp(op, expectedType, lhsVal, rhsVal)
        }
    }

    func emitBinOp(_ op: BinOp, _ ty: MlirType, _ lhs: MlirValue, _ rhs: MlirValue) -> MlirValue {
        let block = currentBlock
        let location = unknownLoc
        switch op {
        case .add:    return cirBuildAdd(block, location, ty, lhs, rhs)
        case .sub:    return cirBuildSub(block, location, ty, lhs, rhs)
        case .mul:    return cirBuildMul(block, location, ty, lhs, rhs)
        case .div:    return cirBuildDiv(block, location, ty, lhs, rhs)
        case .rem:    return cirBuildRem(block, location, ty, lhs, rhs)
        case .bitAnd: return cirBuildBitAnd(block, location, ty, lhs, rhs)
        case .bitOr:  return cirBuildBitOr(block, location, ty, lhs, rhs)
        case .bitXor: return cirBuildBitXor(block, location, ty, lhs, rhs)
        case .shl:    return cirBuildShl(block, location, ty, lhs, rhs)
        case .shr:    return cirBuildShr(block, location, ty, lhs, rhs)
        default:
            // Comparison ops handled in mapBinary
            return cirBuildConstantInt(block, location, ty, 0)
        }
    }

    func mapCall(name: String, args: [Expr], expectedType: MlirType) -> MlirValue {
        // Look up the function as a symbol reference and emit func.call
        var argValues: [MlirValue] = []
        // Infer argument types — use i32 as default for now
        for arg in args {
            let val = mapExpr(arg, expectedType: intType(32))
            argValues.append(val)
        }

        var resultTypes: [MlirType] = []
        if expectedType.ptr != nil {
            resultTypes.append(expectedType)
        }

        let calleeAttr: MlirAttribute = name.withCString { cstr in
            let ref = mlirStringRefCreateFromCString(cstr)
            return mlirFlatSymbolRefAttrGet(ctx, ref)
        }
        let attrs = [namedAttr("callee", calleeAttr)]

        return emit(block: currentBlock, name: "func.call",
                    resultTypes: resultTypes, operands: argValues,
                    attrs: attrs, location: unknownLoc)
    }

    func mapMemberAccess(base: Expr, field: String, expectedType: MlirType) -> MlirValue {
        // Check if base is an enum name
        if case .ident(let typeName) = base {
            for ei in enums {
                if ei.name == typeName {
                    return field.withCString { cstr in
                        let ref = mlirStringRefCreateFromCString(cstr)
                        return cirBuildEnumConstant(currentBlock, unknownLoc, ei.mlirType, ref)
                    }
                }
            }
        }

        // Struct field access
        let baseVal = mapExpr(base, expectedType: expectedType)
        let baseType = mlirValueGetType(baseVal)

        if cirTypeIsStruct(baseType) {
            for si in structs {
                if mlirTypeEqual(si.mlirType, baseType) {
                    for (j, fname) in si.fieldNames.enumerated() {
                        if fname == field {
                            return cirBuildFieldVal(currentBlock, unknownLoc,
                                si.fieldTypes[j], baseVal, Int64(j))
                        }
                    }
                }
            }
        }

        return baseVal
    }

    func mapStructInit(name: String, fieldInits: [(String, Expr)]) -> MlirValue {
        for si in structs {
            if si.name == name {
                // Build field values in struct field order
                var fieldVals: [MlirValue] = []
                for (j, fname) in si.fieldNames.enumerated() {
                    var found = false
                    for (initName, initExpr) in fieldInits {
                        if initName == fname {
                            let val = mapExpr(initExpr, expectedType: si.fieldTypes[j])
                            fieldVals.append(val)
                            found = true
                            break
                        }
                    }
                    if !found {
                        // Zero-initialize missing fields
                        fieldVals.append(cirBuildConstantInt(currentBlock, unknownLoc, si.fieldTypes[j], 0))
                    }
                }
                return fieldVals.withUnsafeMutableBufferPointer { buf in
                    return cirBuildStructInit(currentBlock, unknownLoc, si.mlirType,
                        buf.count, buf.count > 0 ? buf.baseAddress : nil)
                }
            }
        }
        // Unknown struct — return zero
        return cirBuildConstantInt(currentBlock, unknownLoc, intType(32), 0)
    }

    // MARK: Serialization

    /// Serialize the module to MLIR bytecode, returned as [UInt8].
    func serializeToBytecode() -> [UInt8]? {
        let op = mlirModuleGetOperation(module)
        let config = mlirBytecodeWriterConfigCreate()
        mlirBytecodeWriterConfigDesiredEmitVersion(config, 1)

        // Use a class to accumulate bytecode chunks from the callback
        let accumulator = BytecodeAccumulator()
        let userDataPtr = Unmanaged.passUnretained(accumulator).toOpaque()

        mlirOperationWriteBytecodeWithConfig(op, config, bytecodeCallback, userDataPtr)
        mlirBytecodeWriterConfigDestroy(config)

        return accumulator.bytes
    }
}

// Helper class for accumulating bytecode from MLIR callback
final class BytecodeAccumulator {
    var bytes: [UInt8] = []
}

// C callback function for MLIR bytecode serialization
// Matches MlirStringCallback: (MlirStringRef, void*) -> void
private func bytecodeCallback(_ ref: MlirStringRef, _ userData: UnsafeMutableRawPointer?) {
    guard let userData = userData else { return }
    let accumulator = Unmanaged<BytecodeAccumulator>.fromOpaque(userData).takeUnretainedValue()
    // ref.data is UnsafePointer<CChar>! — copy bytes to UInt8 array
    guard let dataPtr = ref.data else { return }
    for i in 0..<ref.length {
        accumulator.bytes.append(UInt8(bitPattern: dataPtr[i]))
    }
}

// =============================================================================
// MARK: - Helper: Convert Swift type to CIR type string
// =============================================================================

private func swiftTypeToString(_ ty: SwiftType) -> String {
    switch ty {
    case .named(let name):
        switch name {
        case "Int8", "UInt8":   return "i8"
        case "Int16", "UInt16": return "i16"
        case "Int32", "UInt32": return "i32"
        case "Int64", "UInt64", "Int": return "i64"
        case "Float":  return "f32"
        case "Double": return "f64"
        case "Bool":   return "i1"
        case "String": return "!cir.slice<i8>"
        case "Void":   return "i0"
        default:       return "i32"
        }
    }
}

// =============================================================================
// MARK: - Helper: Array of C strings for CIR C API
// =============================================================================

/// Execute a closure with an array of MlirStringRef values for the given strings.
private func withArrayOfCStrings<R>(_ strings: [String],
                                     _ body: ([UnsafePointer<CChar>], [MlirStringRef]) -> R) -> R {
    var cstrs: [UnsafePointer<CChar>] = []
    var refs: [MlirStringRef] = []
    var allocated: [UnsafeMutablePointer<CChar>] = []

    for s in strings {
        let cs = strdup(s)!
        allocated.append(cs)
        cstrs.append(UnsafePointer(cs))
        refs.append(MlirStringRef(data: UnsafePointer(cs), length: s.utf8.count))
    }

    let result = body(cstrs, refs)

    for p in allocated { free(p) }
    return result
}

// =============================================================================
// MARK: - Entry Point: sc_parse
// =============================================================================

/// C ABI entry point — called by cot driver, same signature as zc_parse/tc_parse.
///
/// 1. Creates MLIR context + registers CIR dialect
/// 2. Scans + parses Swift source into AST
/// 3. Walks AST, calls cirBuild* for each node
/// 4. Serializes module to MLIR bytecode, returns via output pointers
@_cdecl("sc_parse")
public func scParse(
    _ sourcePtr: UnsafePointer<CChar>,
    _ sourceLen: Int,
    _ filenamePtr: UnsafePointer<CChar>,
    _ cirOut: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>,
    _ cirLenOut: UnsafeMutablePointer<Int>
) -> Int32 {
    // Convert C inputs to Swift strings
    let sourceBuffer = UnsafeBufferPointer(start: sourcePtr, count: sourceLen)
    let source = String(decoding: sourceBuffer.lazy.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    let filename = String(cString: filenamePtr)

    // Scan
    var scanner = Scanner(source: source)
    let tokens = scanner.scanAll()

    // Parse
    var parser = Parser(tokens: tokens)
    let decls = parser.parseModule()

    // Codegen: AST -> CIR via MLIR C API
    let gen = Gen(filename: filename)
    gen.generate(decls)

    // Serialize to MLIR bytecode
    guard let bytes = gen.serializeToBytecode() else {
        gen.destroy()
        return -1
    }

    // Copy to C-allocated memory (driver manages lifetime via free())
    let buf = malloc(bytes.count)!
    memcpy(buf, bytes, bytes.count)
    cirOut.pointee = buf.assumingMemoryBound(to: CChar.self)
    cirLenOut.pointee = bytes.count

    gen.destroy()
    return 0
}
