//===- CIROps.td - CIR operation definitions -----------------*- tablegen -*-===//
//
// CIR (Cot Intermediate Representation) operations.
// Reference: Flang FIR dialect (~/claude/references/flang-ref/flang/)
//            MLIR Arith dialect (~/claude/references/llvm-project/mlir/)
//
//===----------------------------------------------------------------------===//

#ifndef CIR_OPS
#define CIR_OPS

include "CIR/CIRDialect.td"
include "mlir/IR/OpBase.td"
include "mlir/IR/EnumAttr.td"
include "mlir/Interfaces/CastInterfaces.td"
include "mlir/Interfaces/ControlFlowInterfaces.td"
include "mlir/Interfaces/InferTypeOpInterface.td"
include "mlir/Interfaces/SideEffectInterfaces.td"

//===----------------------------------------------------------------------===//
// Base classes — ported from FIR's fir_Op / fir_SimpleOp pattern
//===----------------------------------------------------------------------===//

/// Base class for all CIR ops.
class CIR_Op<string mnemonic, list<Trait> traits = []> :
    Op<CIR_Dialect, mnemonic, traits>;

/// Binary op on any type (int or float). Pure, same operand/result type.
/// Used by: add, sub, mul, div, rem
class CIR_BinaryOp<string mnemonic, list<Trait> traits = []> :
    CIR_Op<mnemonic, !listconcat([Pure, SameOperandsAndResultType], traits)> {
  let arguments = (ins AnyType:$lhs, AnyType:$rhs);
  let results = (outs AnyType:$result);
  let assemblyFormat = "$lhs `,` $rhs attr-dict `:` type($result)";
}

/// Binary op on integers only. Pure, same operand/result type.
/// Used by: bit_and, bit_or, xor, shl, shr
class CIR_IntBinaryOp<string mnemonic, list<Trait> traits = []> :
    CIR_Op<mnemonic, !listconcat([Pure, SameOperandsAndResultType], traits)> {
  let arguments = (ins AnyInteger:$lhs, AnyInteger:$rhs);
  let results = (outs AnyInteger:$result);
  let assemblyFormat = "$lhs `,` $rhs attr-dict `:` type($result)";
}

/// Unary op on integers only. Pure, same operand/result type.
/// Used by: neg, bit_not
class CIR_IntUnaryOp<string mnemonic, list<Trait> traits = []> :
    CIR_Op<mnemonic, !listconcat([Pure, SameOperandsAndResultType], traits)> {
  let arguments = (ins AnyInteger:$operand);
  let results = (outs AnyInteger:$result);
  let assemblyFormat = "$operand attr-dict `:` type($result)";
}

//===----------------------------------------------------------------------===//
// Constants
//===----------------------------------------------------------------------===//

def CIR_ConstantOp : CIR_Op<"constant", [Pure, ConstantLike]> {
  let summary = "integer/float/bool constant";
  let description = [{
    Produces a constant value. Every compiler IR has constant literals.
    Zig: int/float literal. Swift: integer_literal. Rust: Const operand.
  }];

  let arguments = (ins AnyAttr:$value);
  let results = (outs AnyType:$result);
  let hasCustomAssemblyFormat = 1;
  let hasVerifier = 1;
}

//===----------------------------------------------------------------------===//
// Arithmetic — present in every reference IR
//===----------------------------------------------------------------------===//

def CIR_AddOp : CIR_BinaryOp<"add", [Commutative]> { let summary = "integer/float addition"; }
def CIR_SubOp : CIR_BinaryOp<"sub"> { let summary = "integer/float subtraction"; }
def CIR_MulOp : CIR_BinaryOp<"mul", [Commutative]> { let summary = "integer/float multiplication"; }
def CIR_DivOp : CIR_BinaryOp<"div"> { let summary = "signed integer / float division"; }
def CIR_RemOp : CIR_BinaryOp<"rem"> { let summary = "signed integer remainder"; }
def CIR_NegOp : CIR_IntUnaryOp<"neg"> { let summary = "integer negation"; }

//===----------------------------------------------------------------------===//
// Bitwise — present in every reference IR
// Reference: ArithToLLVM AndI/OrI/XOrI lowering patterns
//===----------------------------------------------------------------------===//

