// Codegen for the ac language: AST → CIR MLIR ops.
//
// Architecture ported from:
//   Zig AstGen — single-pass recursive dispatch over AST node kinds
//     ~/claude/references/zig/lib/std/zig/AstGen.zig (13,664 lines)
//
// Zig's AstGen pattern:
//   1. Walk AST nodes via big switch on node tag
//   2. Emit IR instructions for each node
//   3. Scope tracking via linked chain (GenZir → parent GenZir)
//   4. Types are unresolved references (resolved later by Sema)
//
// For gate test 1, we have fully explicit types (i32 in source).
// Type resolution pass will be needed when we add inference.

#include "codegen.h"
#include "CIR/CIROps.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/IR/Builders.h"

#include <unordered_map>

namespace ac {

class CodeGen {
  mlir::OpBuilder b;
  mlir::Location loc;
  std::string_view source_;

  // Zig AstGen pattern: scope holds named values for current function.
  // Zig uses a linked-list scope chain (GenZir → parent). For now, flat map suffices.
  // params: SSA value (direct), locals: SSA address (needs cir.load)
  std::unordered_map<std::string_view, mlir::Value> namedValues;
  std::unordered_map<std::string_view, std::pair<mlir::Value, mlir::Type>> localAddrs;

  mlir::Type resolveType(const TypeRef &t) {
    if (t.name == "i32") return b.getI32Type();
    if (t.name == "i64") return b.getI64Type();
    if (t.name == "f32") return b.getF32Type();
    if (t.name == "f64") return b.getF64Type();
    if (t.name == "bool") return b.getI1Type();
    return b.getI32Type();
  }

