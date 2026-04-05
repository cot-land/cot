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
  std::string filename_;
  mlir::ModuleOp module_;
  bool hasError_ = false;

  /// Compute line and column from byte offset in source.
  std::pair<unsigned, unsigned> lineCol(size_t offset) const {
    unsigned line = 1, col = 1;
    for (size_t i = 0; i < offset && i < source_.size(); i++) {
      if (source_[i] == '\n') { line++; col = 1; }
      else { col++; }
    }
    return {line, col};
  }

  /// Create a FileLineColLoc from a byte offset in source.
  mlir::Location locFromOffset(size_t offset) {
    auto [line, col] = lineCol(offset);
    return mlir::FileLineColLoc::get(
        b.getContext(), llvm::StringRef(filename_), line, col);
  }

  // Zig AstGen pattern: scope holds named values for current function.
  // params: SSA value (direct), locals: SSA address (needs cir.load)
  std::unordered_map<std::string_view, mlir::Value> namedValues;
  std::unordered_map<std::string_view, std::pair<mlir::Value, mlir::Type>> localAddrs;

  // Loop stack for break/continue — {header, exit} block pairs
  struct LoopContext { mlir::Block *header; mlir::Block *exit; };
  llvm::SmallVector<LoopContext> loopStack;

  // Struct type registry — populated by emitStructDecl, queried by resolveType
  std::unordered_map<std::string_view, mlir::Type> structTypes;

  // Enum type registry — populated by emitEnumDecl, queried by resolveType
  std::unordered_map<std::string_view, mlir::Type> enumTypes;

  mlir::Type resolveType(const TypeRef &t) {
    // Ref/pointer type: *T → !cir.ref<T>
    if (t.isRef) {
      TypeRef elemRef{t.name};
      auto pointeeType = resolveType(elemRef);
      return cir::RefType::get(b.getContext(), pointeeType);
    }
    // Optional type: ?T
    if (t.isOptional) {
      TypeRef innerRef{t.name};
      auto innerType = resolveType(innerRef);
      return cir::OptionalType::get(b.getContext(), innerType);
    }
    // Error union type: !T
    if (t.isErrorUnion) {
      TypeRef innerRef{t.name};
      auto innerType = resolveType(innerRef);
      return cir::ErrorUnionType::get(b.getContext(), innerType);
    }
    // Slice type: []T
    if (t.isSlice) {
      TypeRef elemRef{t.arrayElemType};
      auto elemType = resolveType(elemRef);
      return cir::SliceType::get(b.getContext(), elemType);
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
    // String type → !cir.slice<i8>
    if (t.name == "string")
      return cir::SliceType::get(b.getContext(), b.getIntegerType(8));
    // Struct types
    auto sit = structTypes.find(t.name);
    if (sit != structTypes.end()) return sit->second;
    // Enum types
    auto eit = enumTypes.find(t.name);
    if (eit != enumTypes.end()) return eit->second;
    return b.getI32Type();
  }

  // Zig AstGen pattern: expr() dispatches on node kind, returns IR value.
  mlir::Value emitExpr(const Expr &e, mlir::Type resultType) {
    loc = locFromOffset(e.pos);
    switch (e.kind) {
    case ExprKind::IntLit:
      return b.create<cir::ConstantOp>(loc, resultType,
          b.getIntegerAttr(resultType, e.intVal));

    case ExprKind::BoolLit:
      return b.create<cir::ConstantOp>(loc, resultType,
          b.getIntegerAttr(resultType, e.boolVal ? 1 : 0));

    case ExprKind::StringLit: {
      auto sliceType = cir::SliceType::get(b.getContext(), b.getIntegerType(8));
      return b.create<cir::StringConstantOp>(loc, sliceType,
          b.getStringAttr(e.strVal));
    }

    case ExprKind::NullLit: {
      // null literal — resultType must be an optional type
      if (!llvm::isa<cir::OptionalType>(resultType)) {
        mlir::emitError(loc) << "null used in non-optional context, "
            << "expected optional type but got " << resultType;
        hasError_ = true;
        // Return a dummy value to avoid cascading crashes
        return b.create<cir::ConstantOp>(loc, resultType,
            b.getIntegerAttr(resultType, 0));
      }
      return b.create<cir::NoneOp>(loc, resultType);
    }

    case ExprKind::ErrorLit: {
      // error(N) — resultType must be an error union type
      if (!llvm::isa<cir::ErrorUnionType>(resultType)) {
        llvm::errs() << "error: error() used in non-error-union context\n";
        return {};
      }
      auto i16Type = b.getIntegerType(16);
      auto code = b.create<cir::ConstantOp>(loc, i16Type,
          b.getIntegerAttr(i16Type, e.intVal));
      return b.create<cir::WrapErrorOp>(loc, resultType, code);
    }

    case ExprKind::TryExpr: {
      // try expr — unwrap error union or propagate error
      // Desugar: is_error → condbr → error path (return error) / success path (payload)
      auto euVal = emitExpr(*e.lhs, resultType);
      auto euType = llvm::dyn_cast<cir::ErrorUnionType>(euVal.getType());
      if (!euType) {
        llvm::errs() << "error: try requires error union type\n";
        return {};
      }
      auto cond = b.create<cir::IsErrorOp>(loc, b.getI1Type(), euVal);
      auto parentFunc = b.getInsertionBlock()->getParentOp();
      auto funcOp = llvm::cast<mlir::func::FuncOp>(parentFunc);
      auto *errorBlock = addBlock(funcOp);
      auto *successBlock = addBlock(funcOp);
      b.create<cir::CondBrOp>(loc, cond, errorBlock, successBlock);
      // Error path: extract error code, wrap in function's return EU type, return
      b.setInsertionPointToStart(errorBlock);
      auto errCode = b.create<cir::ErrorCodeOp>(loc, b.getIntegerType(16), euVal);
      auto retType = funcOp.getResultTypes()[0];
      auto retEU = b.create<cir::WrapErrorOp>(loc, retType, errCode);
      b.create<mlir::func::ReturnOp>(loc, mlir::ValueRange{retEU});
      // Success path: extract payload
      b.setInsertionPointToStart(successBlock);
      return b.create<cir::ErrorPayloadOp>(loc, euType.getPayloadType(), euVal);
    }

    case ExprKind::CatchExpr: {
      // expr catch |e| { handler } — unwrap error union or evaluate handler
      auto euVal = emitExpr(*e.lhs, resultType);
      auto euType = llvm::dyn_cast<cir::ErrorUnionType>(euVal.getType());
      if (!euType) {
        llvm::errs() << "error: catch requires error union type\n";
        return {};
      }
      auto cond = b.create<cir::IsErrorOp>(loc, b.getI1Type(), euVal);
      auto parentFunc = b.getInsertionBlock()->getParentOp();
      auto funcOp = llvm::cast<mlir::func::FuncOp>(parentFunc);
      auto *errorBlock = addBlock(funcOp);
      auto *successBlock = addBlock(funcOp);
      auto *mergeBlock = addBlock(funcOp);
      auto payloadType = euType.getPayloadType();
      // Add block argument to merge block to carry the result
      mergeBlock->addArgument(payloadType, loc);
      b.create<cir::CondBrOp>(loc, cond, errorBlock, successBlock);
      // Error path: bind error code to capture var, evaluate handler
      b.setInsertionPointToStart(errorBlock);
      auto errCode = b.create<cir::ErrorCodeOp>(loc, b.getIntegerType(16), euVal);
      auto ptrType = cir::PointerType::get(b.getContext());
      auto errAddr = b.create<cir::AllocaOp>(loc, ptrType,
          mlir::TypeAttr::get(b.getIntegerType(16)));
      b.create<cir::StoreOp>(loc, errCode, errAddr);
      localAddrs[e.name] = {errAddr, b.getIntegerType(16)};
      auto handlerVal = emitExpr(*e.rhs, payloadType);
      localAddrs.erase(e.name);
      b.create<cir::BrOp>(loc, mlir::ValueRange{handlerVal}, mergeBlock);
      // Success path: extract payload
      b.setInsertionPointToStart(successBlock);
      auto payload = b.create<cir::ErrorPayloadOp>(loc, payloadType, euVal);
      b.create<cir::BrOp>(loc, mlir::ValueRange{payload}, mergeBlock);
      // Merge: result is block argument
      b.setInsertionPointToStart(mergeBlock);
      return mergeBlock->getArgument(0);
    }

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
      // Address-of: &x → cir.addr_of (alloca ptr → !cir.ref<T>)
      if (e.op == Tag::ampersand) {
        // The operand must be an identifier (local variable)
        if (e.rhs->kind == ExprKind::Ident) {
          auto lit = localAddrs.find(e.rhs->name);
          if (lit != localAddrs.end()) {
            auto [addr, elemType] = lit->second;
            auto refType = cir::RefType::get(b.getContext(), elemType);
            return b.create<cir::AddrOfOp>(loc, refType, addr);
          }
        }
        llvm::errs() << "error: can only take address of local variables\n";
        return {};
      }
      // Dereference: *p → cir.deref (!cir.ref<T> → T)
      if (e.op == Tag::star) {
        auto operand = emitExpr(*e.rhs, resultType);
        auto refType = llvm::dyn_cast<cir::RefType>(operand.getType());
        if (refType) {
          return b.create<cir::DerefOp>(loc, refType.getPointeeType(), operand);
        }
        llvm::errs() << "error: dereference of non-reference type\n";
        return {};
      }
      auto operand = emitExpr(*e.rhs, resultType);
      if (e.op == Tag::minus)
        return b.create<cir::NegOp>(loc, resultType, operand);
      if (e.op == Tag::tilde)
        return b.create<cir::BitNotOp>(loc, resultType, operand);
      if (e.op == Tag::bang) {
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
      // Explicit cast: x as i64 / x as u64
      // Emit operand with its own type, then insert the correct cast op.
      // If target type name starts with 'u', use unsigned extension.
      auto dstType = resolveType(e.targetType);
      auto srcVal = emitExpr(*e.lhs, resultType);
      auto srcType = srcVal.getType();
      if (srcType == dstType) return srcVal; // no-op cast
      bool isUnsigned = !e.targetType.name.empty() && e.targetType.name[0] == 'u';
      return emitCast(srcVal, srcType, dstType, isUnsigned);
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
      // Indexing: arr[i] or slice[i]
      auto obj = emitExpr(*e.lhs, resultType);
      auto objType = obj.getType();
      // Slice indexing: s[i] → cir.slice_elem
      if (auto sliceTy = llvm::dyn_cast<cir::SliceType>(objType)) {
        auto idx = emitExpr(*e.rhs, b.getI64Type());
        return b.create<cir::SliceElemOp>(loc, sliceTy.getElementType(),
            obj, idx);
      }
      // Array indexing: arr[i] → elem_val or elem_ptr + load
      auto arrayTy = llvm::dyn_cast<cir::ArrayType>(objType);
      if (!arrayTy) {
        llvm::errs() << "error: indexing non-array/slice type\n";
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

    case ExprKind::SliceExpr: {
      // Range slice: arr[lo..hi] → cir.array_to_slice
      // lhs = array, rhs = lo, args[0] = hi
      auto arr = emitExpr(*e.lhs, resultType);
      auto arrType = arr.getType();
      auto arrayTy = llvm::dyn_cast<cir::ArrayType>(arrType);
      if (!arrayTy) {
        llvm::errs() << "error: slicing non-array type\n";
        return {};
      }
      auto lo = emitExpr(*e.rhs, b.getI64Type());
      auto hi = emitExpr(*e.args[0], b.getI64Type());
      // Need a pointer to the array — alloca + store
      auto ptrType = cir::PointerType::get(b.getContext());
      auto addr = b.create<cir::AllocaOp>(loc, ptrType,
          mlir::TypeAttr::get(arrayTy));
      b.create<cir::StoreOp>(loc, arr, addr);
      auto sliceType = cir::SliceType::get(b.getContext(),
          arrayTy.getElementType());
      return b.create<cir::ArrayToSliceOp>(loc, sliceType, addr, lo, hi,
          mlir::TypeAttr::get(arrayTy));
    }

    case ExprKind::MethodCall: {
      // Method call: p.distance() → distance(p)
      // Desugar to function call with object as first argument.
      // Auto-deref: if receiver is !cir.ref<T>, deref to match callee param type.
      // Reference: Zig AstGen — methods are functions, receiver is first param.
      std::string callee(e.name);
      auto funcOp = module_.lookupSymbol<mlir::func::FuncOp>(callee);
      mlir::Type selfType = funcOp ? funcOp.getArgumentTypes()[0] : resultType;
      auto self = emitExpr(*e.lhs, selfType);
      // Auto-deref receiver if needed
      if (auto refType = llvm::dyn_cast<cir::RefType>(self.getType())) {
        if (selfType != self.getType()) {
          self = b.create<cir::DerefOp>(loc, refType.getPointeeType(), self);
        }
      }
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

    case ExprKind::EnumAccess:
      // Handled same as FieldAccess — enum detection below
      [[fallthrough]];
    case ExprKind::FieldAccess: {
      // Enum access: Color.Red → cir.enum_constant
      // Check if lhs is an identifier naming an enum type
      if (e.lhs->kind == ExprKind::Ident) {
        auto eit = enumTypes.find(e.lhs->name);
        if (eit != enumTypes.end()) {
          auto enumTy = eit->second;
          return b.create<cir::EnumConstantOp>(loc, enumTy,
              b.getStringAttr(llvm::StringRef(e.name.data(), e.name.size())));
        }
      }
      // Field access: p.x → extract field from struct value
      // Auto-deref: if p is !cir.ref<StructType>, insert implicit deref first
      // Reference: Zig/Rust/Go auto-deref through pointers on field access
      auto obj = emitExpr(*e.lhs, resultType);
      auto objType = obj.getType();
      // Auto-deref: unwrap !cir.ref<T> → T
      if (auto refType = llvm::dyn_cast<cir::RefType>(objType)) {
        obj = b.create<cir::DerefOp>(loc, refType.getPointeeType(), obj);
        objType = obj.getType();
      }
      // Slice field access: s.len → cir.slice_len, s.ptr → cir.slice_ptr
      if (llvm::isa<cir::SliceType>(objType)) {
        auto fieldName = llvm::StringRef(e.name.data(), e.name.size());
        if (fieldName == "len")
          return b.create<cir::SliceLenOp>(loc, b.getI64Type(), obj);
        if (fieldName == "ptr")
          return b.create<cir::SlicePtrOp>(loc,
              cir::PointerType::get(b.getContext()), obj);
        llvm::errs() << "error: no field '" << e.name << "' on slice\n";
        return {};
      }
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
                       mlir::Type dstType, bool isUnsigned = false) {
    // Enum → integer: extract tag value, then cast if needed
    if (auto enumType = llvm::dyn_cast<cir::EnumType>(srcType)) {
      auto tagType = enumType.getTagType();
      auto tagVal = b.create<cir::EnumValueOp>(loc, tagType, input);
      if (tagType == dstType) return tagVal;
      // May need integer width cast (e.g., i8 enum tag → i32)
      return emitCast(tagVal, tagType, dstType, isUnsigned);
    }
    bool srcInt = llvm::isa<mlir::IntegerType>(srcType);
    bool dstInt = llvm::isa<mlir::IntegerType>(dstType);
    bool srcFloat = llvm::isa<mlir::FloatType>(srcType);
    bool dstFloat = llvm::isa<mlir::FloatType>(dstType);

    if (srcInt && dstInt) {
      unsigned srcW = srcType.getIntOrFloatBitWidth();
      unsigned dstW = dstType.getIntOrFloatBitWidth();
      if (dstW > srcW) {
        if (isUnsigned)
          return b.create<cir::ExtUIOp>(loc, dstType, input);
        return b.create<cir::ExtSIOp>(loc, dstType, input);
      }
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

  /// If target is optional but value isn't, auto-wrap with cir.wrap_optional.
  mlir::Value maybeWrapOptional(mlir::Value val, mlir::Type targetType) {
    auto optType = llvm::dyn_cast<cir::OptionalType>(targetType);
    if (!optType) return val;
    if (llvm::isa<cir::OptionalType>(val.getType())) return val;
    // Value is T, target is ?T — wrap
    return b.create<cir::WrapOptionalOp>(loc, optType, val);
  }

  /// If target is error union but value is T, auto-wrap with cir.wrap_result.
  mlir::Value maybeWrapErrorUnion(mlir::Value val, mlir::Type targetType) {
    auto euType = llvm::dyn_cast<cir::ErrorUnionType>(targetType);
    if (!euType) return val;
    if (llvm::isa<cir::ErrorUnionType>(val.getType())) return val;
    return b.create<cir::WrapResultOp>(loc, euType, val);
  }

  void emitLetVar(const Stmt &s) {
    auto varType = resolveType(s.varType);
    auto ptrType = cir::PointerType::get(b.getContext());
    auto addr = b.create<cir::AllocaOp>(loc, ptrType,
        mlir::TypeAttr::get(varType));
    // For optional vars with non-null initializer, pass the payload type
    // to emitExpr so it produces T, then auto-wrap to ?T.
    // For null initializer, pass the full optional type.
    // Same pattern for error union vars with non-error initializers.
    mlir::Type exprType = varType;
    if (auto optType = llvm::dyn_cast<cir::OptionalType>(varType)) {
      if (s.expr->kind != ExprKind::NullLit)
        exprType = optType.getPayloadType();
    }
    if (auto euType = llvm::dyn_cast<cir::ErrorUnionType>(varType)) {
      if (s.expr->kind != ExprKind::ErrorLit &&
          s.expr->kind != ExprKind::TryExpr &&
          s.expr->kind != ExprKind::CatchExpr)
        exprType = euType.getPayloadType();
    }
    auto val = emitExpr(*s.expr, exprType);
    val = maybeWrapOptional(val, varType);
    val = maybeWrapErrorUnion(val, varType);
    b.create<cir::StoreOp>(loc, val, addr);
    localAddrs[s.varName] = {addr, varType};
  }

  void emitAssign(const Stmt &s) {
    // Field assignment: p.x = expr (rangeEnd holds field info)
    if (s.rangeEnd && s.rangeEnd->kind == ExprKind::FieldAccess) {
      auto lit = localAddrs.find(s.varName);
      if (lit == localAddrs.end()) {
        llvm::errs() << "error: undefined variable '" << s.varName << "'\n";
        return;
      }
      auto [addr, elemType] = lit->second;
      // Get struct type — may be direct struct or ref to struct
      auto structType = elemType;
      if (auto refType = llvm::dyn_cast<cir::RefType>(elemType))
        structType = refType.getPointeeType();
      auto cirStruct = llvm::dyn_cast<cir::StructType>(structType);
      if (!cirStruct) {
        llvm::errs() << "error: field assignment requires struct type\n";
        return;
      }
      auto fieldName = llvm::StringRef(s.rangeEnd->name.data(),
                                        s.rangeEnd->name.size());
      int fieldIdx = cirStruct.getFieldIndex(fieldName);
      if (fieldIdx < 0) {
        llvm::errs() << "error: no field '" << fieldName << "'\n";
        return;
      }
      auto fieldType = cirStruct.getFieldTypes()[fieldIdx];
      auto val = emitExpr(*s.expr, fieldType);
      // Use field_ptr to get pointer to the field, then store
      auto fieldPtr = b.create<cir::FieldPtrOp>(loc,
          cir::PointerType::get(b.getContext()),
          addr, b.getI64IntegerAttr(fieldIdx),
          mlir::TypeAttr::get(cirStruct));
      b.create<cir::StoreOp>(loc, val, fieldPtr);
      return;
    }
    // Index assignment: arr[i] = expr (op == l_bracket, rangeEnd = index)
    if (s.op == Tag::l_bracket && s.rangeEnd) {
      auto lit = localAddrs.find(s.varName);
      if (lit == localAddrs.end()) {
        llvm::errs() << "error: undefined variable '" << s.varName << "'\n";
        return;
      }
      auto [addr, elemType] = lit->second;
      auto arrType = llvm::dyn_cast<cir::ArrayType>(elemType);
      if (!arrType) {
        llvm::errs() << "error: index assignment requires array type\n";
        return;
      }
      auto arrElemType = arrType.getElementType();
      auto val = emitExpr(*s.expr, arrElemType);
      auto idx = emitExpr(*s.rangeEnd, b.getI64Type());
      // Use elem_ptr to get pointer to array element, then store
      auto elemPtr = b.create<cir::ElemPtrOp>(loc,
          cir::PointerType::get(b.getContext()),
          addr, idx, mlir::TypeAttr::get(elemType));
      b.create<cir::StoreOp>(loc, val, elemPtr);
      return;
    }
    // Simple assignment: x = expr
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
    loc = locFromOffset(s.pos);
    switch (s.kind) {
    case StmtKind::Return:
      if (s.expr) {
        // For error union return types with non-error initializer, emit the
        // payload type then auto-wrap. Same pattern as optional/let.
        mlir::Type exprType = returnType;
        if (auto euType = llvm::dyn_cast<cir::ErrorUnionType>(returnType)) {
          if (s.expr->kind != ExprKind::ErrorLit)
            exprType = euType.getPayloadType();
        }
        if (auto optType = llvm::dyn_cast<cir::OptionalType>(returnType)) {
          if (s.expr->kind != ExprKind::NullLit)
            exprType = optType.getPayloadType();
        }
        auto val = emitExpr(*s.expr, exprType);
        val = maybeWrapOptional(val, returnType);
        val = maybeWrapErrorUnion(val, returnType);
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
    case StmtKind::IfUnwrap:
      emitIfUnwrapStmt(s, returnType, parentFunc); break;
    case StmtKind::Match:
      emitMatchStmt(s, returnType, parentFunc); break;
    case StmtKind::Throw:
      emitThrowStmt(s); break;
    case StmtKind::TryCatch:
      emitTryCatchStmt(s, returnType, parentFunc); break;
    }
  }

  void emitMatchStmt(const Stmt &s, mlir::Type returnType,
                       mlir::func::FuncOp parentFunc) {
    // match expr { pattern => body, ... }
    // Desugar: emit expr, extract integer (enum_value if enum), switch on cases

    auto matchVal = emitExpr(*s.expr, b.getI32Type());
    auto matchType = matchVal.getType();

    // If matching on an enum, extract the integer tag
    mlir::Value switchVal = matchVal;
    if (auto enumType = llvm::dyn_cast<cir::EnumType>(matchType)) {
      switchVal = b.create<cir::EnumValueOp>(loc, enumType.getTagType(),
                                              matchVal);
    }

    // Create blocks: one per arm + default (fallthrough)
    auto *defaultBlock = addBlock(parentFunc);
    auto *mergeBlock = addBlock(parentFunc);
    llvm::SmallVector<mlir::Block *> armBlocks;
    llvm::SmallVector<int64_t> caseValues;

    for (auto &arm : s.matchArms) {
      auto *armBlock = addBlock(parentFunc);
      armBlocks.push_back(armBlock);

      // Evaluate the pattern to get the integer case value
      if (arm.pattern->kind == ExprKind::IntLit) {
        caseValues.push_back(arm.pattern->intVal);
      } else if (arm.pattern->kind == ExprKind::FieldAccess ||
                 arm.pattern->kind == ExprKind::EnumAccess) {
        // Enum constant: Color.Red → look up the integer value
        if (arm.pattern->lhs && arm.pattern->lhs->kind == ExprKind::Ident) {
          auto eit = enumTypes.find(arm.pattern->lhs->name);
          if (eit != enumTypes.end()) {
            auto et = llvm::cast<cir::EnumType>(eit->second);
            auto val = et.getVariantValue(
                llvm::StringRef(arm.pattern->name.data(),
                                arm.pattern->name.size()));
            caseValues.push_back(val);
          } else {
            caseValues.push_back(0); // fallback
          }
        } else {
          caseValues.push_back(0);
        }
      } else {
        caseValues.push_back(0);
      }
    }

    // Emit cir.switch
    b.create<cir::SwitchOp>(loc, switchVal,
        mlir::DenseI64ArrayAttr::get(b.getContext(), caseValues),
        defaultBlock, armBlocks);

    // Emit each arm body
    for (size_t i = 0; i < armBlocks.size(); i++) {
      b.setInsertionPointToStart(armBlocks[i]);
      for (auto &st : s.matchArms[i].body) {
        if (blockTerminated()) break;
        emitStmt(*st, returnType, parentFunc);
      }
      if (!blockTerminated())
        b.create<cir::BrOp>(loc, mlir::ValueRange{}, mergeBlock);
    }

    // Default block: branch to merge
    b.setInsertionPointToStart(defaultBlock);
    b.create<cir::BrOp>(loc, mlir::ValueRange{}, mergeBlock);

    b.setInsertionPointToStart(mergeBlock);
  }

  void emitThrowStmt(const Stmt &s) {
    // throw expr → cir.throw %val
    auto val = emitExpr(*s.expr, b.getI32Type());
    b.create<cir::ThrowOp>(loc, val);
  }

  void emitTryCatchStmt(const Stmt &s, mlir::Type returnType,
                          mlir::func::FuncOp parentFunc) {
    // try { body } catch |e| { handler }
    // Proper block structure (same pattern as emitIfStmt):
    //   current block → br ^tryBody
    //   ^tryBody:  <body stmts>  br ^merge (if not terminated)
    //   ^catchBody: landingpad, bind e, <handler stmts>, br ^merge
    //   ^merge: <continue>

    auto *tryBlock = addBlock(parentFunc);
    auto *catchBlock = addBlock(parentFunc);
    auto *mergeBlock = addBlock(parentFunc);

    // Connect catch block: use condbr with always-false condition.
    // This makes the catch block reachable in the CFG (required for MLIR
    // full conversion), but never taken at runtime. Phase 2 will replace
    // this with cir.invoke which naturally connects the unwind path.
    // condbr true → tryBlock, false → catchBlock (catch never taken)
    auto trueCond = b.create<cir::ConstantOp>(loc, b.getI1Type(),
        b.getIntegerAttr(b.getI1Type(), 1));
    b.create<cir::CondBrOp>(loc, trueCond, tryBlock, catchBlock);

    // Try body
    b.setInsertionPointToStart(tryBlock);
    for (auto &st : s.thenBody) emitStmt(*st, returnType, parentFunc);
    bool tryReturns = !tryBlock->empty() &&
        tryBlock->back().hasTrait<mlir::OpTrait::IsTerminator>();
    if (!tryReturns)
      b.create<cir::BrOp>(loc, mlir::ValueRange{}, mergeBlock);

    // Catch block: landingpad + bind error + handler
    b.setInsertionPointToStart(catchBlock);
    auto excVal = b.create<cir::LandingPadOp>(loc, b.getI32Type());
    auto ptrType = cir::PointerType::get(b.getContext());
    auto errAddr = b.create<cir::AllocaOp>(loc, ptrType,
        mlir::TypeAttr::get(b.getI32Type()));
    b.create<cir::StoreOp>(loc, excVal, errAddr);
    localAddrs[s.varName] = {errAddr, b.getI32Type()};
    for (auto &st : s.elseBody) emitStmt(*st, returnType, parentFunc);
    localAddrs.erase(s.varName);
    bool catchReturns = !catchBlock->empty() &&
        catchBlock->back().hasTrait<mlir::OpTrait::IsTerminator>();
    if (!catchReturns)
      b.create<cir::BrOp>(loc, mlir::ValueRange{}, mergeBlock);

    // Merge block
    b.setInsertionPointToStart(mergeBlock);
    if (tryReturns && catchReturns)
      b.create<cir::TrapOp>(loc);
  }

  void emitIfUnwrapStmt(const Stmt &s, mlir::Type returnType,
                         mlir::func::FuncOp parentFunc) {
    // if optExpr |val| { thenBody } else { elseBody }
    // Desugar:
    //   %opt = <emit optExpr>
    //   %is_some = cir.is_non_null %opt
    //   cir.condbr %is_some, ^then, ^else
    //   ^then:
    //     %val = cir.optional_payload %opt
    //     <thenBody with val in scope>
    //     cir.br ^merge
    //   ^else:
    //     <elseBody>
    //     cir.br ^merge
    //   ^merge:

    // Emit the optional expression. We don't know the payload type yet,
    // so use a dummy. The expr should produce an optional type.
    auto optVal = emitExpr(*s.expr, b.getI32Type());
    auto optType = llvm::dyn_cast<cir::OptionalType>(optVal.getType());
    if (!optType) {
      llvm::errs() << "error: if-unwrap requires optional type\n";
      return;
    }

    auto cond = b.create<cir::IsNonNullOp>(loc, b.getI1Type(), optVal);

    auto *thenBlock = addBlock(parentFunc);
    auto *elseBlock = addBlock(parentFunc);
    auto *mergeBlock = addBlock(parentFunc);
    b.create<cir::CondBrOp>(loc, cond, thenBlock, elseBlock);

    // Then block: extract payload, bind as local
    b.setInsertionPointToStart(thenBlock);
    auto payloadType = optType.getPayloadType();
    auto payload = b.create<cir::OptionalPayloadOp>(loc, payloadType, optVal);
    // Bind captured variable in scope (alloca + store pattern)
    auto ptrType = cir::PointerType::get(b.getContext());
    auto valAddr = b.create<cir::AllocaOp>(loc, ptrType,
        mlir::TypeAttr::get(payloadType));
    b.create<cir::StoreOp>(loc, payload, valAddr);
    localAddrs[s.varName] = {valAddr, payloadType};

    for (auto &st : s.thenBody) emitStmt(*st, returnType, parentFunc);
    bool thenReturns = !thenBlock->empty() &&
        thenBlock->back().hasTrait<mlir::OpTrait::IsTerminator>();
    if (!thenReturns)
      b.create<cir::BrOp>(loc, mlir::ValueRange{}, mergeBlock);

    // Remove captured variable from scope
    localAddrs.erase(s.varName);

    // Else block
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
    for (auto &stmt : fn.body) {
      if (blockTerminated()) break;
      emitStmt(*stmt, retType, funcOp);
    }

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

    for (auto &stmt : td.body) {
      if (blockTerminated()) break;
      emitStmt(*stmt, b.getNoneType(), funcOp);
    }

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

  /// Register an enum type from a parsed enum declaration.
  /// Creates !cir.enum<"Name", i32, Variant1: 0, Variant2: 1, ...>.
  void emitEnumDecl(const EnumDecl &ed) {
    llvm::SmallVector<mlir::StringAttr> variantNames;
    llvm::SmallVector<int64_t> variantValues;
    for (auto &v : ed.variants) {
      variantNames.push_back(mlir::StringAttr::get(
          b.getContext(), llvm::StringRef(v.name.data(), v.name.size())));
      variantValues.push_back(v.value);
    }
    // Default tag type is i32 (matches TypeScript). ac can specify explicitly later.
    auto tagType = b.getI32Type();
    auto enumTy = cir::EnumType::get(
        b.getContext(), std::string(ed.name), tagType,
        variantNames, variantValues);
    enumTypes[ed.name] = enumTy;
  }

public:
  CodeGen(mlir::MLIRContext &ctx, std::string_view source,
          std::string_view filename = "<unknown>")
      : b(&ctx), loc(b.getUnknownLoc()), source_(source),
        filename_(filename) {
    // Default location — will be overridden per-op by locFromOffset
    loc = mlir::FileLineColLoc::get(b.getContext(),
        llvm::StringRef(filename_), 1, 1);
  }

  mlir::OwningOpRef<mlir::ModuleOp> emit(const Module &mod, bool testMode) {
    auto module = mlir::ModuleOp::create(loc);
    module_ = module;
    // Register types first — needed before resolving function param types
    for (auto &sd : mod.structs) emitStructDecl(sd);
    for (auto &ed : mod.enums) emitEnumDecl(ed);
    for (auto &fn : mod.functions) emitFn(module, fn);
    if (testMode && !mod.tests.empty()) {
      for (size_t i = 0; i < mod.tests.size(); i++)
        emitTest(module, mod.tests[i], i);
      emitTestRunner(module, mod.tests.size());
    }
    if (hasError_) return {};
    return module;
  }
};

mlir::OwningOpRef<mlir::ModuleOp> codegen(mlir::MLIRContext &ctx,
                                           std::string_view source,
                                           const Module &mod,
                                           bool testMode,
                                           std::string_view filename) {
  CodeGen cg(ctx, source, filename);
  return cg.emit(mod, testMode);
}

} // namespace ac