def CIR_BitAndOp : CIR_IntBinaryOp<"bit_and", [Commutative]> { let summary = "bitwise AND"; }
def CIR_BitOrOp  : CIR_IntBinaryOp<"bit_or", [Commutative]>  { let summary = "bitwise OR"; }
def CIR_BitXorOp : CIR_IntBinaryOp<"bit_xor", [Commutative]> { let summary = "bitwise XOR"; }
def CIR_BitNotOp : CIR_IntUnaryOp<"bit_not">   { let summary = "bitwise NOT"; }

//===----------------------------------------------------------------------===//
// Shift — lowers to llvm.shl / llvm.lshr
// Reference: ArithToLLVM ShLI/ShRUI lowering patterns
//===----------------------------------------------------------------------===//

def CIR_ShlOp : CIR_IntBinaryOp<"shl"> { let summary = "shift left"; }
def CIR_ShrOp : CIR_IntBinaryOp<"shr"> { let summary = "logical shift right"; }

//===----------------------------------------------------------------------===//
// Type casts — separate ops per direction (Arith dialect pattern)
// Reference: mlir/Dialect/Arith/IR/ArithOps.td cast hierarchy
//
// Each op maps 1:1 to one LLVM op. No if/else chains in lowering.
// Sema pass inserts these at type boundaries.
//===----------------------------------------------------------------------===//

/// Base class for CIR cast ops. Pure, input → output of different type.
/// Reference: Arith_CastOp — CastOpInterface enables MLIR fold/verify infra.
class CIR_CastOp<string mnemonic, TypeConstraint From, TypeConstraint To,
                  list<Trait> traits = []> :
    CIR_Op<mnemonic, !listconcat([Pure,
      DeclareOpInterfaceMethods<CastOpInterface>], traits)> {
  let arguments = (ins From:$input);
  let results = (outs To:$result);
  let assemblyFormat = "$input attr-dict `:` type($input) `to` type($result)";
}

/// Integer → integer cast (ext/trunc). Verifier checks width.
class CIR_IToICastOp<string mnemonic, list<Trait> traits = []> :
    CIR_CastOp<mnemonic, AnyInteger, AnyInteger, traits>;

/// Integer → float cast.
class CIR_IToFCastOp<string mnemonic, list<Trait> traits = []> :
    CIR_CastOp<mnemonic, AnyInteger, AnyFloat, traits>;

/// Float → integer cast.
class CIR_FToICastOp<string mnemonic, list<Trait> traits = []> :
    CIR_CastOp<mnemonic, AnyFloat, AnyInteger, traits>;

/// Float → float cast (ext/trunc). Verifier checks width.
class CIR_FToFCastOp<string mnemonic, list<Trait> traits = []> :
    CIR_CastOp<mnemonic, AnyFloat, AnyFloat, traits>;

// Integer → integer
def CIR_ExtSIOp  : CIR_IToICastOp<"extsi">  {
  let summary = "sign-extend integer (src narrower than dst)";
  let hasVerifier = 1;
}
def CIR_ExtUIOp  : CIR_IToICastOp<"extui">  {
  let summary = "zero-extend integer (src narrower than dst)";
  let hasVerifier = 1;
}
def CIR_TruncIOp : CIR_IToICastOp<"trunci"> {
  let summary = "truncate integer (src wider than dst)";
  let hasVerifier = 1;
}

// Integer ↔ float
def CIR_SIToFPOp : CIR_IToFCastOp<"sitofp"> { let summary = "signed int to float"; }
def CIR_FPToSIOp : CIR_FToICastOp<"fptosi"> { let summary = "float to signed int"; }

// Float → float
def CIR_ExtFOp   : CIR_FToFCastOp<"extf">   {
  let summary = "extend float (f32 to f64)";
  let hasVerifier = 1;
}
def CIR_TruncFOp : CIR_FToFCastOp<"truncf"> {
  let summary = "truncate float (f64 to f32)";
  let hasVerifier = 1;
}

//===----------------------------------------------------------------------===//
// Memory — alloca, store, load
// Reference: LLVM dialect AllocaOp/StoreOp/LoadOp
//===----------------------------------------------------------------------===//