  // Zig AstGen pattern: expr() dispatches on node kind, returns IR value.
  mlir::Value emitExpr(const Expr &e, mlir::Type resultType) {
    switch (e.kind) {
    case ExprKind::IntLit:
      return b.create<cir::ConstantOp>(loc, resultType,
          b.getIntegerAttr(resultType, e.intVal));

    case ExprKind::BoolLit:
      return b.create<cir::ConstantOp>(loc, resultType,
          b.getIntegerAttr(resultType, e.boolVal ? 1 : 0));

    case ExprKind::Ident: {
      // Check locals first (let bindings — stored as addresses, need load)
      auto lit = localAddrs.find(e.name);
      if (lit != localAddrs.end()) {
        auto [addr, elemType] = lit->second;
        return b.create<cir::LoadOp>(loc, elemType, addr);
      }
      // Then params (direct SSA values)
      auto it = namedValues.find(e.name);
      if (it == namedValues.end()) {
        llvm::errs() << "error: undefined '" << e.name << "'\n";
        return {};
      }
      return it->second;
    }

    case ExprKind::BinOp: {
      // Comparisons return i1, operands use their own type
      bool isCmp = (e.op == Tag::eq_eq || e.op == Tag::bang_eq ||
                    e.op == Tag::less || e.op == Tag::less_eq ||
                    e.op == Tag::greater || e.op == Tag::greater_eq);
      mlir::Type operandType = isCmp ? b.getI32Type() : resultType;
      auto lhs = emitExpr(*e.lhs, operandType);
      auto rhs = emitExpr(*e.rhs, operandType);
      switch (e.op) {
        case Tag::plus:    return b.create<cir::AddOp>(loc, resultType, lhs, rhs);
        case Tag::minus:   return b.create<cir::SubOp>(loc, resultType, lhs, rhs);
        case Tag::star:    return b.create<cir::MulOp>(loc, resultType, lhs, rhs);
        case Tag::slash:   return b.create<cir::DivOp>(loc, resultType, lhs, rhs);
        case Tag::percent: return b.create<cir::RemOp>(loc, resultType, lhs, rhs);
        case Tag::ampersand: return b.create<cir::BitAndOp>(loc, resultType, lhs, rhs);
        case Tag::pipe:      return b.create<cir::BitOrOp>(loc, resultType, lhs, rhs);
        case Tag::caret:     return b.create<cir::XorOp>(loc, resultType, lhs, rhs);
        case Tag::shl:       return b.create<cir::ShlOp>(loc, resultType, lhs, rhs);
        case Tag::shr:       return b.create<cir::ShrOp>(loc, resultType, lhs, rhs);
        // Comparisons: cir::CmpIPredicate enum
        case Tag::eq_eq:      return b.create<cir::CmpOp>(loc, cir::CmpIPredicate::eq, lhs, rhs);
        case Tag::bang_eq:    return b.create<cir::CmpOp>(loc, cir::CmpIPredicate::ne, lhs, rhs);
        case Tag::less:       return b.create<cir::CmpOp>(loc, cir::CmpIPredicate::slt, lhs, rhs);
        case Tag::less_eq:    return b.create<cir::CmpOp>(loc, cir::CmpIPredicate::sle, lhs, rhs);
        case Tag::greater:    return b.create<cir::CmpOp>(loc, cir::CmpIPredicate::sgt, lhs, rhs);
        case Tag::greater_eq: return b.create<cir::CmpOp>(loc, cir::CmpIPredicate::sge, lhs, rhs);
        default:
          llvm::errs() << "error: unsupported binary op\n";
          return {};
      }
    }

    case ExprKind::UnaryOp: {
      auto operand = emitExpr(*e.rhs, resultType);
      if (e.op == Tag::minus)
        return b.create<cir::NegOp>(loc, resultType, operand);
      if (e.op == Tag::tilde)
        return b.create<cir::BitNotOp>(loc, resultType, operand);
      if (e.op == Tag::bang) {
        // Logical NOT: xor with 1 (for booleans)
        auto one = b.create<cir::ConstantOp>(loc, resultType,
            b.getIntegerAttr(resultType, 1));
        return b.create<cir::XorOp>(loc, resultType, operand, one);
      }
      llvm::errs() << "error: unsupported unary op\n";
      return {};
    }

    case ExprKind::Call: {
      llvm::SmallVector<mlir::Value> args;
      for (auto &arg : e.args)
        args.push_back(emitExpr(*arg, resultType));
      std::string callee(e.name);
      auto call = b.create<mlir::func::CallOp>(loc, callee,
          mlir::TypeRange{resultType}, mlir::ValueRange(args));
      return call.getResult(0);
    }

    case ExprKind::FloatLit:
      return b.create<cir::ConstantOp>(loc, resultType,
          b.getFloatAttr(resultType, e.floatVal));
    }
    return {};
  }

