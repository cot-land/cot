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
// Memory — alloca, store, load
// Reference: LLVM dialect AllocaOp/StoreOp/LoadOp
//===----------------------------------------------------------------------===//

def CIR_AllocaOp : CIR_Op<"alloca"> {
  let summary = "stack allocation";
  let description = [{
    Allocates stack space for one value of the given type.
    Returns an opaque pointer (!cir.ptr).
    Zig: alloc. Swift: alloc_stack. Rust: StorageLive. Go: LocalAddr.
  }];

  let arguments = (ins TypeAttr:$elem_type);
  let results = (outs AnyType:$result);
  let assemblyFormat = "$elem_type attr-dict `:` type($result)";
}

def CIR_StoreOp : CIR_Op<"store"> {
  let summary = "store value to memory";
  let description = [{
    Stores a value to the address produced by cir.alloca.
  }];

  let arguments = (ins AnyType:$value, AnyType:$addr);
  let assemblyFormat = "$value `,` $addr attr-dict `:` type($value) `,` type($addr)";
}

def CIR_LoadOp : CIR_Op<"load"> {
  let summary = "load value from memory";
  let description = [{
    Loads a value from the address produced by cir.alloca.
  }];

  let arguments = (ins AnyType:$addr);
  let results = (outs AnyType:$result);
  let assemblyFormat = "$addr attr-dict `:` type($addr) `->` type($result)";
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
                       AnyType:$lhs, AnyType:$rhs);
  let results = (outs I1:$result);
  let assemblyFormat = "$predicate `,` $lhs `,` $rhs attr-dict `:` type($lhs)";
}

//===----------------------------------------------------------------------===//
// Control flow — branches and blocks
// Reference: mlir/Dialect/ControlFlow/IR/ControlFlowOps.td
//===----------------------------------------------------------------------===//

def CIR_BrOp : CIR_Op<"br", [Pure, Terminator]> {
  let summary = "unconditional branch";
  let arguments = (ins Variadic<AnyType>:$destOperands);
  let successors = (successor AnySuccessor:$dest);
  let assemblyFormat = [{
    $dest (`(` $destOperands^ `:` type($destOperands) `)`)? attr-dict
  }];
}

def CIR_CondBrOp : CIR_Op<"condbr", [Pure, Terminator]> {
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

def CIR_TrapOp : CIR_Op<"trap", [Terminator]> {
  let summary = "abort execution (assertion failure)";
  let description = [{
    Unconditional trap. Used by assert() on failure.
    Reference: llvm.trap intrinsic.
  }];
  let assemblyFormat = "attr-dict";
}

#endif // CIR_OPS