def CIR_AllocaOp : CIR_Op<"alloca", [MemoryEffects<[MemAlloc<DefaultResource>]>]> {
  let summary = "stack allocation";
  let description = [{
    Allocates stack space for one value of the given type.
    Returns an opaque pointer (!cir.ptr).
    Zig: alloc. Swift: alloc_stack. Rust: StorageLive. Go: LocalAddr.
  }];

  let arguments = (ins TypeAttr:$elem_type);
  let results = (outs AnyType:$result);
  let assemblyFormat = "$elem_type attr-dict `:` type($result)";
  let hasVerifier = 1;
}

def CIR_StoreOp : CIR_Op<"store", [MemoryEffects<[MemWrite<DefaultResource>]>]> {
  let summary = "store value to memory";
  let description = [{
    Stores a value to the address produced by cir.alloca.
    Address must be !cir.ptr.
  }];

  let arguments = (ins AnyType:$value, AnyType:$addr);
  let assemblyFormat = "$value `,` $addr attr-dict `:` type($value) `,` type($addr)";
  let hasVerifier = 1;
}

def CIR_LoadOp : CIR_Op<"load", [MemoryEffects<[MemRead<DefaultResource>]>]> {
  let summary = "load value from memory";
  let description = [{
    Loads a value from the address produced by cir.alloca.
    Address must be !cir.ptr.
  }];

  let arguments = (ins AnyType:$addr);
  let results = (outs AnyType:$result);
  let assemblyFormat = "$addr attr-dict `:` type($addr) `to` type($result)";
  let hasVerifier = 1;
}

//===----------------------------------------------------------------------===//
// Address-of and dereference — typed reference operations
// Reference: FIR fir.ref / Zig &x / Rust &x
//===----------------------------------------------------------------------===//

def CIR_AddrOfOp : CIR_Op<"addr_of", [Pure]> {
  let summary = "take address of a local (alloca ptr → typed ref)";
  let description = [{
    Converts a raw alloca pointer (!cir.ptr) into a typed safe reference
    (!cir.ref<T>). This is the address-of operation (&x).
    The pointee type is specified in the result ref type.

    Lowering: identity — both !cir.ptr and !cir.ref<T> lower to !llvm.ptr.

    Example:
      %r = cir.addr_of %alloca : !cir.ptr to !cir.ref<i32>
  }];

  let arguments = (ins AnyType:$addr);
  let results = (outs AnyType:$result);
  let assemblyFormat = "$addr attr-dict `:` type($addr) `to` type($result)";
  let hasVerifier = 1;
}

def CIR_DerefOp : CIR_Op<"deref", [Pure]> {
  let summary = "dereference a typed reference (load through ref)";
  let description = [{
    Loads the value pointed to by a typed reference (!cir.ref<T>).
    Result type must match the ref's pointee type.
    This is the dereference operation (*p or p.*).

    Lowering: llvm.load (same as cir.load but type-safe).

    Example:
      %v = cir.deref %r : !cir.ref<i32> to i32
  }];

  let arguments = (ins AnyType:$ref);
  let results = (outs AnyType:$result);
  let assemblyFormat = "$ref attr-dict `:` type($ref) `to` type($result)";
  let hasVerifier = 1;
}

//===----------------------------------------------------------------------===//
// Comparison predicate enum
// Reference: mlir/include/mlir/Dialect/Arith/IR/ArithBase.td CmpIPredicate
//===----------------------------------------------------------------------===//

def CIR_CmpIPredicate_eq  : I64EnumAttrCase<"eq", 0>;
def CIR_CmpIPredicate_ne  : I64EnumAttrCase<"ne", 1>;
def CIR_CmpIPredicate_slt : I64EnumAttrCase<"slt", 2>;
def CIR_CmpIPredicate_sle : I64EnumAttrCase<"sle", 3>;
def CIR_CmpIPredicate_sgt : I64EnumAttrCase<"sgt", 4>;
def CIR_CmpIPredicate_sge : I64EnumAttrCase<"sge", 5>;

def CIR_CmpIPredicateAttr : I64EnumAttr<
    "CmpIPredicate", "integer comparison predicate",
    [CIR_CmpIPredicate_eq, CIR_CmpIPredicate_ne,
     CIR_CmpIPredicate_slt, CIR_CmpIPredicate_sle,
     CIR_CmpIPredicate_sgt, CIR_CmpIPredicate_sge]> {
  let cppNamespace = "::cir";
}

