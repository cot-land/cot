//===- GenericSpecializer.cpp - Monomorphize generic functions ----------===//
//
// CIR → CIR transformation: find cir.generic_apply ops, clone generic
// function bodies with concrete types, replace generic_apply with func.call.
//
// After this pass, no !cir.type_param or cir.generic_apply remains.
// All functions are concrete with fully resolved types.
//
// Architecture: Module-level pass (needs to clone functions across the module).
// Reference: Swift GenericSpecializer
//   ~/claude/references/swift/lib/SILOptimizer/Transforms/GenericSpecializer.cpp
//
//===----------------------------------------------------------------===//

#include "COT/Passes.h"
#include "CIR/CIROps.h"

#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/IR/IRMapping.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/Pass/Pass.h"

using namespace mlir;

namespace {

/// Build substitution map from generic_apply attributes.
/// Maps type parameter names to concrete types.
static llvm::DenseMap<StringRef, Type> buildSubstitutionMap(
    cir::GenericApplyOp applyOp) {
  llvm::DenseMap<StringRef, Type> subs;
  auto keys = applyOp.getSubsKeys();
  auto types = applyOp.getSubsTypes();
  for (size_t i = 0; i < keys.size(); i++) {
    auto key = llvm::cast<StringAttr>(keys[i]).getValue();
    auto type = llvm::cast<TypeAttr>(types[i]).getValue();
    subs[key] = type;
  }
  return subs;
}

/// Substitute !cir.type_param types with concrete types from the substitution map.
static Type substituteType(Type type,
                           const llvm::DenseMap<StringRef, Type> &subs) {
  if (auto param = llvm::dyn_cast<cir::TypeParamType>(type)) {
    auto it = subs.find(param.getName());
    if (it != subs.end())
      return it->second;
    return type; // unresolved — will be caught by verifier
  }
  // Recursively substitute in composite types
  if (auto optType = llvm::dyn_cast<cir::OptionalType>(type))
    return cir::OptionalType::get(type.getContext(),
        substituteType(optType.getPayloadType(), subs));
  if (auto euType = llvm::dyn_cast<cir::ErrorUnionType>(type))
    return cir::ErrorUnionType::get(type.getContext(),
        substituteType(euType.getPayloadType(), subs));
  if (auto refType = llvm::dyn_cast<cir::RefType>(type))
    return cir::RefType::get(type.getContext(),
        substituteType(refType.getPointeeType(), subs));
  if (auto arrType = llvm::dyn_cast<cir::ArrayType>(type))
    return cir::ArrayType::get(type.getContext(), arrType.getSize(),
        substituteType(arrType.getElementType(), subs));
  if (auto sliceType = llvm::dyn_cast<cir::SliceType>(type))
    return cir::SliceType::get(type.getContext(),
        substituteType(sliceType.getElementType(), subs));
  // Generic struct: substitute field types recursively.
  // Reference: Swift BoundGenericStructType substitution, Rust AdtDef with GenericArgsRef.
  // A generic struct like !cir.struct<"Pair", a: !cir.type_param<"T">, b: !cir.type_param<"T">>
  // becomes !cir.struct<"Pair_i32", a: i32, b: i32> after substitution.
  if (auto structType = llvm::dyn_cast<cir::StructType>(type)) {
    bool hasGenericField = false;
    for (auto ft : structType.getFieldTypes()) {
      if (substituteType(ft, subs) != ft) {
        hasGenericField = true;
        break;
      }
    }
    if (hasGenericField) {
      auto ctx = type.getContext();
      llvm::SmallVector<Type> newFieldTypes;
      for (auto ft : structType.getFieldTypes())
        newFieldTypes.push_back(substituteType(ft, subs));
      // Mangle struct name: append sanitized concrete type for each substituted field.
      // Must match the frontend's mangling (name_typeName).
      std::string newName(structType.getName());
      llvm::SmallPtrSet<const void *, 4> seenTypes;
      for (auto ft : structType.getFieldTypes()) {
        if (auto tp = llvm::dyn_cast<cir::TypeParamType>(ft)) {
          auto it = subs.find(tp.getName());
          if (it != subs.end() && seenTypes.insert(it->second.getAsOpaquePointer()).second) {
            newName += "_";
            std::string typeStr;
            llvm::raw_string_ostream os(typeStr);
            it->second.print(os);
            for (char c : typeStr) {
              if (std::isalnum(c) || c == '_')
                newName += c;
              else
                newName += '_';
            }
          }
        }
      }
      return cir::StructType::get(ctx, newName,
          structType.getFieldNames(), newFieldTypes);
    }
  }
  return type; // non-generic type — return as-is
}

/// Build a mangled name for a specialized function.
/// Sanitize type strings to produce valid C/LLVM symbol names.
/// Reference: Rust uses hash-based mangling; we use name-based for readability.
static std::string mangleName(StringRef baseName,
                               const llvm::DenseMap<StringRef, Type> &subs) {
  std::string mangled(baseName);
  for (auto &[key, type] : subs) {
    mangled += "_";
    // Print type to string, then sanitize for symbol name
    std::string typeStr;
    llvm::raw_string_ostream os(typeStr);
    type.print(os);
    // Replace invalid symbol characters with underscores
    for (char c : typeStr) {
      if (std::isalnum(c) || c == '_')
        mangled += c;
      else
        mangled += '_';
    }
  }
  return mangled;
}

/// Look up a witness table for the given (conforming type, protocol) pair.
/// Scans the module for cir.witness_table ops matching both.
/// Returns the method symbol for the given method name, or empty string.
static StringRef lookupWitnessMethod(
    ModuleOp module, Type conformingType,
    StringRef protocolName, StringRef methodName) {
  StringRef result;
  module.walk([&](cir::WitnessTableOp wt) {
    if (wt.getProtocolName() == protocolName &&
        wt.getConformingType() == conformingType) {
      auto names = wt.getMethodNames();
      auto impls = wt.getMethodImpls();
      for (size_t i = 0; i < names.size(); i++) {
        auto name = llvm::cast<StringAttr>(names[i]).getValue();
        if (name == methodName) {
          result = llvm::cast<FlatSymbolRefAttr>(impls[i]).getValue();
          return WalkResult::interrupt();
        }
      }
    }
    return WalkResult::advance();
  });
  return result;
}

/// Clone a generic function with type substitutions applied.
/// Returns the new specialized function, or nullptr on failure.
static func::FuncOp specializeFunction(
    func::FuncOp genericFn,
    const llvm::DenseMap<StringRef, Type> &subs,
    const std::string &specializedName,
    ModuleOp module) {

  OpBuilder builder(module.getContext());
  builder.setInsertionPointToEnd(module.getBody());

  // Build the specialized function type
  auto genericType = genericFn.getFunctionType();
  llvm::SmallVector<Type> newInputs;
  for (auto input : genericType.getInputs())
    newInputs.push_back(substituteType(input, subs));
  llvm::SmallVector<Type> newResults;
  for (auto result : genericType.getResults())
    newResults.push_back(substituteType(result, subs));
  auto specializedType = builder.getFunctionType(newInputs, newResults);


  // Create the new function
  auto specializedFn = func::FuncOp::create(
      genericFn.getLoc(), specializedName, specializedType);

  // Clone the body with type substitutions.
  // Two-pass approach: (1) create all blocks + map args, (2) clone ops.
  // This ensures forward block references (branches) are resolved.
  IRMapping mapping;

  // Pass 1: Create blocks, map arguments
  for (auto &block : genericFn.getBody()) {
    auto *newBlock = new Block();
    specializedFn.getBody().push_back(newBlock);
    mapping.map(&block, newBlock);

    for (auto arg : block.getArguments()) {
      auto newType = substituteType(arg.getType(), subs);
      auto newArg = newBlock->addArgument(newType, arg.getLoc());
      mapping.map(arg, newArg);
    }
  }

  // Pass 2: Clone operations into mapped blocks
  for (auto &block : genericFn.getBody()) {
    auto *newBlock = mapping.lookup(&block);
    builder.setInsertionPointToEnd(newBlock);

    for (auto &op : block) {
      auto *newOp = builder.clone(op, mapping);

      // Update result types
      for (unsigned i = 0; i < newOp->getNumResults(); i++) {
        auto oldType = newOp->getResult(i).getType();
        auto newType = substituteType(oldType, subs);
        if (oldType != newType)
          newOp->getResult(i).setType(newType);
      }

      // Update type-carrying attributes (alloca/field_ptr/elem_ptr elem_type)
      if (auto allocaOp = llvm::dyn_cast<cir::AllocaOp>(newOp)) {
        auto elemType = substituteType(allocaOp.getElemType(), subs);
        allocaOp.setElemTypeAttr(TypeAttr::get(elemType));
      }
      if (auto fpOp = llvm::dyn_cast<cir::FieldPtrOp>(newOp)) {
        auto elemType = substituteType(fpOp.getElemType(), subs);
        fpOp.setElemTypeAttr(TypeAttr::get(elemType));
      }
      if (auto epOp = llvm::dyn_cast<cir::ElemPtrOp>(newOp)) {
        auto elemType = substituteType(epOp.getElemType(), subs);
        epOp.setElemTypeAttr(TypeAttr::get(elemType));
      }
      if (auto atsOp = llvm::dyn_cast<cir::ArrayToSliceOp>(newOp)) {
        auto elemType = substituteType(atsOp.getElemType(), subs);
        atsOp.setElemTypeAttr(TypeAttr::get(elemType));
      }
    }
  }

  module.push_back(specializedFn);

  // Phase 7b: Resolve cir.trait_call ops in the specialized function.
  // For each trait_call, look up the witness table for the concrete type
  // and replace with a direct func.call to the concrete implementation.
  llvm::SmallVector<cir::TraitCallOp> traitCalls;
  specializedFn.walk([&](cir::TraitCallOp tc) {
    traitCalls.push_back(tc);
  });

  for (auto tc : traitCalls) {
    // The receiver's type tells us the concrete type
    // (it was already substituted from type_param to concrete)
    auto receiverType = tc.getOperands()[0].getType();
    auto implName = lookupWitnessMethod(
        module, receiverType, tc.getProtocolName(), tc.getMethodName());
    if (implName.empty()) {
      tc.emitError("cannot resolve trait method '")
          << tc.getMethodName() << "' on protocol '"
          << tc.getProtocolName() << "' for type " << receiverType;
      continue;
    }

    OpBuilder tcBuilder(tc);
    auto directCall = tcBuilder.create<func::CallOp>(
        tc.getLoc(), implName,
        tc.getResultTypes(),
        tc.getOperands());
    if (tc.getResult())
      tc.getResult().replaceAllUsesWith(directCall.getResult(0));
    tc.erase();
  }

  // Phase 7b+: Resolve cir.method_call ops (structural/duck dispatch).
  // For each method_call, search the module for a function with matching name
  // that accepts the concrete receiver type as its first parameter.
  // Reference: Zig Sema fieldCallBind() — name lookup on concrete type.
  llvm::SmallVector<cir::MethodCallOp> methodCalls;
  specializedFn.walk([&](cir::MethodCallOp mc) {
    methodCalls.push_back(mc);
  });

  for (auto mc : methodCalls) {
    auto receiverType = mc.getOperands()[0].getType();
    auto methodName = mc.getMethodName();
    StringRef resolvedName;

    // Strategy 1: Look for function with exact name matching first param type
    module.walk([&](func::FuncOp fn) {
      if (fn.getName() == methodName &&
          fn.getNumArguments() > 0 &&
          fn.getArgumentTypes()[0] == receiverType) {
        resolvedName = fn.getName();
        return WalkResult::interrupt();
      }
      return WalkResult::advance();
    });

    // Strategy 2: Search witness tables for any protocol mapping this method
    if (resolvedName.empty()) {
      module.walk([&](cir::WitnessTableOp wt) {
        if (wt.getConformingType() == receiverType) {
          auto names = wt.getMethodNames();
          auto impls = wt.getMethodImpls();
          for (size_t i = 0; i < names.size(); i++) {
            if (llvm::cast<StringAttr>(names[i]).getValue() == methodName) {
              resolvedName = llvm::cast<FlatSymbolRefAttr>(impls[i]).getValue();
              return WalkResult::interrupt();
            }
          }
        }
        return WalkResult::advance();
      });
    }

    if (resolvedName.empty()) {
      mc.emitError("cannot resolve method '")
          << mc.getMethodName() << "' for type " << receiverType
          << " (no matching function or witness table entry found)";
      continue;
    }

    OpBuilder mcBuilder(mc);
    auto directCall = mcBuilder.create<func::CallOp>(
        mc.getLoc(), resolvedName,
        mc.getResultTypes(),
        mc.getOperands());
    if (mc.getResult())
      mc.getResult().replaceAllUsesWith(directCall.getResult(0));
    mc.erase();
  }

  return specializedFn;
}

struct GenericSpecializerPass
    : public PassWrapper<GenericSpecializerPass, OperationPass<ModuleOp>> {
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(GenericSpecializerPass)

  StringRef getArgument() const override { return "cir-specialize"; }
  StringRef getDescription() const override {
    return "Monomorphize generic functions (resolve cir.generic_apply)";
  }

  void runOnOperation() override {
    auto module = getOperation();
    llvm::DenseSet<StringRef> specializedNames;


    // Collect all cir.generic_apply ops
    llvm::SmallVector<cir::GenericApplyOp> genericCalls;
    module.walk([&](cir::GenericApplyOp op) {
      genericCalls.push_back(op);
    });

    if (genericCalls.empty()) {
      return;
    }

    // Process each generic call
    for (auto applyOp : genericCalls) {
      // Build substitution map from attributes
      llvm::DenseMap<StringRef, Type> subs;
      auto keys = applyOp.getSubsKeys();
      auto types = applyOp.getSubsTypes();
      for (size_t i = 0; i < keys.size(); i++) {
        auto key = llvm::cast<StringAttr>(keys[i]).getValue();
        auto type = llvm::cast<TypeAttr>(types[i]).getValue();
        subs[key] = type;
      }

      auto callee = applyOp.getCallee();

      // Find the generic function
      auto genericFn = module.lookupSymbol<func::FuncOp>(callee);
      if (!genericFn) {
        applyOp.emitError("cannot find generic function '")
            << callee << "'";
        signalPassFailure();
        return;
      }

      // Build specialized name
      std::string specializedName = mangleName(callee, subs);

      // Specialize if not already done
      auto existingFn = module.lookupSymbol<func::FuncOp>(specializedName);
      if (!existingFn) {
        existingFn = specializeFunction(genericFn, subs, specializedName, module);
        if (!existingFn) {
          applyOp.emitError("failed to specialize '") << callee << "'";
          signalPassFailure();
          return;
        }
      }

      // Replace generic_apply with func.call to specialized version
      OpBuilder builder(applyOp);
      auto newCall = builder.create<func::CallOp>(
          applyOp.getLoc(), specializedName,
          existingFn.getResultTypes(),
          applyOp.getOperands());
      if (applyOp.getResult())
        applyOp.getResult().replaceAllUsesWith(newCall.getResult(0));
      applyOp.erase();
    }

    // Remove generic function templates (they're no longer needed)
    // Keep them if they might be used by other modules (public linkage)
    // For now: remove all generic functions that have type_param in signature
    llvm::SmallVector<func::FuncOp> toRemove;
    module.walk([&](func::FuncOp fn) {
      auto fnType = fn.getFunctionType();
      bool hasTypeParam = false;
      for (auto input : fnType.getInputs()) {
        if (llvm::isa<cir::TypeParamType>(input)) {
          hasTypeParam = true;
          break;
        }
      }
      if (!hasTypeParam) {
        for (auto result : fnType.getResults()) {
          if (llvm::isa<cir::TypeParamType>(result)) {
            hasTypeParam = true;
            break;
          }
        }
      }
      if (hasTypeParam) {
        toRemove.push_back(fn);
      }
    });
    for (auto fn : toRemove) {
      fn.erase();
    }
  }
};

} // namespace

std::unique_ptr<mlir::Pass> cot::createGenericSpecializerPass() {
  return std::make_unique<GenericSpecializerPass>();
}