  void emitStmt(const Stmt &s, mlir::Type returnType, mlir::func::FuncOp parentFunc) {
    switch (s.kind) {
    case StmtKind::Return:
      if (s.expr) {
        auto val = emitExpr(*s.expr, returnType);
        b.create<mlir::func::ReturnOp>(loc, mlir::ValueRange{val});
      } else {
        b.create<mlir::func::ReturnOp>(loc, mlir::ValueRange{});
      }
      break;

    case StmtKind::ExprStmt:
      if (s.expr) emitExpr(*s.expr, returnType);
      break;

    case StmtKind::Let:
    case StmtKind::Var: {
      auto varType = resolveType(s.varType);
      auto ptrType = cir::PointerType::get(b.getContext());
      auto addr = b.create<cir::AllocaOp>(loc, ptrType,
          mlir::TypeAttr::get(varType));
      auto val = emitExpr(*s.expr, varType);
      b.create<cir::StoreOp>(loc, val, addr);
      localAddrs[s.varName] = {addr, varType};
      break;
    }

    case StmtKind::Assign: {
      auto lit = localAddrs.find(s.varName);
      if (lit == localAddrs.end()) {
        llvm::errs() << "error: undefined variable '" << s.varName << "'\n";
        break;
      }
      auto [addr, elemType] = lit->second;
      auto val = emitExpr(*s.expr, elemType);
      b.create<cir::StoreOp>(loc, val, addr);
      break;
    }

    case StmtKind::CompoundAssign: {
      auto lit = localAddrs.find(s.varName);
      if (lit == localAddrs.end()) {
        llvm::errs() << "error: undefined variable '" << s.varName << "'\n";
        break;
      }
      auto [addr, elemType] = lit->second;
      auto current = b.create<cir::LoadOp>(loc, elemType, addr);
      auto rhs = emitExpr(*s.expr, elemType);
      mlir::Value result;
      switch (s.op) {
        case Tag::plus:    result = b.create<cir::AddOp>(loc, elemType, current, rhs); break;
        case Tag::minus:   result = b.create<cir::SubOp>(loc, elemType, current, rhs); break;
        case Tag::star:    result = b.create<cir::MulOp>(loc, elemType, current, rhs); break;
        case Tag::slash:   result = b.create<cir::DivOp>(loc, elemType, current, rhs); break;
        case Tag::percent: result = b.create<cir::RemOp>(loc, elemType, current, rhs); break;
        default: llvm::errs() << "error: unsupported compound op\n"; break;
      }
      b.create<cir::StoreOp>(loc, result, addr);
      break;
    }

    case StmtKind::Assert: {
      // Zig pattern: assert condition, trap on failure.
      // Emit: if (!cond) { cir.trap }
      auto cond = emitExpr(*s.expr, b.getI1Type());
      auto *trapBlock = new mlir::Block();
      auto *contBlock = new mlir::Block();
      parentFunc.getBody().push_back(trapBlock);
      parentFunc.getBody().push_back(contBlock);
      b.create<cir::CondBrOp>(loc, cond, contBlock, trapBlock);
      b.setInsertionPointToStart(trapBlock);
      b.create<cir::TrapOp>(loc);
      b.setInsertionPointToStart(contBlock);
      break;
    }

    case StmtKind::If: {
      auto cond = emitExpr(*s.expr, b.getI1Type());
      auto *thenBlock = new mlir::Block();
      auto *elseBlock = new mlir::Block();
      auto *mergeBlock = new mlir::Block();
      parentFunc.getBody().push_back(thenBlock);
      parentFunc.getBody().push_back(elseBlock);
      parentFunc.getBody().push_back(mergeBlock);
      b.create<cir::CondBrOp>(loc, cond, thenBlock, elseBlock);
      // Then
      b.setInsertionPointToStart(thenBlock);
      for (auto &st : s.thenBody) emitStmt(*st, returnType, parentFunc);
      if (thenBlock->empty() || !thenBlock->back().hasTrait<mlir::OpTrait::IsTerminator>())
        b.create<cir::BrOp>(loc, mergeBlock);
      // Else
      b.setInsertionPointToStart(elseBlock);
      for (auto &st : s.elseBody) emitStmt(*st, returnType, parentFunc);
      if (elseBlock->empty() || !elseBlock->back().hasTrait<mlir::OpTrait::IsTerminator>())
        b.create<cir::BrOp>(loc, mergeBlock);
      // Merge — if both branches terminated, merge is unreachable
      b.setInsertionPointToStart(mergeBlock);
      bool thenDone = !thenBlock->empty() &&
          thenBlock->back().hasTrait<mlir::OpTrait::IsTerminator>();
      bool elseDone = !elseBlock->empty() &&
          elseBlock->back().hasTrait<mlir::OpTrait::IsTerminator>();
      if (thenDone && elseDone)
        b.create<cir::TrapOp>(loc);
      break;
    }
    }
  }

