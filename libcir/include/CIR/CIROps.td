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

def CIR_AddOp : CIR_BinaryOp<"add"> { let summary = "integer/float addition"; }
def CIR_SubOp : CIR_BinaryOp<"sub"> { let summary = "integer/float subtraction"; }
def CIR_MulOp : CIR_BinaryOp<"mul"> { let summary = "integer/float multiplication"; }
def CIR_DivOp : CIR_BinaryOp<"div"> { let summary = "signed integer / float division"; }
def CIR_RemOp : CIR_BinaryOp<"rem"> { let summary = "signed integer remainder"; }
def CIR_NegOp : CIR_IntUnaryOp<"neg"> { let summary = "integer negation"; }

//===----------------------------------------------------------------------===//
// Bitwise — present in every reference IR
// Reference: ArithToLLVM AndI/OrI/XOrI lowering patterns
//===----------------------------------------------------------------------===//

def CIR_BitAndOp : CIR_IntBinaryOp<"bit_and"> { let summary = "bitwise AND"; }
def CIR_BitOrOp  : CIR_IntBinaryOp<"bit_or">  { let summary = "bitwise OR"; }
def CIR_XorOp    : CIR_IntBinaryOp<"xor">     { let summary = "bitwise XOR"; }
def CIR_BitNotOp : CIR_IntUnaryOp<"bit_not">   { let summary = "bitwise NOT"; }

//===----------------------------------------------------------------------===//
// Shift — lowers to llvm.shl / llvm.lshr
// Reference: ArithToLLVM ShLI/ShRUI lowering patterns
//===----------------------------------------------------------------------===//

def CIR_ShlOp : CIR_IntBinaryOp<"shl"> { let summary = "shift left"; }
def CIR_ShrOp : CIR_IntBinaryOp<"shr"> { let summary = "logical shift right"; }

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
                       AnyType:$lhs, AnyType:$rhs);
  let results = (outs I1:$result);
  let assemblyFormat = "$predicate `,` $lhs `,` $rhs attr-dict `:` type($lhs)";
}

//===----------------------------------------------------------------------===//
// Control flow
//===----------------------------------------------------------------------===//

def CIR_TrapOp : CIR_Op<"trap", [Terminator]> {
  let summary = "abort execution (assertion failure)";
  let description = [{
    Unconditional trap. Used by assert() on failure.
    Reference: llvm.trap intrinsic.
  }];
  let assemblyFormat = "attr-dict";
}

#endif // CIR_OPS
