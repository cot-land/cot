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
  mlir::ModuleOp module_;

  // Zig AstGen pattern: scope holds named values for current function.
  // params: SSA value (direct), locals: SSA address (needs cir.load)
  std::unordered_map<std::string_view, mlir::Value> namedValues;
  std::unordered_map<std::string_view, std::pair<mlir::Value, mlir::Type>> localAddrs;

  // Loop stack for break/continue — {header, exit} block pairs
  struct LoopContext { mlir::Block *header; mlir::Block *exit; };
  llvm::SmallVector<LoopContext> loopStack;

  // Struct type registry — populated by emitStructDecl, queried by resolveType
  std::unordered_map<std::string_view, mlir::Type> structTypes;

  mlir::Type resolveType(const TypeRef &t) {
    // Ref/pointer type: *T → !cir.ref<T>
    if (t.isRef) {
      TypeRef elemRef{t.name};
      auto pointeeType = resolveType(elemRef);
      return cir::RefType::get(b.getContext(), pointeeType);
    }
    // Array type: [N]T
    if (t.arraySize > 0) {
      TypeRef elemRef{t.arrayElemType};
      auto elemType = resolveType(elemRef);
      return cir::ArrayType::get(b.getContext(), t.arraySize, elemType);
    }
    // Integer types (signless in MLIR — signed/unsigned in op semantics)
    if (t.name == "i8"  || t.name == "u8")  return b.getIntegerType(8);
    if (t.name == "i16" || t.name == "u16") return b.getIntegerType(16);
    if (t.name == "i32" || t.name == "u32") return b.getIntegerType(32);
    if (t.name == "i64" || t.name == "u64") return b.getIntegerType(64);
    if (t.name == "bool") return b.getI1Type();
    // Float types
    if (t.name == "f32") return b.getF32Type();
    if (t.name == "f64") return b.getF64Type();
    // Struct types
    auto sit = structTypes.find(t.name);
    if (sit != structTypes.end()) return sit->second;
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
      bool isCmp = (e.op == Tag::eq_eq || e.op == Tag::bang_eq ||
                    e.op == Tag::less || e.op == Tag::less_eq ||
                    e.op == Tag::greater || e.op == Tag::greater_eq);
      // Comparisons return i1, but operands should not be i1.
      // Use i32 default for comparison operands when context is boolean.
      auto opResultType = (isCmp && resultType == b.getI1Type())
          ? b.getI32Type() : resultType;
      auto lhs = emitExpr(*e.lhs, opResultType);
      auto operandType = lhs.getType();
      auto rhs = emitExpr(*e.rhs, operandType);
      switch (e.op) {
        case Tag::plus:    return b.create<cir::AddOp>(loc, operandType, lhs, rhs);
        case Tag::minus:   return b.create<cir::SubOp>(loc, operandType, lhs, rhs);
        case Tag::star:    return b.create<cir::MulOp>(loc, operandType, lhs, rhs);
        case Tag::slash:   return b.create<cir::DivOp>(loc, operandType, lhs, rhs);
        case Tag::percent: return b.create<cir::RemOp>(loc, operandType, lhs, rhs);
        case Tag::ampersand: return b.create<cir::BitAndOp>(loc, operandType, lhs, rhs);
        case Tag::pipe:      return b.create<cir::BitOrOp>(loc, operandType, lhs, rhs);
        case Tag::caret:     return b.create<cir::BitXorOp>(loc, operandType, lhs, rhs);
        case Tag::shl:       return b.create<cir::ShlOp>(loc, operandType, lhs, rhs);
        case Tag::shr:       return b.create<cir::ShrOp>(loc, operandType, lhs, rhs);
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
        return b.create<cir::BitXorOp>(loc, resultType, operand, one);
      }
      llvm::errs() << "error: unsupported unary op\n";
      return {};
    }

    case ExprKind::Call: {
      std::string callee(e.name);
      // Look up callee to get parameter types (mini symbol table via MLIR module)
      auto funcOp = module_.lookupSymbol<mlir::func::FuncOp>(callee);
      llvm::SmallVector<mlir::Value> args;
      for (size_t i = 0; i < e.args.size(); i++) {
        mlir::Type argType = (funcOp && i < funcOp.getNumArguments())
            ? funcOp.getArgumentTypes()[i] : resultType;
        args.push_back(emitExpr(*e.args[i], argType));
      }
      // Use callee's return type if available
      mlir::Type callResultType = (funcOp && funcOp.getNumResults() > 0)
          ? funcOp.getResultTypes()[0] : resultType;
      auto call = b.create<mlir::func::CallOp>(loc, callee,
          mlir::TypeRange{callResultType}, mlir::ValueRange(args));
      return call.getResult(0);
    }

    case ExprKind::IfExpr: {
      // if cond { thenVal } else { elseVal } → cir.select
      auto cond = emitExpr(*e.args[0], b.getI1Type());
      auto thenVal = emitExpr(*e.args[1], resultType);
      auto elseVal = emitExpr(*e.args[2], resultType);
      return b.create<cir::SelectOp>(loc, resultType, cond, thenVal, elseVal);
    }

    case ExprKind::FloatLit:
      return b.create<cir::ConstantOp>(loc, resultType,
          b.getFloatAttr(resultType, e.floatVal));

    case ExprKind::Cast: {
      // Explicit cast: x as i64
      // Emit operand with its own type, then insert the correct cast op.
      auto dstType = resolveType(e.targetType);
      auto srcVal = emitExpr(*e.lhs, resultType);
      auto srcType = srcVal.getType();
      if (srcType == dstType) return srcVal; // no-op cast
      return emitCast(srcVal, srcType, dstType);
    }

    case ExprKind::ArrayLit: {
      // Array literal: [1, 2, 3] → cir.array_init
      auto arrayTy = llvm::dyn_cast<cir::ArrayType>(resultType);
      if (!arrayTy) {
        llvm::errs() << "error: array literal requires array type context\n";
        return {};
      }
      auto elemType = arrayTy.getElementType();
      llvm::SmallVector<mlir::Value> elems;
      for (auto &arg : e.args)
        elems.push_back(emitExpr(*arg, elemType));
      return b.create<cir::ArrayInitOp>(loc, arrayTy, elems);
    }

    case ExprKind::IndexAccess: {
      // Array indexing: arr[i]
      // arr is a local (alloca) — use elem_ptr + load for dynamic index
      auto obj = emitExpr(*e.lhs, resultType);
      auto objType = obj.getType();
      // If the object is an array SSA value and index is a constant, use elem_val
      auto arrayTy = llvm::dyn_cast<cir::ArrayType>(objType);
      if (!arrayTy) {
        llvm::errs() << "error: indexing non-array type\n";
        return {};
      }
      auto idx = emitExpr(*e.rhs, b.getI32Type());
      auto elemType = arrayTy.getElementType();
      // For constant index on SSA value, use cir.elem_val
      if (auto constOp = idx.getDefiningOp<cir::ConstantOp>()) {
        if (auto intAttr = llvm::dyn_cast<mlir::IntegerAttr>(constOp.getValue())) {
          return b.create<cir::ElemValOp>(loc, elemType, obj,
              b.getI64IntegerAttr(intAttr.getInt()));
        }
      }
      // Dynamic index: store to alloca, use elem_ptr + load
      auto ptrType = cir::PointerType::get(b.getContext());
      auto addr = b.create<cir::AllocaOp>(loc, ptrType,
          mlir::TypeAttr::get(arrayTy));
      b.create<cir::StoreOp>(loc, obj, addr);
      auto elemPtr = b.create<cir::ElemPtrOp>(loc, ptrType, addr, idx,
          mlir::TypeAttr::get(arrayTy));
      return b.create<cir::LoadOp>(loc, elemType, elemPtr);
    }

    case ExprKind::MethodCall: {
      // Method call: p.distance() → distance(p)
      // Desugar to function call with object as first argument.
      // Reference: Zig AstGen — methods are functions, receiver is first param.
      std::string callee(e.name);
      auto funcOp = module_.lookupSymbol<mlir::func::FuncOp>(callee);
      // Emit receiver (the object before the dot)
      mlir::Type selfType = funcOp ? funcOp.getArgumentTypes()[0] : resultType;
      auto self = emitExpr(*e.lhs, selfType);
      llvm::SmallVector<mlir::Value> args;
      args.push_back(self);
      // Emit remaining arguments
      for (size_t i = 0; i < e.args.size(); i++) {
        mlir::Type argType = (funcOp && i + 1 < funcOp.getNumArguments())
            ? funcOp.getArgumentTypes()[i + 1] : resultType;
        args.push_back(emitExpr(*e.args[i], argType));
      }
      mlir::Type callResultType = (funcOp && funcOp.getNumResults() > 0)
          ? funcOp.getResultTypes()[0] : resultType;
      auto call = b.create<mlir::func::CallOp>(loc, callee,
          mlir::TypeRange{callResultType}, mlir::ValueRange(args));
      return call.getResult(0);
    }

    case ExprKind::FieldAccess: {
      // Field access: p.x → load struct, extract field
      auto obj = emitExpr(*e.lhs, resultType);
      auto objType = obj.getType();
      auto structTy = llvm::dyn_cast<cir::StructType>(objType);
      if (!structTy) {
        llvm::errs() << "error: field access on non-struct type\n";
        return {};
      }
      int idx = structTy.getFieldIndex(
          llvm::StringRef(e.name.data(), e.name.size()));
      if (idx < 0) {
        llvm::errs() << "error: no field '" << e.name << "' in struct\n";
        return {};
      }
      auto fieldType = structTy.getFieldTypes()[idx];
      return b.create<cir::FieldValOp>(loc, fieldType, obj,
          b.getI64IntegerAttr(idx));
    }

    case ExprKind::StructInit: {
      // Struct construction: Point { x: 1, y: 2 }
      // Look up struct type, emit field values, create cir.struct_init.
      auto sit = structTypes.find(e.name);
      if (sit == structTypes.end()) {
        llvm::errs() << "error: unknown struct '" << e.name << "'\n";
        return {};
      }
      auto structTy = llvm::cast<cir::StructType>(sit->second);
      auto fieldTypes = structTy.getFieldTypes();
      // Emit field values in struct field order (match by name)
      llvm::SmallVector<mlir::Value> fieldVals(fieldTypes.size());
      for (size_t i = 0; i < e.fieldNames.size(); i++) {
        int idx = structTy.getFieldIndex(
            llvm::StringRef(e.fieldNames[i].data(), e.fieldNames[i].size()));
        if (idx < 0) {
          llvm::errs() << "error: unknown field '" << e.fieldNames[i]
                       << "' in struct '" << e.name << "'\n";
          return {};
        }
        fieldVals[idx] = emitExpr(*e.args[i], fieldTypes[idx]);
      }
      return b.create<cir::StructInitOp>(loc, structTy, fieldVals);
    }
    }
    return {};
  }

  /// Emit the correct CIR cast op based on source and destination types.
  /// Reference: Arith dialect — one op per direction, no mega-cast.
  mlir::Value emitCast(mlir::Value input, mlir::Type srcType,
                       mlir::Type dstType) {
    bool srcInt = llvm::isa<mlir::IntegerType>(srcType);
    bool dstInt = llvm::isa<mlir::IntegerType>(dstType);
    bool srcFloat = llvm::isa<mlir::FloatType>(srcType);
    bool dstFloat = llvm::isa<mlir::FloatType>(dstType);

    if (srcInt && dstInt) {
      unsigned srcW = srcType.getIntOrFloatBitWidth();
      unsigned dstW = dstType.getIntOrFloatBitWidth();
      if (dstW > srcW)
        return b.create<cir::ExtSIOp>(loc, dstType, input);
      if (dstW < srcW)
        return b.create<cir::TruncIOp>(loc, dstType, input);
      return input;
    }
    if (srcInt && dstFloat)
      return b.create<cir::SIToFPOp>(loc, dstType, input);
    if (srcFloat && dstInt)
      return b.create<cir::FPToSIOp>(loc, dstType, input);
    if (srcFloat && dstFloat) {
      unsigned srcW = srcType.getIntOrFloatBitWidth();
      unsigned dstW = dstType.getIntOrFloatBitWidth();
      if (dstW > srcW)
        return b.create<cir::ExtFOp>(loc, dstType, input);
      if (dstW < srcW)
        return b.create<cir::TruncFOp>(loc, dstType, input);
      return input;
    }
    llvm::errs() << "error: unsupported cast\n";
    return input;
  }

  // Helper: add a block to the current function's region.
  mlir::Block *addBlock(mlir::func::FuncOp fn) {
    auto *block = new mlir::Block();
    fn.getBody().push_back(block);
    return block;
  }

  // Helper: check if current insertion block is terminated.
  bool blockTerminated() {
    auto *cur = b.getInsertionBlock();
    return !cur->empty() &&
        cur->back().hasTrait<mlir::OpTrait::IsTerminator>();
  }

  void emitLetVar(const Stmt &s) {
    auto varType = resolveType(s.varType);
    auto ptrType = cir::PointerType::get(b.getContext());
    auto addr = b.create<cir::AllocaOp>(loc, ptrType,
        mlir::TypeAttr::get(varType));
    auto val = emitExpr(*s.expr, varType);
    b.create<cir::StoreOp>(loc, val, addr);
    localAddrs[s.varName] = {addr, varType};
  }

  void emitAssign(const Stmt &s) {
    auto lit = localAddrs.find(s.varName);
    if (lit == localAddrs.end()) {
      llvm::errs() << "error: undefined variable '" << s.varName << "'\n";
      return;
    }
    auto [addr, elemType] = lit->second;
    auto val = emitExpr(*s.expr, elemType);
    b.create<cir::StoreOp>(loc, val, addr);
  }

  void emitCompoundAssign(const Stmt &s) {
    auto lit = localAddrs.find(s.varName);
    if (lit == localAddrs.end()) {
      llvm::errs() << "error: undefined variable '" << s.varName << "'\n";
      return;
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
      default: llvm::errs() << "error: unsupported compound op\n"; return;
    }
    b.create<cir::StoreOp>(loc, result, addr);
  }

  void emitForStmt(const Stmt &s, mlir::Type returnType,
                   mlir::func::FuncOp parentFunc) {
    auto i32Ty = b.getI32Type();
    auto ptrType = cir::PointerType::get(b.getContext());
    auto addr = b.create<cir::AllocaOp>(loc, ptrType,
        mlir::TypeAttr::get(i32Ty));
    auto startVal = emitExpr(*s.expr, i32Ty);
    b.create<cir::StoreOp>(loc, startVal, addr);
    localAddrs[s.varName] = {addr, i32Ty};
    auto endVal = emitExpr(*s.rangeEnd, i32Ty);

    auto *headerBlock = addBlock(parentFunc);
    auto *bodyBlock = addBlock(parentFunc);
    auto *exitBlock = addBlock(parentFunc);
    b.create<cir::BrOp>(loc, mlir::ValueRange{}, headerBlock);

    b.setInsertionPointToStart(headerBlock);
    auto curVal = b.create<cir::LoadOp>(loc, i32Ty, addr);
    auto cond = b.create<cir::CmpOp>(loc, cir::CmpIPredicate::slt,
        curVal, endVal);
    b.create<cir::CondBrOp>(loc, cond, bodyBlock, exitBlock);

    b.setInsertionPointToStart(bodyBlock);
    loopStack.push_back({headerBlock, exitBlock});
    for (auto &st : s.thenBody) emitStmt(*st, returnType, parentFunc);
    loopStack.pop_back();
    if (!blockTerminated()) {
      auto v = b.create<cir::LoadOp>(loc, i32Ty, addr);
      auto one = b.create<cir::ConstantOp>(loc, i32Ty, b.getI32IntegerAttr(1));
      auto inc = b.create<cir::AddOp>(loc, i32Ty, v, one);
      b.create<cir::StoreOp>(loc, inc, addr);
      b.create<cir::BrOp>(loc, mlir::ValueRange{}, headerBlock);
    }
    b.setInsertionPointToStart(exitBlock);
  }

  void emitWhileStmt(const Stmt &s, mlir::Type returnType,
                     mlir::func::FuncOp parentFunc) {
    auto *headerBlock = addBlock(parentFunc);
    auto *bodyBlock = addBlock(parentFunc);
    auto *exitBlock = addBlock(parentFunc);
    b.create<cir::BrOp>(loc, mlir::ValueRange{}, headerBlock);

    b.setInsertionPointToStart(headerBlock);
    auto cond = emitExpr(*s.expr, b.getI1Type());
    b.create<cir::CondBrOp>(loc, cond, bodyBlock, exitBlock);

    b.setInsertionPointToStart(bodyBlock);
    loopStack.push_back({headerBlock, exitBlock});
    for (auto &st : s.thenBody) emitStmt(*st, returnType, parentFunc);
    loopStack.pop_back();
    if (!blockTerminated())
      b.create<cir::BrOp>(loc, mlir::ValueRange{}, headerBlock);
    b.setInsertionPointToStart(exitBlock);
  }

  void emitAssertStmt(const Stmt &s, mlir::func::FuncOp parentFunc) {
    auto cond = emitExpr(*s.expr, b.getI1Type());
    auto *trapBlock = addBlock(parentFunc);
    auto *contBlock = addBlock(parentFunc);
    b.create<cir::CondBrOp>(loc, cond, contBlock, trapBlock);
    b.setInsertionPointToStart(trapBlock);
    b.create<cir::TrapOp>(loc);
    b.setInsertionPointToStart(contBlock);
  }

  void emitIfStmt(const Stmt &s, mlir::Type returnType,
                  mlir::func::FuncOp parentFunc) {
    auto cond = emitExpr(*s.expr, b.getI1Type());
    auto *thenBlock = addBlock(parentFunc);
    auto *elseBlock = addBlock(parentFunc);
    auto *mergeBlock = addBlock(parentFunc);
    b.create<cir::CondBrOp>(loc, cond, thenBlock, elseBlock);

    b.setInsertionPointToStart(thenBlock);
    for (auto &st : s.thenBody) emitStmt(*st, returnType, parentFunc);
    bool thenReturns = !thenBlock->empty() &&
        thenBlock->back().hasTrait<mlir::OpTrait::IsTerminator>();
    if (!thenReturns)
      b.create<cir::BrOp>(loc, mlir::ValueRange{}, mergeBlock);

    b.setInsertionPointToStart(elseBlock);
    for (auto &st : s.elseBody) emitStmt(*st, returnType, parentFunc);
    bool elseReturns = !elseBlock->empty() &&
        elseBlock->back().hasTrait<mlir::OpTrait::IsTerminator>();
    if (!elseReturns)
      b.create<cir::BrOp>(loc, mlir::ValueRange{}, mergeBlock);

    b.setInsertionPointToStart(mergeBlock);
    if (thenReturns && elseReturns)
      b.create<cir::TrapOp>(loc);
  }

  void emitStmt(const Stmt &s, mlir::Type returnType,
                mlir::func::FuncOp parentFunc) {
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
    case StmtKind::Var:
      emitLetVar(s); break;
    case StmtKind::Assign:
      emitAssign(s); break;
    case StmtKind::CompoundAssign:
      emitCompoundAssign(s); break;
    case StmtKind::For:
      emitForStmt(s, returnType, parentFunc); break;
    case StmtKind::While:
      emitWhileStmt(s, returnType, parentFunc); break;
    case StmtKind::Break:
      if (!loopStack.empty())
        b.create<cir::BrOp>(loc, mlir::ValueRange{}, loopStack.back().exit);
      break;
    case StmtKind::Continue:
      if (!loopStack.empty())
        b.create<cir::BrOp>(loc, mlir::ValueRange{}, loopStack.back().header);
      break;
    case StmtKind::Assert:
      emitAssertStmt(s, parentFunc); break;
    case StmtKind::If:
      emitIfStmt(s, returnType, parentFunc); break;
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

  /// Register a struct type from a parsed struct declaration.
  /// Creates !cir.struct<"Name", field1: type1, ...> in the MLIR context.
  void emitStructDecl(const StructDecl &sd) {
    llvm::SmallVector<mlir::StringAttr> fieldNames;
    llvm::SmallVector<mlir::Type> fieldTypes;
    for (auto &f : sd.fields) {
      fieldNames.push_back(mlir::StringAttr::get(
          b.getContext(), llvm::StringRef(f.name.data(), f.name.size())));
      fieldTypes.push_back(resolveType(f.type));
    }
    auto structTy = cir::StructType::get(
        b.getContext(), std::string(sd.name), fieldNames, fieldTypes);
    structTypes[sd.name] = structTy;
  }

public:
  CodeGen(mlir::MLIRContext &ctx, std::string_view source)
      : b(&ctx), loc(b.getUnknownLoc()), source_(source) {}

  mlir::OwningOpRef<mlir::ModuleOp> emit(const Module &mod, bool testMode) {
    auto module = mlir::ModuleOp::create(loc);
    module_ = module;
    // Register struct types first — needed before resolving function param types
    for (auto &sd : mod.structs) emitStructDecl(sd);
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
