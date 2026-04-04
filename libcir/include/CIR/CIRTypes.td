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
  let summary = "aggregate struct type with named fields";
  let description = [{
    Named aggregate type with ordered, named fields. Models C struct, Rust
    struct, Zig struct. Field names are stored for semantic resolution (field
    access by name → index). Names are dropped when lowering to LLVM.
    Reference: fir.type (FIR RecordType) in Flang — stores field names as
    TypePair<string, Type>.
    Syntax: !cir.struct<"Point", x: i32, y: i32>
  }];

  let parameters = (ins
    StringRefParameter<"struct name">:$name,
    ArrayRefParameter<"mlir::StringAttr", "field names">:$fieldNames,
    ArrayRefParameter<"mlir::Type", "field types">:$fieldTypes
  );

  let extraClassDeclaration = [{
    /// Get the index of a field by name. Returns -1 if not found.
    int getFieldIndex(llvm::StringRef fieldName) const;
  }];

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