//===----------------------------------------------------------------------===//
// Comparison — lowers to llvm.icmp with predicate
// Reference: ArithToLLVM CmpIOpLowering
//===----------------------------------------------------------------------===//

def CIR_CmpOp : CIR_Op<"cmp", [Pure, SameTypeOperands]> {
  let summary = "integer comparison with predicate";
  let description = [{
    Compares two integers using a named predicate.
    Predicate values match LLVM::ICmpPredicate for direct lowering.
  }];

  let arguments = (ins CIR_CmpIPredicateAttr:$predicate,
                       AnyInteger:$lhs, AnyInteger:$rhs);
  let results = (outs I1:$result);
  let assemblyFormat = "$predicate `,` $lhs `,` $rhs attr-dict `:` type($lhs)";
}

//===----------------------------------------------------------------------===//
// Control flow — branches and blocks
// Reference: mlir/Dialect/ControlFlow/IR/ControlFlowOps.td
//===----------------------------------------------------------------------===//

def CIR_BrOp : CIR_Op<"br",
    [Pure, Terminator,
     DeclareOpInterfaceMethods<BranchOpInterface>]> {
  let summary = "unconditional branch";
  let arguments = (ins Variadic<AnyType>:$destOperands);
  let successors = (successor AnySuccessor:$dest);
  let assemblyFormat = [{
    $dest (`(` $destOperands^ `:` type($destOperands) `)`)? attr-dict
  }];
}

def CIR_CondBrOp : CIR_Op<"condbr",
    [Pure, Terminator,
     DeclareOpInterfaceMethods<BranchOpInterface>]> {
  let summary = "conditional branch";
  let arguments = (ins I1:$condition);
  let successors = (successor AnySuccessor:$trueDest,
                              AnySuccessor:$falseDest);
  let assemblyFormat =
      "$condition `,` $trueDest `,` $falseDest attr-dict";
}

//===----------------------------------------------------------------------===//
// Select — conditional value (ternary)
// Reference: arith::SelectOp, llvm::SelectOp
//===----------------------------------------------------------------------===//

def CIR_SelectOp : CIR_Op<"select", [Pure,
    AllTypesMatch<["trueValue", "falseValue", "result"]>]> {
  let summary = "select value based on condition";
  let description = [{
    Returns trueValue if condition is true, falseValue otherwise.
    Both values are computed eagerly (no short-circuit).
    Reference: arith.select / llvm.select pattern.
  }];

  let arguments = (ins I1:$condition, AnyType:$trueValue, AnyType:$falseValue);
  let results = (outs AnyType:$result);
  let assemblyFormat =
      "$condition `,` $trueValue `,` $falseValue attr-dict `:` type($result)";
}

//===----------------------------------------------------------------------===//
// Aggregate construction — struct values from fields
// Reference: FIR fir.undefined + fir.insert_value chain
//            LLVM llvm.mlir.undef + llvm.insertvalue chain
//===----------------------------------------------------------------------===//

def CIR_StructInitOp : CIR_Op<"struct_init", [Pure]> {
  let summary = "construct aggregate struct value from field values";
  let description = [{
    Constructs a struct value from individual field values in order.
    Operands are positional — operand 0 is field 0, operand 1 is field 1, etc.
    Result type is a !cir.struct.

    Lowers to llvm.mlir.undef + llvm.insertvalue chain (FIR pattern).

    Example:
      %p = cir.struct_init(%x, %y) : !cir.struct<"Point", x: i32, y: i32>
  }];

  let arguments = (ins Variadic<AnyType>:$fields);
  let results = (outs AnyType:$result);
  let hasCustomAssemblyFormat = 1;
  let hasVerifier = 1;
}

//===----------------------------------------------------------------------===//
// Aggregate field access — extract/address struct fields
// Reference: FIR fir.extract_value / fir.coordinate_of
//            LLVM llvm.extractvalue / llvm.getelementptr
//===----------------------------------------------------------------------===//

