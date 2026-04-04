//===- parser.h - ac language parser ----------------------------*- C++ -*-===//
#ifndef AC_PARSER_H
#define AC_PARSER_H
// Parser for the ac language.
//
// Architecture: Go parser recursive descent + Zig precedence table
//   ~/claude/references/go/src/go/parser/parser.go (2,962 lines)
//   ~/claude/references/zig/lib/std/zig/Parse.zig (3,725 lines)

#include "scanner.h"
#include <memory>
#include <vector>

namespace ac {

struct Expr;
struct Stmt;
using ExprPtr = std::unique_ptr<Expr>;
using StmtPtr = std::unique_ptr<Stmt>;

struct TypeRef {
  std::string_view name; // "i32", "void", etc. — view into source
  int64_t arraySize = 0; // >0 for array types: [N]T
  std::string_view arrayElemType; // element type name for arrays
  bool isRef = false; // true for pointer/ref types: *T
};

struct Param {
  std::string_view name;
  TypeRef type;
};

// Expression kinds
enum class ExprKind { IntLit, FloatLit, BoolLit, Ident, BinOp, UnaryOp, Call, IfExpr, Cast, StructInit, FieldAccess, MethodCall, ArrayLit, IndexAccess };

struct Expr {
  ExprKind kind;
  size_t pos; // byte offset in source

  int64_t intVal = 0;            // IntLit
  double floatVal = 0.0;         // FloatLit
  bool boolVal = false;           // BoolLit
  std::string_view name;          // Ident, Call (callee)
  Tag op = Tag::invalid;          // BinOp, UnaryOp
  ExprPtr lhs, rhs;              // BinOp (lhs, rhs), UnaryOp (rhs only)
  std::vector<ExprPtr> args;     // Call
  TypeRef targetType;             // Cast: target type (x as i64)
  std::vector<std::string_view> fieldNames; // StructInit: field names
};

// Statement kinds
enum class StmtKind { Return, ExprStmt, If, While, For, Break, Continue, Assert, Let, Var, Assign, CompoundAssign };

struct Stmt {
  StmtKind kind;
  size_t pos;
  ExprPtr expr;                   // Return value, ExprStmt expr, If condition, Assert condition
  std::vector<StmtPtr> thenBody;  // If then block
  std::vector<StmtPtr> elseBody;  // If else block
  std::string_view varName;       // Let/Var/Assign/CompoundAssign/For: variable name
  TypeRef varType;                // Let/Var: type annotation
  Tag op = Tag::invalid;          // CompoundAssign: operator (+= → plus, etc.)
  ExprPtr rangeEnd;               // For: end of range
};

struct StructField {
  std::string_view name;
  TypeRef type;
};

struct StructDecl {
  std::string_view name;
  std::vector<StructField> fields;
  size_t pos;
};

struct FnDecl {
  std::string_view name;
  std::vector<Param> params;
  TypeRef returnType;
  std::vector<StmtPtr> body;
  size_t pos;
};

struct TestDecl {
  std::string_view name;          // test name from string literal
  std::vector<StmtPtr> body;
  size_t pos;
};

struct Module {
  std::vector<FnDecl> functions;
  std::vector<TestDecl> tests;
  std::vector<StructDecl> structs;
};

Module parse(std::string_view source, const std::vector<Token> &tokens);

} // namespace ac

#endif // AC_PARSER_H
