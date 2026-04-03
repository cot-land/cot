//===- CIROps.td - CIR operation definitions -----------------*- tablegen -*-===//
//
// Minimal CIR ops for gate test 1: add(19, 23) = 42
//
// For gate test 1, functions use MLIR's built-in func.func.
// CIR-specific cir.func will be added when we need CIR function semantics
// (comptime params, error return types, calling conventions, etc.)
//
//===----------------------------------------------------------------------===//

#ifndef CIR_OPS
#define CIR_OPS

include "CIR/CIRDialect.td"
include "mlir/IR/OpBase.td"
include "mlir/Interfaces/InferTypeOpInterface.td"
include "mlir/Interfaces/SideEffectInterfaces.td"

// Base class for all CIR ops
class CIR_Op<string mnemonic, list<Trait> traits = []> :
    Op<CIR_Dialect, mnemonic, traits>;

//===----------------------------------------------------------------------===//
// Constants
//===----------------------------------------------------------------------===//

def CIR_ConstantOp : CIR_Op<"constant", [Pure]> {
  let summary = "integer/float/bool constant";
  let description = [{
    Produces a constant value. Every compiler IR has constant literals.
    Zig: int/float literal. Swift: integer_literal. Rust: Const operand. Go: ConstXX.
  }];

  let arguments = (ins AnyAttr:$value);
  let results = (outs AnyType:$result);
  let hasCustomAssemblyFormat = 1;
}

//===----------------------------------------------------------------------===//
// Arithmetic — present in every reference IR
//===----------------------------------------------------------------------===//

def CIR_AddOp : CIR_Op<"add", [Pure, SameOperandsAndResultType]> {
  let summary = "integer/float addition";
  let arguments = (ins AnyType:$lhs, AnyType:$rhs);
  let results = (outs AnyType:$result);
  let assemblyFormat = "$lhs `,` $rhs attr-dict `:` type($result)";
}

def CIR_SubOp : CIR_Op<"sub", [Pure, SameOperandsAndResultType]> {
  let summary = "integer/float subtraction";
  let arguments = (ins AnyType:$lhs, AnyType:$rhs);
  let results = (outs AnyType:$result);
  let assemblyFormat = "$lhs `,` $rhs attr-dict `:` type($result)";
}

def CIR_MulOp : CIR_Op<"mul", [Pure, SameOperandsAndResultType]> {
  let summary = "integer/float multiplication";
  let arguments = (ins AnyType:$lhs, AnyType:$rhs);
  let results = (outs AnyType:$result);
  let assemblyFormat = "$lhs `,` $rhs attr-dict `:` type($result)";
}

def CIR_DivOp : CIR_Op<"div", [Pure, SameOperandsAndResultType]> {
  let summary = "integer signed division / float division";
  let arguments = (ins AnyType:$lhs, AnyType:$rhs);
  let results = (outs AnyType:$result);
  let assemblyFormat = "$lhs `,` $rhs attr-dict `:` type($result)";
}

def CIR_RemOp : CIR_Op<"rem", [Pure, SameOperandsAndResultType]> {
  let summary = "integer signed remainder";
  let arguments = (ins AnyType:$lhs, AnyType:$rhs);
  let results = (outs AnyType:$result);
  let assemblyFormat = "$lhs `,` $rhs attr-dict `:` type($result)";
}

//===----------------------------------------------------------------------===//
// Comparison — lowers to llvm.icmp with predicate
// Reference: mlir/lib/Conversion/ArithToLLVM/ArithToLLVM.cpp CmpIOpLowering
//===----------------------------------------------------------------------===//

def CIR_CmpOp : CIR_Op<"cmp", [Pure, SameTypeOperands]> {
  let summary = "integer comparison with predicate";
  let description = [{
    Compares two integers. Predicate is an i64 integer attribute:
      0=eq, 1=ne, 2=slt, 3=sle, 4=sgt, 5=sge
    Maps directly to LLVM::ICmpPredicate enum values.
    Reference: arith::CmpIOp → LLVM::ICmpOp pattern.
  }];

  let arguments = (ins I64Attr:$predicate, AnyType:$lhs, AnyType:$rhs);
  let results = (outs I1:$result);
  let assemblyFormat = "$predicate `,` $lhs `,` $rhs attr-dict `:` type($lhs)";
}

//===----------------------------------------------------------------------===//
// Control flow — branches and blocks
// Reference: LLVM dialect br/cond_br + func.return
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
