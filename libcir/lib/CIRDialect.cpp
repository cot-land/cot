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
// !cir.struct — custom print/parse + verifier
// Syntax: !cir.struct<"Point", i32, i32>
//===----------------------------------------------------------------------===//

mlir::Type StructType::parse(mlir::AsmParser &parser) {
  std::string name;
  if (parser.parseLess() || parser.parseString(&name) || parser.parseComma())
    return {};
  llvm::SmallVector<mlir::Type> fields;
  do {
    mlir::Type field;
    if (parser.parseType(field)) return {};
    fields.push_back(field);
  } while (succeeded(parser.parseOptionalComma()));
  if (parser.parseGreater()) return {};
  return get(parser.getContext(), name, fields);
}

void StructType::print(mlir::AsmPrinter &p) const {
  p << "<\"" << getName() << "\"";
  for (auto field : getFieldTypes())
    p << ", " << field;
  p << ">";
}

mlir::LogicalResult StructType::verify(
    llvm::function_ref<mlir::InFlightDiagnostic()> emitError,
    llvm::StringRef name,
    llvm::ArrayRef<mlir::Type> fieldTypes) {
  if (name.empty())
    return emitError() << "struct type must have a name";
  return mlir::success();
}

//===----------------------------------------------------------------------===//
// !cir.array — custom print/parse
// Syntax: !cir.array<10 x i32>
//===----------------------------------------------------------------------===//

mlir::Type ArrayType::parse(mlir::AsmParser &parser) {
  int64_t size;
  mlir::Type elemType;
  if (parser.parseLess() || parser.parseInteger(size) ||
      parser.parseKeyword("x") || parser.parseType(elemType) ||
      parser.parseGreater())
    return {};
  return get(parser.getContext(), size, elemType);
}

void ArrayType::print(mlir::AsmPrinter &p) const {
  p << "<" << getSize() << " x " << getElementType() << ">";
}

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