def CIR_FieldValOp : CIR_Op<"field_val", [Pure]> {
  let summary = "extract field value from struct";
  let description = [{
    Extracts a named field from a struct SSA value.
    The field_index attribute specifies which field to extract (0-based).
    Result type is the field's type.

    Lowers to llvm.extractvalue (FIR extract_value pattern).

    Example:
      %x = cir.field_val %p, 0 : !cir.struct<"Point", x: i32, y: i32> -> i32
  }];

  let arguments = (ins AnyType:$input, I64Attr:$field_index);
  let results = (outs AnyType:$result);
  let assemblyFormat =
      "$input `,` $field_index attr-dict `:` type($input) `to` type($result)";
  let hasVerifier = 1;
}

def CIR_FieldPtrOp : CIR_Op<"field_ptr", [Pure]> {
  let summary = "get pointer to struct field";
  let description = [{
    Given a pointer to a struct, returns a pointer to the named field.
    The field_index attribute specifies which field (0-based).
    Result type is !cir.ptr.

    Lowers to llvm.getelementptr with struct indices [0, field_index].

    Example:
      %xp = cir.field_ptr %pp, 0 {elem_type = !cir.struct<"Point", x: i32, y: i32>}
            : !cir.ptr -> !cir.ptr
  }];

  let arguments = (ins AnyType:$base, I64Attr:$field_index,
                       TypeAttr:$elem_type);
  let results = (outs AnyType:$result);
  let assemblyFormat =
      "$base `,` $field_index attr-dict `:` type($base) `to` type($result)";
  let hasVerifier = 1;
}

//===----------------------------------------------------------------------===//
// Array construction and element access
// Reference: FIR fir.insert_value chain / fir.extract_value / fir.coordinate_of
//            LLVM llvm.insertvalue / llvm.extractvalue / llvm.getelementptr
//===----------------------------------------------------------------------===//

def CIR_ArrayInitOp : CIR_Op<"array_init", [Pure]> {
  let summary = "construct array value from element values";
  let description = [{
    Constructs a fixed-size array from individual element values.
    Operands are positional — operand 0 is element 0, etc.
    Result type is a !cir.array.

    Lowers to llvm.mlir.undef + llvm.insertvalue chain.

    Example:
      %a = cir.array_init(%x, %y, %z) : !cir.array<3 x i32>
  }];

  let arguments = (ins Variadic<AnyType>:$elements);
  let results = (outs AnyType:$result);
  let hasCustomAssemblyFormat = 1;
  let hasVerifier = 1;
}

def CIR_ElemValOp : CIR_Op<"elem_val", [Pure]> {
  let summary = "extract element value from array by constant index";
  let description = [{
    Extracts an element from an array SSA value at a constant index.
    Lowers to llvm.extractvalue.

    Example:
      %v = cir.elem_val %arr, 0 : !cir.array<4 x i32> -> i32
  }];

  let arguments = (ins AnyType:$input, I64Attr:$index);
  let results = (outs AnyType:$result);
  let assemblyFormat =
      "$input `,` $index attr-dict `:` type($input) `to` type($result)";
  let hasVerifier = 1;
}

def CIR_ElemPtrOp : CIR_Op<"elem_ptr", [Pure]> {
  let summary = "get pointer to array element by dynamic index";
  let description = [{
    Given a pointer to an array, returns a pointer to the element at
    the given runtime index. Lowers to llvm.getelementptr.

    Example:
      %ep = cir.elem_ptr %arr_ptr, %idx {elem_type = !cir.array<4 x i32>}
            : (!cir.ptr, i32) -> !cir.ptr
  }];

  let arguments = (ins AnyType:$base, AnyInteger:$index,
                       TypeAttr:$elem_type);
  let results = (outs AnyType:$result);
  let assemblyFormat =
      "$base `,` $index attr-dict `:` `(` type($base) `,` type($index) `)` `->` type($result)";
  let hasVerifier = 1;
}

def CIR_TrapOp : CIR_Op<"trap", [Terminator]> {
  let summary = "abort execution (assertion failure)";
  let description = [{
    Unconditional trap. Used by assert() on failure.
    Reference: llvm.trap intrinsic.
  }];
  let assemblyFormat = "attr-dict";
}

