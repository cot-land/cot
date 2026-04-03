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

def CIR_StructType : CIR_Type<"Struct", "struct"> {
  let summary = "aggregate struct type";
  let description = [{
    Named aggregate type with ordered fields. Models C struct, Rust struct,
    Zig struct. The name identifies the type; fields are an ordered list of
    MLIR types.
    Reference: fir.type (FIR RecordType) in Flang.
  }];

  let parameters = (ins
    StringRefParameter<"struct name">:$name,
    ArrayRefParameter<"mlir::Type", "field types">:$fieldTypes
  );

  let genVerifyDecl = 1;
  let hasCustomAssemblyFormat = 1;
}

def CIR_ArrayType : CIR_Type<"Array", "array"> {
  let summary = "fixed-size array type";
  let description = [{
    Fixed-size homogeneous array. Models C arrays, Zig [N]T, Rust [T; N].
    Reference: fir.array (FIR SequenceType) in Flang.
  }];

  let parameters = (ins
    "int64_t":$size,
    "mlir::Type":$elementType
  );

  let hasCustomAssemblyFormat = 1;
}

#endif // CIR_TYPES
