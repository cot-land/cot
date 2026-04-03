//===- CIRDialect.td - CIR dialect definition ----------------*- tablegen -*-===//
//
// Defines the CIR (Cot Intermediate Representation) MLIR dialect.
// CIR is the universal IR for C-style languages.
//
//===----------------------------------------------------------------------===//

#ifndef CIR_DIALECT
#define CIR_DIALECT

include "mlir/IR/OpBase.td"

def CIR_Dialect : Dialect {
  let name = "cir";
  let summary = "Cot Intermediate Representation — universal IR for C-style languages";
  let cppNamespace = "::cir";
}

#endif // CIR_DIALECT
