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

def CIR_RefType : CIR_Type<"Ref", "ref"> {
  let summary = "typed safe reference (non-null pointer with known pointee type)";
  let description = [{
    A safe, non-null reference to a value of type T in memory.
    Carries the pointee type for verification — load/deref result type must
    match the ref's pointee type.
    Lowers to !llvm.ptr (same as !cir.ptr) — zero runtime cost.

    Use !cir.ref<T> for safe code (Zig *T, Rust &T, ac &x).
    Use !cir.ptr for unsafe/C interop (raw pointers, malloc results).

    Reference: fir.ref<T> in Flang — typed reference to memory entity.
    Syntax: !cir.ref<i32>, !cir.ref<!cir.struct<"Point", x: i32, y: i32>>
  }];

  let parameters = (ins "mlir::Type":$pointeeType);
  let assemblyFormat = "`<` $pointeeType `>`";
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

def CIR_SliceType : CIR_Type<"Slice", "slice"> {
  let summary = "fat pointer slice type ({pointer, length})";
  let description = [{
    A slice is a {pointer, length} pair referencing a contiguous region of
    elements of type T. This is universal across languages:
    - Zig: []T = {ptr: [*]T, len: usize}
    - Rust: &[T] = {ptr: *const T, len: usize}
    - Go: []T = {ptr, len, cap} (CIR omits cap — that's a growable array)

    string = !cir.slice<i8>. No separate string type.

    Lowers to !llvm.struct<(!llvm.ptr, i64)> — zero-cost at runtime.

    Reference: Zig slice fat pointer, FIR fir.boxchar (string descriptor).
    Syntax: !cir.slice<i32>, !cir.slice<i8>
  }];

  let parameters = (ins "mlir::Type":$elementType);
  let assemblyFormat = "`<` $elementType `>`";
}

def CIR_OptionalType : CIR_Type<"Optional", "optional"> {
  let summary = "optional type (?T — value or null)";
  let description = [{
    A type that holds either a value of type T or null (none).
    This is Zig's ?T, Rust's Option<T>, Swift's Optional<T>.

    Null-pointer optimization: when T is a pointer type (!cir.ptr or
    !cir.ref<U>), the optional uses null as the none representation —
    no tag byte, zero runtime cost. For non-pointer T, lowers to
    !llvm.struct<(T, i1)> where i1 is the tag (1 = some, 0 = none).

    Reference: Zig ?T (InternPool opt_type), Rust Option<T> niche encoding.
    Syntax: !cir.optional<i32>, !cir.optional<!cir.ptr>
  }];

  let parameters = (ins "mlir::Type":$payloadType);
  let assemblyFormat = "`<` $payloadType `>`";

  let extraClassDeclaration = [{
    /// Returns true if this optional can use null-pointer optimization.
    /// True when payload is !cir.ptr or !cir.ref<T>.
    bool isPointerLike() const;
  }];
}

def CIR_ErrorUnionType : CIR_Type<"ErrorUnion", "error_union"> {
  let summary = "error union type (E!T — success value or error code)";
  let description = [{
    A type that holds either a success value of type T or an error code (i16).
    This is Zig's E!T, Rust's Result<T, E>.

    Error code 0 = success (payload is valid).
    Error code != 0 = error (payload is undefined).

    Lowers to !llvm.struct<(T, i16)> — payload first, error code second.
    No null-pointer optimization (unlike optionals, error unions always need
    the i16 tag to distinguish N+1 states).

    Error sets are a frontend concept — CIR only sees i16 error codes.
    Frontends map error names to integer codes.

    Reference: Zig E!T (InternPool ErrorUnionType), Rust Result<T,E>.
    Syntax: !cir.error_union<i32>, !cir.error_union<f64>
  }];

  let parameters = (ins "mlir::Type":$payloadType);
  let assemblyFormat = "`<` $payloadType `>`";
}

#endif // CIR_TYPES