  void emitFn(mlir::ModuleOp module, const FnDecl &fn) {
    llvm::SmallVector<mlir::Type> paramTypes;
    for (auto &p : fn.params) paramTypes.push_back(resolveType(p.type));

    llvm::SmallVector<mlir::Type> resultTypes;
    if (fn.returnType.name != "void")
      resultTypes.push_back(resolveType(fn.returnType));

    auto funcType = b.getFunctionType(paramTypes, resultTypes);
    auto funcOp = mlir::func::FuncOp::create(loc, std::string(fn.name), funcType);
    auto *entry = funcOp.addEntryBlock();

    mlir::OpBuilder::InsertionGuard guard(b);
    b.setInsertionPointToStart(entry);

    // Zig AstGen pattern: bind param names in scope.
    namedValues.clear();
    localAddrs.clear();
    for (size_t i = 0; i < fn.params.size(); i++)
      namedValues[fn.params[i].name] = entry->getArgument(i);

    mlir::Type retType = resultTypes.empty() ? b.getNoneType() : resultTypes[0];
    for (auto &stmt : fn.body)
      emitStmt(*stmt, retType, funcOp);

    module.push_back(funcOp);
  }

  // Zig pattern: test blocks become parameterless void functions.
  // The test runner main() calls each one.
  void emitTest(mlir::ModuleOp module, const TestDecl &td, int index) {
    std::string name = "__test_" + std::to_string(index);
    auto funcType = b.getFunctionType({}, {});
    auto funcOp = mlir::func::FuncOp::create(loc, name, funcType);
    funcOp.setPrivate();
    auto *entry = funcOp.addEntryBlock();

    mlir::OpBuilder::InsertionGuard guard(b);
    b.setInsertionPointToStart(entry);
    namedValues.clear();

    for (auto &stmt : td.body)
      emitStmt(*stmt, b.getNoneType(), funcOp);

    // Implicit void return if not terminated
    auto &lastBlock = funcOp.getBody().back();
    if (lastBlock.empty() || !lastBlock.back().hasTrait<mlir::OpTrait::IsTerminator>())
      b.create<mlir::func::ReturnOp>(loc, mlir::ValueRange{});

    module.push_back(funcOp);
  }

  // Generate test runner main: calls each test, returns 0 on success.
  // Zig pattern: test runner iterates test_functions array.
  void emitTestRunner(mlir::ModuleOp module, int testCount) {
    auto i32 = b.getI32Type();
    auto funcType = b.getFunctionType({}, {i32});
    auto funcOp = mlir::func::FuncOp::create(loc, "main", funcType);
    auto *entry = funcOp.addEntryBlock();

    mlir::OpBuilder::InsertionGuard guard(b);
    b.setInsertionPointToStart(entry);

    // Call each test function
    for (int i = 0; i < testCount; i++) {
      std::string name = "__test_" + std::to_string(i);
      b.create<mlir::func::CallOp>(loc, name, mlir::TypeRange{});
    }

    // Return 0 (all tests passed — if any failed, trap would have fired)
    auto zero = b.create<cir::ConstantOp>(loc, i32, b.getI32IntegerAttr(0));
    b.create<mlir::func::ReturnOp>(loc, mlir::ValueRange{zero});
    module.push_back(funcOp);
  }

public:
  CodeGen(mlir::MLIRContext &ctx, std::string_view source)
      : b(&ctx), loc(b.getUnknownLoc()), source_(source) {}

  mlir::OwningOpRef<mlir::ModuleOp> emit(const Module &mod, bool testMode) {
    auto module = mlir::ModuleOp::create(loc);
    for (auto &fn : mod.functions) emitFn(module, fn);
    if (testMode && !mod.tests.empty()) {
      for (size_t i = 0; i < mod.tests.size(); i++)
        emitTest(module, mod.tests[i], i);
      emitTestRunner(module, mod.tests.size());
    }
    return module;
  }
};

mlir::OwningOpRef<mlir::ModuleOp> codegen(mlir::MLIRContext &ctx,
                                           std::string_view source,
                                           const Module &mod,
                                           bool testMode) {
  CodeGen cg(ctx, source);
  return cg.emit(mod, testMode);
}

} // namespace ac
