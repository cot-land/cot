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
    case kwFor, kwIn
    case kwThrows, kwThrow, kwTry, kwDo, kwCatch

    // Range operators
    case halfOpenRange   // ..<
    case question        // ?

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
        case UInt8(ascii: "."):
            // Check for ..< (half-open range)
            if let n = peek(), n == UInt8(ascii: ".") {
                if let n2 = peekNext(), n2 == UInt8(ascii: "<") {
                    _ = advance() // .
                    _ = advance() // <
                    return Token(kind: .halfOpenRange, line: tokLine, col: tokCol)
                }
            }
            return Token(kind: .dot, line: tokLine, col: tokCol)
        case UInt8(ascii: "?"): return Token(kind: .question, line: tokLine, col: tokCol)
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
    case "for":      return .kwFor
    case "in":       return .kwIn
    case "throws":   return .kwThrows
    case "throw":    return .kwThrow
    case "try":      return .kwTry
    case "do":       return .kwDo
    case "catch":    return .kwCatch
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
    case methodCall(Expr, String, [Expr])  // expr.method(args)
    case structInit(String, [(String, Expr)]) // TypeName(field: val, ...)
    case arrayLit([Expr])                  // [1, 2, 3]
    case dotCall(String, [Expr])           // .circle(r) — enum variant init with payload
    case subscriptExpr(Expr, Expr)         // arr[i]
    case typeCast(String, Expr)            // Int32(x) — type conversion call
    case addrOf(Expr)                      // &x — address-of
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
    case ifLetStmt(String, Expr, [Stmt], [Stmt]?)   // if let val = expr { } else { }
    case whileStmt(Expr, [Stmt])
    case forInStmt(String, Expr, Expr, [Stmt])       // for i in lo..<hi { body }
    case breakStmt
    case continueStmt
    case switchStmt(Expr, [(SwitchCase, [Stmt])], [Stmt]?)
    case memberAssign(Expr, String, Expr)               // expr.field = val (for p.pointee = val)
    case throwStmt(Expr)                              // throw expr
    case doTryCatchStmt([Stmt], String?, [Stmt])      // do { try body } catch { handler }
}

enum SwitchCase {
    case expr(Expr)
    case defaultCase
}

indirect enum SwiftType {
    case named(String)           // Int32, Bool, String, MyStruct...
    case optional(SwiftType)     // Int32?
    case array(SwiftType, Int64) // [3]Int32 (fixed-size for CIR)
    case pointer(SwiftType)      // UnsafePointer<T> / UnsafeMutablePointer<T> → !cir.ref<T>
}

struct FuncParam {
    let name: String
    let type: SwiftType
}

