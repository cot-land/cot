//===- CIROps.h - CIR dialect ops -------------------------------*- C++ -*-===//
#ifndef CIR_OPS_H
#define CIR_OPS_H

#include "mlir/Bytecode/BytecodeOpInterface.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/Dialect.h"
#include "mlir/IR/OpDefinition.h"
#include "mlir/Interfaces/CastInterfaces.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "mlir/Interfaces/InferTypeOpInterface.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"

#include "CIR/CIRDialect.h.inc"

#define GET_TYPEDEF_CLASSES
#include "CIR/CIRTypes.h.inc"

#include "CIR/CIREnums.h.inc"

#define GET_OP_CLASSES
#include "CIR/CIROps.h.inc"

#endif // CIR_OPS_H