//===----------------------------------------------------------------------===//
// String/Slice operations
// Reference: Zig slice fat pointer, FIR fir.boxchar, llvm.mlir.global
//===----------------------------------------------------------------------===//

def CIR_StringConstantOp : CIR_Op<"string_constant", [Pure]> {
  let summary = "string literal → slice<i8> constant";
  let description = [{
    Materializes a string literal as a global constant array and returns
    a !cir.slice<i8> fat pointer {ptr, len}.

    Lowers to: llvm.mlir.global + llvm.mlir.addressof + undef/insertvalue.

    Reference: Zig string literals become []const u8 slices. FIR boxchar
    wraps character data with a descriptor.

    Example:
      %s = cir.string_constant "hello" : !cir.slice<i8>
  }];

  let arguments = (ins StrAttr:$value);
  let results = (outs AnyType:$result);
  let assemblyFormat = "$value attr-dict `:` type($result)";
  let hasVerifier = 1;
}

def CIR_SlicePtrOp : CIR_Op<"slice_ptr", [Pure]> {
  let summary = "extract pointer from slice";
  let description = [{
    Extracts the data pointer from a !cir.slice<T>.
    Returns !cir.ptr (raw pointer to the first element).

    Lowers to: llvm.extractvalue [0] (ptr field of fat pointer struct).

    Example:
      %p = cir.slice_ptr %s : !cir.slice<i32> to !cir.ptr
  }];

  let arguments = (ins AnyType:$input);
  let results = (outs AnyType:$result);
  let assemblyFormat = "$input attr-dict `:` type($input) `to` type($result)";
  let hasVerifier = 1;
}

def CIR_SliceLenOp : CIR_Op<"slice_len", [Pure]> {
  let summary = "extract length from slice";
  let description = [{
    Extracts the length from a !cir.slice<T>. Returns i64.

    Lowers to: llvm.extractvalue [1] (len field of fat pointer struct).

    Example:
      %n = cir.slice_len %s : !cir.slice<i32> to i64
  }];

  let arguments = (ins AnyType:$input);
  let results = (outs AnyType:$result);
  let assemblyFormat = "$input attr-dict `:` type($input) `to` type($result)";
  let hasVerifier = 1;
}

def CIR_SliceElemOp : CIR_Op<"slice_elem", [Pure]> {
  let summary = "index into slice (unchecked)";
  let description = [{
    Loads the element at index %idx from a !cir.slice<T>.
    Extracts the pointer, GEPs to the element, and loads it.
    No bounds checking (safety passes can add cir.bounds_check before this).

    Lowers to: extractvalue [0] (ptr) + GEP + load.

    Example:
      %v = cir.slice_elem %s, %i : !cir.slice<i32>, i64 to i32
  }];

  let arguments = (ins AnyType:$input, AnyInteger:$index);
  let results = (outs AnyType:$result);
  let assemblyFormat =
      "$input `,` $index attr-dict `:` type($input) `,` type($index) `to` type($result)";
  let hasVerifier = 1;
}

def CIR_ArrayToSliceOp : CIR_Op<"array_to_slice", [Pure]> {
  let summary = "create slice from array pointer + range";
  let description = [{
    Constructs a !cir.slice<T> from a pointer to an array and a start/end
    index pair. The result slice points to arr[start] with length (end - start).

    The base must be !cir.ptr (pointer to an array on the stack).
    start and end are i64 indices.

    Lowers to: GEP for start pointer + sub for length + struct construction.

    Example:
      %s = cir.array_to_slice %arr_ptr, %lo, %hi
            {elem_type = !cir.array<4 x i32>}
            : (!cir.ptr, i64, i64) -> !cir.slice<i32>
  }];

  let arguments = (ins AnyType:$base, AnyInteger:$start, AnyInteger:$end,
                       TypeAttr:$elem_type);
  let results = (outs AnyType:$result);
  let assemblyFormat =
      "$base `,` $start `,` $end attr-dict `:`"
      " `(` type($base) `,` type($start) `,` type($end) `)` `->` type($result)";
  let hasVerifier = 1;
}

//===----------------------------------------------------------------------===//
// Optional operations
// Reference: Zig ?T — is_non_null, optional_payload_unsafe, null
//===----------------------------------------------------------------------===//