enum Decl {
    case funcDecl(String, [FuncParam], SwiftType?, Bool, [Stmt])  // name, params, retType, throws, body
    case genericFuncDecl(String, [String], [FuncParam], SwiftType?, Bool, [Stmt])  // name, typeParams, params, retType, throws, body
    case structDecl(String, [(String, SwiftType)])
    case enumDecl(String, [(String, Int64?)])
    case taggedUnionDecl(String, [(String, SwiftType?)])          // enum with associated values
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
    // func name<T>(params) -> RetType { body }   — generic function
    // Reference: Swift generic function syntax, ac frontend monomorphization pattern
    mutating func parseFuncDecl() -> Decl? {
        _ = advance() // func
        guard let name = expectIdentifier() else { return nil }

        // Parse optional type parameters: <T> or <T, U>
        var typeParams: [String] = []
        if tokenMatches(peek(), .lt) {
            _ = advance() // <
            while !tokenMatches(peek(), .gt) && !isEof() {
                if case .identifier(let tp) = peek() {
                    _ = advance()
                    typeParams.append(tp)
                    if !tokenMatches(peek(), .gt) {
                        _ = expect(.comma)
                    }
                } else {
                    break
                }
            }
            _ = advance() // > (consume gt)
        }

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

        // Check for throws
        var doesThrow = false
        if tokenMatches(peek(), .kwThrows) {
            _ = advance() // throws
            doesThrow = true
        }

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

        if !typeParams.isEmpty {
            return .genericFuncDecl(name, typeParams, params, retType, doesThrow, body)
        }
        return .funcDecl(name, params, retType, doesThrow, body)
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
    // or enum Name { case circle(Int32); case none } (tagged union with associated values)
    mutating func parseEnumDecl() -> Decl? {
        _ = advance() // enum
        guard let name = expectIdentifier() else { return nil }

        // Optional conformance (enum MyError: Error)
        if tokenMatches(peek(), .colon) {
            _ = advance() // :
            _ = parseType() // consume conformance type (e.g. Error, Int32)
        }

        guard expect(.lBrace) else { return nil }

        // First pass: collect all variants, detecting if any have associated values
        var simpleVariants: [(String, Int64?)] = []
        var taggedVariants: [(String, SwiftType?)] = []
        var hasAssociatedValues = false

        while !tokenMatches(peek(), .rBrace) && !isEof() {
            guard expect(.kwCase) else {
                _ = advance() // skip unknown
                continue
            }
            // case name [(Type)] [= value] [, name2 ...]
            repeat {
                guard let vname = expectIdentifier() else { break }

                // Check for associated value: case circle(Int32)
                if tokenMatches(peek(), .lParen) {
                    _ = advance() // (
                    let assocType = parseType()
                    _ = expect(.rParen)
                    hasAssociatedValues = true
                    taggedVariants.append((vname, assocType))
                    simpleVariants.append((vname, nil))
                } else if tokenMatches(peek(), .assign) {
                    _ = advance() // =
                    var val: Int64? = nil
                    if case .intLiteral(let v) = peek() {
                        _ = advance()
                        val = v
                    }
                    simpleVariants.append((vname, val))
                    taggedVariants.append((vname, nil))
                } else {
                    simpleVariants.append((vname, nil))
                    taggedVariants.append((vname, nil))
                }
            } while expect(.comma)
        }
        _ = expect(.rBrace)

        if hasAssociatedValues {
            return .taggedUnionDecl(name, taggedVariants)
        }
        return .enumDecl(name, simpleVariants)
    }

    mutating func parseType() -> SwiftType? {
        // Array type: [Int32] — Swift uses this for Array<Int32>
        if tokenMatches(peek(), .lBracket) {
            _ = advance() // [
            guard let elemType = parseType() else { return nil }
            _ = expect(.rBracket) // ]
            // For CIR we need a fixed size. Use 0 as "dynamic" placeholder;
            // actual size comes from array literal context.
            return .array(elemType, 0)
        }
        if case .identifier(let s) = peek() {
            _ = advance()
            // UnsafePointer<T> / UnsafeMutablePointer<T> → pointer(T)
            if (s == "UnsafePointer" || s == "UnsafeMutablePointer"),
               tokenMatches(peek(), .lt) {
                _ = advance() // <
                guard let innerType = parseType() else { return nil }
                _ = expect(.gt) // >
                // Check for optional suffix: UnsafePointer<Int32>?
                if tokenMatches(peek(), .question) {
                    _ = advance()
                    return .optional(.pointer(innerType))
                }
                return .pointer(innerType)
            }
            // Check for optional suffix: Int32?
            if tokenMatches(peek(), .question) {
                _ = advance()
                return .optional(.named(s))
            }
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
        case .kwFor:      return parseForInStmt()
        case .kwBreak:    _ = advance(); return .breakStmt
        case .kwContinue: _ = advance(); return .continueStmt
        case .kwSwitch:   return parseSwitchStmt()
        case .kwThrow:    return parseThrowStmt()
        case .kwDo:       return parseDoTryCatchStmt()
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

        // Check for `if let val = expr { ... } else { ... }`
        if tokenMatches(peek(), .kwLet) {
            _ = advance() // let
            guard let bindName = expectIdentifier() else { return nil }
            guard expect(.assign) else { return nil }
            guard let optExpr = parseExpr() else { return nil }
            guard expect(.lBrace) else { return nil }
            let thenBody = parseStmtList()
            _ = expect(.rBrace)

            var elseBody: [Stmt]? = nil
            if tokenMatches(peek(), .kwElse) {
                _ = advance()
                guard expect(.lBrace) else { return nil }
                elseBody = parseStmtList()
                _ = expect(.rBrace)
            }
            return .ifLetStmt(bindName, optExpr, thenBody, elseBody)
        }

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

    // for i in 0..<10 { body }
    mutating func parseForInStmt() -> Stmt? {
        _ = advance() // for
        guard let varName = expectIdentifier() else { return nil }
        guard expect(.kwIn) else { return nil }
        guard let lo = parseExpr() else { return nil }
        // Expect ..< for half-open range
        guard expect(.halfOpenRange) else { return nil }
        guard let hi = parseExpr() else { return nil }
        guard expect(.lBrace) else { return nil }
        let body = parseStmtList()
        _ = expect(.rBrace)
        return .forInStmt(varName, lo, hi, body)
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

    // throw expr
    mutating func parseThrowStmt() -> Stmt? {
        _ = advance() // throw
        guard let expr = parseExpr() else { return nil }
        return .throwStmt(expr)
    }

    // do { try body } catch { handler } or do { try body } catch let e { handler }
    mutating func parseDoTryCatchStmt() -> Stmt? {
        _ = advance() // do
        guard expect(.lBrace) else { return nil }
        let tryBody = parseStmtList()
        _ = expect(.rBrace)

        // Parse catch clause
        guard tokenMatches(peek(), .kwCatch) else {
            // do block without catch — just a plain block, emit as statements
            // (shouldn't normally happen for error handling)
            return nil
        }
        _ = advance() // catch

        // Optional catch variable: catch let e { ... } or just catch { ... }
        var catchVarName: String? = nil
        if tokenMatches(peek(), .kwLet) {
            _ = advance() // let
            catchVarName = expectIdentifier()
        }

        guard expect(.lBrace) else { return nil }
        let catchBody = parseStmtList()
        _ = expect(.rBrace)

        return .doTryCatchStmt(tryBody, catchVarName, catchBody)
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
        // Check for member assignment: expr.field = val (for p.pointee = val)
        if case .memberAccess(let base, let field) = expr {
            if tokenMatches(peek(), .assign) {
                _ = advance()
                guard let rhs = parseExpr() else { return nil }
                return .memberAssign(base, field, rhs)
            }
        }
        return .exprStmt(expr)
    }

    // MARK: Expressions (precedence climbing)

    mutating func parseExpr() -> Expr? {
        // Swift `try` is a transparent prefix for error handling annotation
        if tokenMatches(peek(), .kwTry) {
            _ = advance() // try
        }
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
        // &x — address-of
        if tokenMatches(peek(), .ampersand) {
            _ = advance()
            guard let operand = parseUnary() else { return nil }
            return .addrOf(operand)
        }
        return parsePostfix()
    }

    mutating func parsePostfix() -> Expr? {
        guard var expr = parsePrimary() else { return nil }
        while true {
            if tokenMatches(peek(), .dot) {
                _ = advance()
                guard let field = expectIdentifier() else { return nil }
                // Check if it's a method call: expr.field(args)
                if tokenMatches(peek(), .lParen) {
                    _ = advance() // (
                    var args: [Expr] = []
                    while !tokenMatches(peek(), .rParen) && !isEof() {
                        guard let arg = parseExpr() else { break }
                        args.append(arg)
                        if !tokenMatches(peek(), .rParen) { _ = expect(.comma) }
                    }
                    _ = expect(.rParen)
                    expr = .methodCall(expr, field, args)
                } else {
                    expr = .memberAccess(expr, field)
                }
            } else if tokenMatches(peek(), .lBracket) {
                // Subscript: expr[index]
                _ = advance() // [
                guard let index = parseExpr() else { return nil }
                _ = expect(.rBracket)
                expr = .subscriptExpr(expr, index)
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
                // Check if this is a type cast: Int32(x), Float(x), etc.
                if isTypeCastName(name) && args.count == 1 {
                    return .typeCast(name, args[0])
                }
                return .call(name, args)
            }
            return .ident(name)
        case .lParen:
            _ = advance() // (
            let expr = parseExpr()
            _ = expect(.rParen)
            return expr
        case .lBracket:
            // Array literal: [1, 2, 3]
            _ = advance() // [
            var elements: [Expr] = []
            while !tokenMatches(peek(), .rBracket) && !isEof() {
                guard let elem = parseExpr() else { break }
                elements.append(elem)
                if !tokenMatches(peek(), .rBracket) { _ = expect(.comma) }
            }
            _ = expect(.rBracket)
            return .arrayLit(elements)
        case .dot:
            // Enum member shorthand: .red, .green — parse as memberAccess on implicit enum
            // Also handles .circle(r) — tagged union variant init
            _ = advance() // .
            guard let memberName = expectIdentifier() else { return nil }
            // Check for .circle(arg) — tagged union variant with payload
            if tokenMatches(peek(), .lParen) {
                _ = advance() // (
                var args: [Expr] = []
                while !tokenMatches(peek(), .rParen) && !isEof() {
                    guard let arg = parseExpr() else { break }
                    args.append(arg)
                    if !tokenMatches(peek(), .rParen) { _ = expect(.comma) }
                }
                _ = expect(.rParen)
                return .dotCall(memberName, args)
            }
            return .memberAccess(.ident("_enum"), memberName)
        default:
            return nil
        }
    }

    func isTypeCastName(_ name: String) -> Bool {
        switch name {
        case "Int8", "UInt8", "Int16", "UInt16", "Int32", "UInt32",
             "Int64", "UInt64", "Int", "Float", "Double":
            return true
        default:
            return false
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
    case (.kwFor, .kwFor): return true
    case (.kwIn, .kwIn): return true
    case (.kwThrows, .kwThrows): return true
    case (.kwThrow, .kwThrow): return true
    case (.kwTry, .kwTry): return true
    case (.kwDo, .kwDo): return true
    case (.kwCatch, .kwCatch): return true
    case (.halfOpenRange, .halfOpenRange): return true
    case (.question, .question): return true
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

    // Try/catch state: pending catch block for exception unwinding
    var pendingCatchBlock: MlirBlock = MlirBlock(ptr: nil)
    var pendingCatchVar: String? = nil

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

    // Tagged union type registry
    struct TaggedUnionInfo {
        let name: String
        let mlirType: MlirType
        let variantNames: [String]
        let variantTypes: [MlirType?]   // nil for variants with no payload
    }
    var taggedUnions: [TaggedUnionInfo] = []

    // Current generic type parameters (for resolving T → !cir.type_param<"T">)
    // Reference: ac frontend currentTypeParams_ pattern (libac/codegen.cpp)
    var currentTypeParams: [String] = []
    // Generic function registry — to detect generic calls at call sites
    var genericFuncNames: [String] = []
    var genericFuncTypeParams: [[String]] = []

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
            // Check if this is a generic type parameter (T → !cir.type_param<"T">)
            // Reference: ac frontend currentTypeParams_ pattern (libac/codegen.cpp)
            if currentTypeParams.contains(name) {
                return name.withCString { cstr in
                    let ref = mlirStringRefCreateFromCString(cstr)
                    return cirTypeParamGet(ctx, ref)
                }
            }
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
                // Check tagged union types
                for tu in taggedUnions {
                    if tu.name == name { return tu.mlirType }
                }
                return intType(32) // default fallback
            }
        case .optional(let inner):
            let innerType = resolveType(inner)
            return cirOptionalTypeGet(ctx, innerType)
        case .array(let elem, let size):
            let elemType = resolveType(elem)
            return cirArrayTypeGet(ctx, size, elemType)
        case .pointer(let inner):
            let innerType = resolveType(inner)
            return cirRefTypeGet(ctx, innerType)
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
        case .funcDecl(let name, let params, let retType, let doesThrow, let body):
            mapFuncDecl(name: name, params: params, retType: retType, doesThrow: doesThrow, body: body)
        case .genericFuncDecl(let name, let typeParams, let params, let retType, let doesThrow, let body):
            // Emit generic function with !cir.type_param types.
            // The GenericSpecializer pass in libcot handles monomorphization.
            // Reference: ac frontend currentTypeParams_ pattern (libac/codegen.cpp)
            let savedTypeParams = currentTypeParams
            currentTypeParams = typeParams
            // Register as generic for call-site detection
            genericFuncNames.append(name)
            genericFuncTypeParams.append(typeParams)
            mapFuncDecl(name: name, params: params, retType: retType,
                        doesThrow: doesThrow, body: body)
            // Add cir.generic_params attribute to the func op
            if !typeParams.isEmpty {
                var paramAttrs: [MlirAttribute] = []
                for tp in typeParams {
                    let attr = tp.withCString { cstr in
                        let ref = mlirStringRefCreateFromCString(cstr)
                        return mlirStringAttrGet(ctx, ref)
                    }
                    paramAttrs.append(attr)
                }
                let arrAttr = paramAttrs.withUnsafeMutableBufferPointer { buf in
                    return mlirArrayAttrGet(ctx, buf.count, buf.baseAddress)
                }
                "cir.generic_params".withCString { cstr in
                    let ref = mlirStringRefCreateFromCString(cstr)
                    mlirOperationSetAttributeByName(currentFunc, ref, arrAttr)
                }
            }
            currentTypeParams = savedTypeParams
        case .structDecl(let name, let fields):
            mapStructDecl(name: name, fields: fields)
        case .enumDecl(let name, let variants):
            mapEnumDecl(name: name, variants: variants)
        case .taggedUnionDecl(let name, let variants):
            mapTaggedUnionDecl(name: name, variants: variants)
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

    func mapTaggedUnionDecl(name: String, variants: [(String, SwiftType?)]) {
        var variantNames: [String] = []
        var variantTypes: [MlirType] = []
        var variantSwiftTypes: [MlirType?] = []

        for (vname, vtype) in variants {
            variantNames.append(vname)
            if let vt = vtype {
                let resolved = resolveType(vt)
                variantTypes.append(resolved)
                variantSwiftTypes.append(resolved)
            } else {
                // No payload — use i8 as placeholder (void variant)
                variantTypes.append(intType(8))
                variantSwiftTypes.append(nil)
            }
        }

        // Create CIR tagged union type via C API
        let unionType = withArrayOfCStrings(variantNames) { _, refs in
            var mutableRefs = refs
            return name.withCString { nameCs in
                let nameRef = mlirStringRefCreateFromCString(nameCs)
                return mutableRefs.withUnsafeMutableBufferPointer { refBuf in
                    variantTypes.withUnsafeMutableBufferPointer { typeBuf in
                        return cirTaggedUnionTypeGet(ctx, nameRef,
                            refBuf.count,
                            refBuf.count > 0 ? refBuf.baseAddress : nil,
                            typeBuf.count > 0 ? typeBuf.baseAddress : nil)
                    }
                }
            }
        }

        taggedUnions.append(TaggedUnionInfo(name: name, mlirType: unionType,
                                             variantNames: variantNames,
                                             variantTypes: variantSwiftTypes))
    }

    func mapFuncDecl(name: String, params: [FuncParam], retType: SwiftType?, doesThrow: Bool = false, body: [Stmt]) {
        let paramTypes = params.map { resolveType($0.type) }
        var returnTypes: [MlirType] = []
        if let rt = retType {
            var resolved = resolveType(rt)
            // If function throws, wrap return type in error_union
            if doesThrow {
                resolved = cirErrorUnionTypeGet(ctx, resolved)
            }
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
        case .ifLetStmt(let bindName, let optExpr, let thenBody, let elseBody):
            mapIfLetStmt(bindName: bindName, optExpr: optExpr, thenBody: thenBody, elseBody: elseBody)
        case .whileStmt(let cond, let body):
            mapWhileStmt(cond: cond, body: body)
        case .forInStmt(let varName, let lo, let hi, let body):
            mapForInStmt(varName: varName, lo: lo, hi: hi, body: body)
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
        case .memberAssign(let base, let field, let rhs):
            mapMemberAssign(base: base, field: field, rhs: rhs)
        case .throwStmt(let expr):
            mapThrowStmt(expr: expr)
        case .doTryCatchStmt(let tryBody, let catchVar, let catchBody):
            mapDoTryCatchStmt(tryBody: tryBody, catchVar: catchVar, catchBody: catchBody)
        }
    }

    func mapReturn(_ expr: Expr?) {
        if let expr = expr {
            // When returning error_union, evaluate expression with payload type
            let exprType: MlirType
            if cirTypeIsErrorUnion(currentRetType) {
                exprType = cirErrorUnionTypeGetPayload(currentRetType)
            } else {
                exprType = currentRetType
            }
            var val = mapExpr(expr, expectedType: exprType)
            // If function returns error_union and value is the payload type,
            // wrap it with wrap_result
            if cirTypeIsErrorUnion(currentRetType) {
                let valType = mlirValueGetType(val)
                if !cirTypeIsErrorUnion(valType) {
                    val = cirBuildWrapResult(currentBlock, unknownLoc, currentRetType, val)
                }
            }
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

    // throw expr → cir.throw
    func mapThrowStmt(expr: Expr) {
        let throwVal = mapExpr(expr, expectedType: intType(32))
        cirBuildThrow(currentBlock, unknownLoc, throwVal)
        hasTerminator = true
    }

    // do { try body } catch [let e] { handler }
    // Calls inside the try body are emitted as cir.invoke (with normal/unwind
    // successors). The catch block begins with cir.landingpad.
    func mapDoTryCatchStmt(tryBody: [Stmt], catchVar: String?, catchBody: [Stmt]) {
        let catchBlock = addBlock()
        let mergeBlock = addBlock()

        // Save scope state and set catch context
        let savedCatchBlock = pendingCatchBlock
        let savedCatchVar = pendingCatchVar
        pendingCatchBlock = catchBlock
        pendingCatchVar = catchVar

        // Emit try body — calls will use cir.invoke with unwind to catchBlock
        for stmt in tryBody {
            if hasTerminator { break }
            mapStmt(stmt)
        }
        let tryTerminated = hasTerminator
        if !tryTerminated {
            cirBuildBr(currentBlock, unknownLoc, mergeBlock, 0, nil)
        }

        // Restore catch context
        pendingCatchBlock = savedCatchBlock
        pendingCatchVar = savedCatchVar

        // Emit catch clause with landingpad
        currentBlock = catchBlock
        hasTerminator = false

        let exnType = intType(32)
        let exnVal = cirBuildLandingPad(catchBlock, unknownLoc, exnType)

        // Bind catch variable if present
        if let varName = catchVar {
            let addr = cirBuildAlloca(currentBlock, unknownLoc, exnType)
            cirBuildStore(currentBlock, unknownLoc, exnVal, addr)
            localNames.append(varName)
            localAddrs.append(addr)
            localTypes.append(exnType)
        }

        for stmt in catchBody {
            if hasTerminator { break }
            mapStmt(stmt)
        }
        let catchTerminated = hasTerminator
        if !catchTerminated {
            cirBuildBr(currentBlock, unknownLoc, mergeBlock, 0, nil)
        }

        currentBlock = mergeBlock
        if tryTerminated && catchTerminated {
            cirBuildTrap(mergeBlock, unknownLoc)
            hasTerminator = true
        } else {
            hasTerminator = false
        }
    }

    func mapVarBinding(name: String, ty: SwiftType?, init_: Expr?) {
        var varType: MlirType
        if let ty = ty {
            // Special case: [T] with array literal — infer size from literal
            if case .array(let elemTy, let sz) = ty, sz == 0,
               let init_ = init_, case .arrayLit(let elems) = init_ {
                varType = resolveType(.array(elemTy, Int64(elems.count)))
            } else {
                varType = resolveType(ty)
            }
        } else {
            varType = intType(32)
        }

        let addr = cirBuildAlloca(currentBlock, unknownLoc, varType)

        if let init_ = init_ {
            // Special case: nil literal for optional types
            if case .nilLit = init_, cirTypeIsOptional(varType) {
                let noneVal = cirBuildNone(currentBlock, unknownLoc, varType)
                cirBuildStore(currentBlock, unknownLoc, noneVal, addr)
            } else if cirTypeIsOptional(varType) {
                // Wrapping a non-nil value into optional
                let payloadType = cirOptionalTypeGetPayload(varType)
                let innerVal = mapExpr(init_, expectedType: payloadType)
                let wrapped = cirBuildWrapOptional(currentBlock, unknownLoc, varType, innerVal)
                cirBuildStore(currentBlock, unknownLoc, wrapped, addr)
            } else {
                let val = mapExpr(init_, expectedType: varType)
                cirBuildStore(currentBlock, unknownLoc, val, addr)
            }
        }

        localNames.append(name)
        localAddrs.append(addr)
        localTypes.append(varType)
    }

    func mapAssign(name: String, expr: Expr) {
        for i in stride(from: localNames.count - 1, through: 0, by: -1) {
            if localNames[i] == name {
                let varType = localTypes[i]
                if cirTypeIsOptional(varType) {
                    // Check if assigning nil
                    if case .nilLit = expr {
                        let noneVal = cirBuildNone(currentBlock, unknownLoc, varType)
                        cirBuildStore(currentBlock, unknownLoc, noneVal, localAddrs[i])
                    } else {
                        // Wrap value into optional
                        let payloadType = cirOptionalTypeGetPayload(varType)
                        let innerVal = mapExpr(expr, expectedType: payloadType)
                        let wrapped = cirBuildWrapOptional(currentBlock, unknownLoc, varType, innerVal)
                        cirBuildStore(currentBlock, unknownLoc, wrapped, localAddrs[i])
                    }
                } else {
                    let val = mapExpr(expr, expectedType: varType)
                    cirBuildStore(currentBlock, unknownLoc, val, localAddrs[i])
                }
                return
            }
        }
    }

    // p.pointee = val → store through pointer
    func mapMemberAssign(base: Expr, field: String, rhs: Expr) {
        if field == "pointee" {
            // base should resolve to a !cir.ref<T> value
            // We need the pointer value, then store rhs through it
            let ptrVal = mapExpr(base, expectedType: intType(32))
            let ptrType = mlirValueGetType(ptrVal)
            if cirTypeIsRef(ptrType) {
                let pointeeType = cirRefTypeGetPointee(ptrType)
                let rhsVal = mapExpr(rhs, expectedType: pointeeType)
                cirBuildStore(currentBlock, unknownLoc, rhsVal, ptrVal)
            }
            return
        }
        // General struct field assignment could go here
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

    // for i in lo..<hi { body } => lowered as while loop
    func mapForInStmt(varName: String, lo: Expr, hi: Expr, body: [Stmt]) {
        let loopType = intType(32)

        // Allocate loop variable, initialize to lo
        let addr = cirBuildAlloca(currentBlock, unknownLoc, loopType)
        let loVal = mapExpr(lo, expectedType: loopType)
        cirBuildStore(currentBlock, unknownLoc, loVal, addr)

        localNames.append(varName)
        localAddrs.append(addr)
        localTypes.append(loopType)

        let headerBlock = addBlock()
        let bodyBlock = addBlock()
        let exitBlock = addBlock()

        cirBuildBr(currentBlock, unknownLoc, headerBlock, 0, nil)

        // Header: check i < hi
        currentBlock = headerBlock
        let curVal = cirBuildLoad(currentBlock, unknownLoc, loopType, addr)
        let hiVal = mapExpr(hi, expectedType: loopType)
        let condVal = cirBuildCmp(currentBlock, unknownLoc, CIR_CMP_SLT, curVal, hiVal)
        cirBuildCondBr(headerBlock, unknownLoc, condVal, bodyBlock, exitBlock)

        // Body
        loopStack.append(LoopCtx(header: headerBlock, exit: exitBlock))
        currentBlock = bodyBlock
        hasTerminator = false
        for stmt in body {
            if hasTerminator { break }
            mapStmt(stmt)
        }
        // Increment: i = i + 1
        if !hasTerminator {
            let current = cirBuildLoad(currentBlock, unknownLoc, loopType, addr)
            let one = cirBuildConstantInt(currentBlock, unknownLoc, loopType, 1)
            let next = cirBuildAdd(currentBlock, unknownLoc, loopType, current, one)
            cirBuildStore(currentBlock, unknownLoc, next, addr)
            cirBuildBr(currentBlock, unknownLoc, headerBlock, 0, nil)
        }
        loopStack.removeLast()

        currentBlock = exitBlock
        hasTerminator = false
    }

    // if let val = optExpr { thenBody } else { elseBody }
    func mapIfLetStmt(bindName: String, optExpr: Expr, thenBody: [Stmt], elseBody: [Stmt]?) {
        // Evaluate the optional expression
        let optVal = mapExpr(optExpr, expectedType: intType(64))
        let optType = mlirValueGetType(optVal)

        // Check if non-null
        let condVal = cirBuildIsNonNull(currentBlock, unknownLoc, optVal)

        let thenBlock = addBlock()
        let elseBlock = addBlock()
        let mergeBlock = addBlock()

        cirBuildCondBr(currentBlock, unknownLoc, condVal, thenBlock, elseBlock)

        // Then branch: extract payload, bind to name
        currentBlock = thenBlock
        hasTerminator = false
        let payloadType: MlirType
        if cirTypeIsOptional(optType) {
            payloadType = cirOptionalTypeGetPayload(optType)
        } else {
            payloadType = intType(32)
        }
        let payload = cirBuildOptionalPayload(currentBlock, unknownLoc, payloadType, optVal)

        // Create local for the bound name
        let addr = cirBuildAlloca(currentBlock, unknownLoc, payloadType)
        cirBuildStore(currentBlock, unknownLoc, payload, addr)
        localNames.append(bindName)
        localAddrs.append(addr)
        localTypes.append(payloadType)

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
                    // If enumName is "_enum", infer from switch discriminant type
                    var lookupEnumName = enumName
                    if enumName == "_enum" && cirTypeIsEnum(condType) {
                        for ei in enums {
                            if mlirTypeEqual(ei.mlirType, condType) {
                                lookupEnumName = ei.name
                                break
                            }
                        }
                    }
                    for ei in enums {
                        if ei.name == lookupEnumName {
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
        var allTerminated = true
        for (i, stmts) in caseStmts.enumerated() {
            currentBlock = caseBlocks[i]
            hasTerminator = false
            for stmt in stmts {
                if hasTerminator { break }
                mapStmt(stmt)
            }
            if !hasTerminator {
                cirBuildBr(currentBlock, unknownLoc, mergeBlock, 0, nil)
                allTerminated = false
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
                allTerminated = false
            }
        } else {
            allTerminated = false // default falls through
        }

        currentBlock = mergeBlock
        if allTerminated {
            cirBuildTrap(mergeBlock, unknownLoc)
            hasTerminator = true
        } else {
            hasTerminator = false
        }
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
        case .methodCall(let base, let method, let args):
            return mapMethodCall(base: base, method: method, args: args, expectedType: expectedType)
        case .structInit(let name, let fieldInits):
            return mapStructInit(name: name, fieldInits: fieldInits)
        case .arrayLit(let elements):
            return mapArrayLit(elements: elements, expectedType: expectedType)
        case .subscriptExpr(let base, let index):
            return mapSubscript(base: base, index: index, expectedType: expectedType)
        case .typeCast(let targetType, let inner):
            return mapTypeCast(targetType: targetType, inner: inner)
        case .dotCall(let variant, let args):
            return mapDotCall(variant: variant, args: args, expectedType: expectedType)
        case .addrOf(let operand):
            return mapAddrOf(operand: operand)
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
        // Check if callee is a generic function — emit cir.generic_apply
        // Reference: ac frontend GenericCall handling in libac/codegen.cpp
        // Frontends emit cir.generic_apply; GenericSpecializer pass monomorphizes.
        if let idx = genericFuncNames.firstIndex(of: name) {
            let typeParams = genericFuncTypeParams[idx]
            // Infer type arguments from call site:
            // Use the expected return type to determine T
            let inferredType = expectedType

            // Emit call arguments
            var argValues: [MlirValue] = []
            for arg in args {
                let val = mapExpr(arg, expectedType: expectedType)
                argValues.append(val)
            }

            // Emit cir.generic_apply
            var subsTypes: [MlirType] = Array(repeating: inferredType, count: typeParams.count)
            let nSubs = typeParams.count
            // Allocate stable C string storage for callee + type param names
            let calleePtr = strdup(name)!
            let keyPtrs: [UnsafeMutablePointer<CChar>] = typeParams.map { strdup($0)! }
            var subsKeys: [MlirStringRef] = keyPtrs.enumerated().map { (i, ptr) in
                MlirStringRef(data: ptr, length: typeParams[i].utf8.count)
            }
            let calleeRef = MlirStringRef(data: calleePtr, length: name.utf8.count)
            let result = argValues.withUnsafeMutableBufferPointer { argBuf in
                subsKeys.withUnsafeMutableBufferPointer { keyBuf in
                    subsTypes.withUnsafeMutableBufferPointer { typeBuf in
                        return cirBuildGenericApply(
                            currentBlock, unknownLoc, calleeRef,
                            argBuf.count,
                            argBuf.count > 0 ? argBuf.baseAddress : nil,
                            expectedType,
                            nSubs,
                            nSubs > 0 ? keyBuf.baseAddress : nil,
                            nSubs > 0 ? typeBuf.baseAddress : nil)
                    }
                }
            }
            free(calleePtr)
            for ptr in keyPtrs { free(ptr) }
            return result
        }

        // Non-generic function call
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

        // If inside a try block, emit cir.invoke with normal/unwind successors
        if pendingCatchBlock.ptr != nil {
            let normalBlock = addBlock()
            let resultType = resultTypes.isEmpty ? intType(32) : resultTypes[0]
            let callResult = name.withCString { cstr in
                let ref = MlirStringRef(data: cstr, length: name.utf8.count)
                return argValues.withUnsafeMutableBufferPointer { argBuf in
                    return cirBuildInvoke(currentBlock, unknownLoc, ref,
                        argBuf.count, argBuf.count > 0 ? argBuf.baseAddress : nil,
                        resultType, normalBlock, pendingCatchBlock)
                }
            }
            currentBlock = normalBlock
            return callResult
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
        // p.pointee → cir.deref (pointer dereference)
        if field == "pointee" {
            let ptrVal = mapExpr(base, expectedType: expectedType)
            let ptrType = mlirValueGetType(ptrVal)
            if cirTypeIsRef(ptrType) {
                let pointeeType = cirRefTypeGetPointee(ptrType)
                return cirBuildDeref(currentBlock, unknownLoc, pointeeType, ptrVal)
            }
            // Fallback: treat as regular deref with expected type
            return cirBuildDeref(currentBlock, unknownLoc, expectedType, ptrVal)
        }

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
            // Check tagged unions: Shape.none → cirBuildUnionInitVoid
            for tu in taggedUnions {
                if tu.name == typeName {
                    return field.withCString { cstr in
                        let ref = MlirStringRef(data: cstr, length: field.utf8.count)
                        return cirBuildUnionInitVoid(currentBlock, unknownLoc, tu.mlirType, ref)
                    }
                }
            }
        }

        // Handle implicit enum base (_enum) — also try tagged unions
        if case .ident(let typeName) = base, typeName == "_enum" {
            // If expectedType is a tagged union, use union_init_void
            for tu in taggedUnions {
                if mlirTypeEqual(tu.mlirType, expectedType) || cirTypeIsTaggedUnion(expectedType) {
                    return field.withCString { cstr in
                        let ref = MlirStringRef(data: cstr, length: field.utf8.count)
                        return cirBuildUnionInitVoid(currentBlock, unknownLoc, tu.mlirType, ref)
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

    func mapMethodCall(base: Expr, method: String, args: [Expr],
                       expectedType: MlirType) -> MlirValue {
        // Method call: p.distance() => call @distance(p)
        let baseVal = mapExpr(base, expectedType: intType(32))
        var allArgs = [baseVal]
        for arg in args {
            allArgs.append(mapExpr(arg, expectedType: intType(32)))
        }

        var resultTypes: [MlirType] = []
        if expectedType.ptr != nil {
            resultTypes.append(expectedType)
        }

        let calleeAttr: MlirAttribute = method.withCString { cstr in
            let ref = mlirStringRefCreateFromCString(cstr)
            return mlirFlatSymbolRefAttrGet(ctx, ref)
        }
        let attrs = [namedAttr("callee", calleeAttr)]

        return emit(block: currentBlock, name: "func.call",
                    resultTypes: resultTypes, operands: allArgs,
                    attrs: attrs, location: unknownLoc)
    }

    func mapArrayLit(elements: [Expr], expectedType: MlirType) -> MlirValue {
        // Determine element type from expected type or default i32
        let elemType: MlirType
        if cirTypeIsArray(expectedType) {
            elemType = cirArrayTypeGetElementType(expectedType)
        } else {
            elemType = intType(32)
        }
        let count = Int64(elements.count)
        let arrType = cirArrayTypeGet(ctx, count, elemType)

        var elemVals: [MlirValue] = []
        for elem in elements {
            elemVals.append(mapExpr(elem, expectedType: elemType))
        }

        return elemVals.withUnsafeMutableBufferPointer { buf in
            return cirBuildArrayInit(currentBlock, unknownLoc, arrType,
                buf.count, buf.count > 0 ? buf.baseAddress : nil)
        }
    }

    func mapSubscript(base: Expr, index: Expr, expectedType: MlirType) -> MlirValue {
        let baseVal = mapExpr(base, expectedType: expectedType)
        let baseType = mlirValueGetType(baseVal)

        if cirTypeIsArray(baseType) {
            let elemType = cirArrayTypeGetElementType(baseType)
            // cirBuildElemVal takes static int64_t index
            if case .intLit(let idx) = index {
                return cirBuildElemVal(currentBlock, unknownLoc, elemType, baseVal, idx)
            }
            // For runtime index, evaluate and use elem_ptr + load
            let indexVal = mapExpr(index, expectedType: intType(64))
            let elemPtr = cirBuildElemPtr(currentBlock, unknownLoc, baseVal, indexVal, elemType)
            return cirBuildLoad(currentBlock, unknownLoc, elemType, elemPtr)
        }

        // Fallback
        return baseVal
    }

    func mapTypeCast(targetType: String, inner: Expr) -> MlirValue {
        let destType: MlirType
        switch targetType {
        case "Int8", "UInt8":   destType = intType(8)
        case "Int16", "UInt16": destType = intType(16)
        case "Int32", "UInt32": destType = intType(32)
        case "Int64", "UInt64", "Int": destType = intType(64)
        case "Float":  destType = f32Type()
        case "Double": destType = f64Type()
        default: destType = intType(32)
        }

        // Evaluate the inner expression with a compatible source type
        let srcVal = mapExpr(inner, expectedType: destType)
        let srcType = mlirValueGetType(srcVal)

        // Integer -> Integer
        if mlirTypeIsAInteger(srcType) && mlirTypeIsAInteger(destType) {
            let srcW = mlirIntegerTypeGetWidth(srcType)
            let dstW = mlirIntegerTypeGetWidth(destType)
            if srcW == dstW { return srcVal }
            if srcW < dstW {
                return cirBuildExtSI(currentBlock, unknownLoc, destType, srcVal)
            } else {
                return cirBuildTruncI(currentBlock, unknownLoc, destType, srcVal)
            }
        }

        // Integer -> Float
        if mlirTypeIsAInteger(srcType) && mlirTypeIsAFloat(destType) {
            return cirBuildSIToFP(currentBlock, unknownLoc, destType, srcVal)
        }

        // Float -> Integer
        if mlirTypeIsAFloat(srcType) && mlirTypeIsAInteger(destType) {
            return cirBuildFPToSI(currentBlock, unknownLoc, destType, srcVal)
        }

        // Float -> Float
        if mlirTypeIsAFloat(srcType) && mlirTypeIsAFloat(destType) {
            let srcBits = mlirFloatTypeGetWidth(srcType)
            let dstBits = mlirFloatTypeGetWidth(destType)
            if srcBits < dstBits {
                return cirBuildExtF(currentBlock, unknownLoc, destType, srcVal)
            } else if srcBits > dstBits {
                return cirBuildTruncF(currentBlock, unknownLoc, destType, srcVal)
            }
        }

        return srcVal
    }

    // .circle(r) → cir.union_init on inferred tagged union type from expectedType
    func mapDotCall(variant: String, args: [Expr], expectedType: MlirType) -> MlirValue {
        // Find the tagged union type that matches expectedType
        for tu in taggedUnions {
            if mlirTypeEqual(tu.mlirType, expectedType) || cirTypeIsTaggedUnion(expectedType) {
                // Find variant type
                for (i, vname) in tu.variantNames.enumerated() {
                    if vname == variant {
                        if let payloadType = tu.variantTypes[i], !args.isEmpty {
                            // Variant with payload
                            let payloadVal = mapExpr(args[0], expectedType: payloadType)
                            return variant.withCString { cstr in
                                let ref = MlirStringRef(data: cstr, length: variant.utf8.count)
                                return cirBuildUnionInit(currentBlock, unknownLoc,
                                    tu.mlirType, ref, payloadVal)
                            }
                        } else {
                            // Variant without payload (void)
                            return variant.withCString { cstr in
                                let ref = MlirStringRef(data: cstr, length: variant.utf8.count)
                                return cirBuildUnionInitVoid(currentBlock, unknownLoc,
                                    tu.mlirType, ref)
                            }
                        }
                    }
                }
            }
        }

        // Fallback: look at all tagged unions for a matching variant name
        for tu in taggedUnions {
            for (i, vname) in tu.variantNames.enumerated() {
                if vname == variant {
                    if let payloadType = tu.variantTypes[i], !args.isEmpty {
                        let payloadVal = mapExpr(args[0], expectedType: payloadType)
                        return variant.withCString { cstr in
                            let ref = MlirStringRef(data: cstr, length: variant.utf8.count)
                            return cirBuildUnionInit(currentBlock, unknownLoc,
                                tu.mlirType, ref, payloadVal)
                        }
                    } else {
                        return variant.withCString { cstr in
                            let ref = MlirStringRef(data: cstr, length: variant.utf8.count)
                            return cirBuildUnionInitVoid(currentBlock, unknownLoc,
                                tu.mlirType, ref)
                        }
                    }
                }
            }
        }

        // Unknown variant — return zero constant
        return cirBuildConstantInt(currentBlock, unknownLoc, intType(32), 0)
    }

    // &x → cir.addr_of (address-of operator)
    func mapAddrOf(operand: Expr) -> MlirValue {
        if case .ident(let name) = operand {
            // Look up as local variable — get its alloca address
            for i in stride(from: localNames.count - 1, through: 0, by: -1) {
                if localNames[i] == name {
                    let refType = cirRefTypeGet(ctx, localTypes[i])
                    return cirBuildAddrOf(currentBlock, unknownLoc, refType, localAddrs[i])
                }
            }
        }
        // Fallback: evaluate operand and return it
        return mapExpr(operand, expectedType: intType(32))
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
    case .optional(let inner):
        return "!cir.optional<\(swiftTypeToString(inner))>"
    case .array(let elem, let size):
        return "!cir.array<\(size) x \(swiftTypeToString(elem))>"
    case .pointer(let inner):
        return "!cir.ref<\(swiftTypeToString(inner))>"
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
