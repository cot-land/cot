//===- CIRTypes.td - CIR type definitions --------------------*- tablegen -*-===//
//
// CIR custom types. Reference: FIR's FIRTypes.td
//   ~/claude/references/flang-ref/flang/include/flang/Optimizer/Dialect/FIRTypes.td
//
//===----------------------------------------------------------------------===//

#ifndef CIR_TYPES
#define CIR_TYPES

include "CIR/CIRDialect.td"
include "mlir/IR/AttrTypeBase.td"

/// Base class for all CIR types.
class CIR_Type<string name, string typeMnemonic, list<Trait> traits = []>
    : TypeDef<CIR_Dialect, name, traits> {
  let mnemonic = typeMnemonic;
}

def CIR_PointerType : CIR_Type<"Pointer", "ptr"> {
  let summary = "opaque pointer type (address of a stack/heap value)";
  let description = [{
    Represents a pointer to memory. Opaque (no element type parameter),
    matching LLVM's modern opaque pointer design.
    Used by cir.alloca, cir.load, cir.store.
  }];
}

#endif // CIR_TYPES