def CIR_NoneOp : CIR_Op<"none", [Pure]> {
  let summary = "null optional constant";
  let description = [{
    Produces the null/none value for an optional type.
    Reference: Zig null literal.
    Example:
      %n = cir.none : !cir.optional<i32>
  }];
  let results = (outs AnyType:$result);
  let assemblyFormat = "attr-dict `:` type($result)";
  let hasVerifier = 1;
}

def CIR_WrapOptionalOp : CIR_Op<"wrap_optional", [Pure]> {
  let summary = "wrap value in optional (T → ?T)";
  let description = [{
    Wraps a non-optional value into an optional (the Some case).
    Reference: Zig implicit T → ?T coercion.
    Example:
      %opt = cir.wrap_optional %val : i32 to !cir.optional<i32>
  }];
  let arguments = (ins AnyType:$input);
  let results = (outs AnyType:$result);
  let assemblyFormat = "$input attr-dict `:` type($input) `to` type($result)";
  let hasVerifier = 1;
}

def CIR_IsNonNullOp : CIR_Op<"is_non_null", [Pure]> {
  let summary = "test optional for non-null → i1";
  let description = [{
    Returns true (i1) if the optional contains a value, false if null.
    Reference: Zig is_non_null ZIR instruction.
    Example:
      %b = cir.is_non_null %opt : !cir.optional<i32> to i1
  }];
  let arguments = (ins AnyType:$input);
  let results = (outs I1:$result);
  let assemblyFormat = "$input attr-dict `:` type($input) `to` type($result)";
  let hasVerifier = 1;
}

def CIR_OptionalPayloadOp : CIR_Op<"optional_payload", [Pure]> {
  let summary = "extract value from optional (unchecked)";
  let description = [{
    Extracts the payload from an optional. Unchecked — caller must have
    already branched on cir.is_non_null. Safety passes can add checks.
    Reference: Zig optional_payload_unsafe ZIR instruction.
    Example:
      %val = cir.optional_payload %opt : !cir.optional<i32> to i32
  }];
  let arguments = (ins AnyType:$input);
  let results = (outs AnyType:$result);
  let assemblyFormat = "$input attr-dict `:` type($input) `to` type($result)";
  let hasVerifier = 1;
}

//===----------------------------------------------------------------------===//
// Error union operations
// Reference: Zig E!T — wrap_errunion_payload, wrap_errunion_err, is_err,
//            unwrap_errunion_payload, unwrap_errunion_err
//===----------------------------------------------------------------------===//

def CIR_WrapResultOp : CIR_Op<"wrap_result", [Pure]> {
  let summary = "wrap success value in error union (T → E!T)";
  let description = [{
    Wraps a non-error value into an error union (the success case).
    Sets error_code = 0 (no error).
    Reference: Zig wrap_errunion_payload AIR instruction.
    Example:
      %eu = cir.wrap_result %val : i32 to !cir.error_union<i32>
  }];
  let arguments = (ins AnyType:$input);
  let results = (outs AnyType:$result);
  let assemblyFormat = "$input attr-dict `:` type($input) `to` type($result)";
  let hasVerifier = 1;
}

def CIR_WrapErrorOp : CIR_Op<"wrap_error", [Pure]> {
  let summary = "wrap error code in error union (i16 → E!T)";
  let description = [{
    Wraps an error code into an error union (the error case).
    Payload is undefined. Error code must be nonzero.
    Reference: Zig wrap_errunion_err AIR instruction.
    Example:
      %eu = cir.wrap_error %code : i16 to !cir.error_union<i32>
  }];
  let arguments = (ins AnyInteger:$input);
  let results = (outs AnyType:$result);
  let assemblyFormat = "$input attr-dict `:` type($input) `to` type($result)";
  let hasVerifier = 1;
}

def CIR_IsErrorOp : CIR_Op<"is_error", [Pure]> {
  let summary = "test error union for error → i1";
  let description = [{
    Returns true (i1) if the error union contains an error, false if success.
    Reference: Zig is_err AIR instruction.
    Example:
      %b = cir.is_error %eu : !cir.error_union<i32> to i1
  }];
  let arguments = (ins AnyType:$input);
  let results = (outs I1:$result);
  let assemblyFormat = "$input attr-dict `:` type($input) `to` type($result)";
  let hasVerifier = 1;
}

