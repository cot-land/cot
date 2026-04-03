//===- CIRDialect.cpp - CIR dialect implementation --------------------===//

#include "CIR/CIROps.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "llvm/ADT/TypeSwitch.h"
#include "mlir/IR/DialectImplementation.h"
#include "mlir/IR/OpImplementation.h"

using namespace mlir;
using namespace cir;

//===----------------------------------------------------------------------===//
// CIR dialect registration
//===----------------------------------------------------------------------===//

#include "CIR/CIRDialect.cpp.inc"

#include "CIR/CIREnums.cpp.inc"

void CIRDialect::initialize() {
  addTypes<
#define GET_TYPEDEF_LIST
#include "CIR/CIRTypes.cpp.inc"
  >();
  addOperations<
#define GET_OP_LIST
#include "CIR/CIROps.cpp.inc"
  >();
}

#define GET_TYPEDEF_CLASSES
#include "CIR/CIRTypes.cpp.inc"

//===----------------------------------------------------------------------===//
// cir.constant — custom print/parse
//===----------------------------------------------------------------------===//

ParseResult ConstantOp::parse(OpAsmParser &parser, OperationState &result) {
  Attribute valueAttr;
  if (parser.parseAttribute(valueAttr, "value", result.attributes))
    return failure();
  Type type;
  if (parser.parseColonType(type))
    return failure();
  result.addTypes(type);
  return success();
}

void ConstantOp::print(OpAsmPrinter &p) {
  p << " " << getValue() << " : " << getResult().getType();
}

//===----------------------------------------------------------------------===//
// cir.constant — verifier
//===----------------------------------------------------------------------===//

LogicalResult ConstantOp::verify() {
  auto resType = getResult().getType();

  // Integer attribute type must match result type
  if (auto intAttr = llvm::dyn_cast<IntegerAttr>(getValue())) {
    if (intAttr.getType() != resType)
      return emitOpError("integer value type ")
             << intAttr.getType() << " must match result type " << resType;
    return success();
  }

  // Float attribute type must match result type
  if (auto floatAttr = llvm::dyn_cast<FloatAttr>(getValue())) {
    if (floatAttr.getType() != resType)
      return emitOpError("float value type ")
             << floatAttr.getType() << " must match result type " << resType;
    return success();
  }

  return success();
}

//===----------------------------------------------------------------------===//
// TableGen-generated op definitions
//===----------------------------------------------------------------------===//

#define GET_OP_CLASSES
#include "CIR/CIROps.cpp.inc"