def CIR_ErrorPayloadOp : CIR_Op<"error_payload", [Pure]> {
  let summary = "extract success value from error union (unchecked)";
  let description = [{
    Extracts the payload from an error union. Unchecked — caller must have
    already branched on cir.is_error. Safety passes can add checks.
    Reference: Zig unwrap_errunion_payload AIR instruction.
    Example:
      %val = cir.error_payload %eu : !cir.error_union<i32> to i32
  }];
  let arguments = (ins AnyType:$input);
  let results = (outs AnyType:$result);
  let assemblyFormat = "$input attr-dict `:` type($input) `to` type($result)";
  let hasVerifier = 1;
}

def CIR_ErrorCodeOp : CIR_Op<"error_code", [Pure]> {
  let summary = "extract error code from error union";
  let description = [{
    Extracts the i16 error code from an error union. Returns 0 if the
    error union holds a success value.
    Reference: Zig unwrap_errunion_err AIR instruction.
    Example:
      %code = cir.error_code %eu : !cir.error_union<i32> to i16
  }];
  let arguments = (ins AnyType:$input);
  let results = (outs AnyType:$result);
  let assemblyFormat = "$input attr-dict `:` type($input) `to` type($result)";
  let hasVerifier = 1;
}

//===----------------------------------------------------------------------===//
// Exception-based error handling
// Reference: LLVM InvokeOp/LandingpadOp, Swift try_apply
// Alternative to error unions — frontends choose which model fits.
// TS/Java/C#/C++ use exceptions. Zig/Rust use error unions. Both in CIR.
//===----------------------------------------------------------------------===//

def CIR_ThrowOp : CIR_Op<"throw", [Terminator]> {
  let summary = "throw an exception value";
  let description = [{
    Throws an exception value. Transfers control to the nearest enclosing
    catch handler via stack unwinding.

    Lowers to: __cxa_allocate_exception + __cxa_throw (C++ ABI), or
    a simpler runtime call for languages without C++ interop.

    Reference: LLVM resume instruction, C++ throw expression.

    Example:
      cir.throw %val : i32
  }];
  let arguments = (ins AnyType:$value);
  let assemblyFormat = "$value attr-dict `:` type($value)";
}

def CIR_InvokeOp : CIR_Op<"invoke",
    [Terminator, DeclareOpInterfaceMethods<BranchOpInterface>]> {
  let summary = "call that may throw — normal/unwind successors";
  let description = [{
    Calls a function that may throw an exception. If the call returns
    normally, control transfers to normalDest. If it throws, control
    transfers to unwindDest (which must begin with cir.landingpad).

    This is LLVM's invoke instruction. Used by languages with exception-
    based error handling (TypeScript, Java, C#, C++, Python).

    Reference: LLVM InvokeOp, Swift try_apply.

    Example:
      %r = cir.invoke @may_throw(%arg) : (i32) -> i32
            normal ^ok unwind ^catch
  }];
  let arguments = (ins FlatSymbolRefAttr:$callee,
                       Variadic<AnyType>:$operands);
  let results = (outs Optional<AnyType>:$result);
  let successors = (successor AnySuccessor:$normalDest,
                              AnySuccessor:$unwindDest);
  let assemblyFormat = [{
    $callee `(` $operands `)` attr-dict `:` functional-type($operands, results)
    `normal` $normalDest `unwind` $unwindDest
  }];
}

def CIR_LandingPadOp : CIR_Op<"landingpad", [Pure]> {
  let summary = "catch thrown exception value";
  let description = [{
    Catches an exception at the start of an unwind block. Returns the
    caught exception value. Must be the first op in a block that is
    the unwind destination of a cir.invoke.

    For simplicity, CIR's landingpad catches all exceptions (catch-all).
    Type-specific catching can be added later via catch clause attributes.

    Lowers to: llvm.landingpad (catch null) + __cxa_begin_catch.

    Reference: LLVM LandingpadOp, C++ catch(...).

    Example:
      %exc = cir.landingpad : i32
  }];
  let results = (outs AnyType:$result);
  let assemblyFormat = "attr-dict `:` type($result)";
}

#endif // CIR_OPS
