//===- CIRDialect.cpp - CIR dialect implementation --------------------===//

#include "CIR/CIROps.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/Interfaces/CastInterfaces.h"
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

/// Parse: !cir.struct<"Name", field1: type1, field2: type2>
/// Reference: FIR RecordType parse — name{field:type, ...}
mlir::Type StructType::parse(mlir::AsmParser &parser) {
  std::string name;
  if (parser.parseLess() || parser.parseString(&name))
    return {};
  llvm::SmallVector<mlir::StringAttr> fieldNames;
  llvm::SmallVector<mlir::Type> fieldTypes;
  // Parse optional fields: , name: type, name: type, ...
  while (succeeded(parser.parseOptionalComma())) {
    llvm::StringRef fieldName;
    mlir::Type fieldType;
    if (parser.parseKeyword(&fieldName) || parser.parseColon() ||
        parser.parseType(fieldType))
      return {};
    fieldNames.push_back(
        mlir::StringAttr::get(parser.getContext(), fieldName));
    fieldTypes.push_back(fieldType);
  }
  if (parser.parseGreater()) return {};
  return get(parser.getContext(), name, fieldNames, fieldTypes);
}

/// Print: !cir.struct<"Name", field1: type1, field2: type2>
void StructType::print(mlir::AsmPrinter &p) const {
  p << "<\"" << getName() << "\"";
  auto names = getFieldNames();
  auto types = getFieldTypes();
  for (size_t i = 0; i < names.size(); i++)
    p << ", " << names[i].getValue() << ": " << types[i];
  p << ">";
}

mlir::LogicalResult StructType::verify(
    llvm::function_ref<mlir::InFlightDiagnostic()> emitError,
    llvm::StringRef name,
    llvm::ArrayRef<mlir::StringAttr> fieldNames,
    llvm::ArrayRef<mlir::Type> fieldTypes) {
  if (name.empty())
    return emitError() << "struct type must have a name";
  if (fieldNames.size() != fieldTypes.size())
    return emitError() << "field names count (" << fieldNames.size()
                       << ") must match field types count ("
                       << fieldTypes.size() << ")";
  return mlir::success();
}

/// Look up field index by name. Returns -1 if not found.
/// Reference: FIR RecordType::getFieldIndex
int StructType::getFieldIndex(llvm::StringRef fieldName) const {
  auto names = getFieldNames();
  for (size_t i = 0; i < names.size(); i++)
    if (names[i].getValue() == fieldName) return static_cast<int>(i);
  return -1;
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
// Cast op verifiers — width constraints per Arith dialect pattern
// Reference: mlir/lib/Dialect/Arith/IR/ArithOps.cpp verifyExtOp/verifyTruncateOp
//===----------------------------------------------------------------------===//

/// Extension: destination must be strictly wider than source.
template <typename OpTy>
static LogicalResult verifyExtOp(OpTy op) {
  unsigned srcW = op.getInput().getType().getIntOrFloatBitWidth();
  unsigned dstW = op.getResult().getType().getIntOrFloatBitWidth();
  if (srcW >= dstW)
    return op.emitOpError("result type must be wider than operand type");
  return success();
}

/// Truncation: destination must be strictly narrower than source.
template <typename OpTy>
static LogicalResult verifyTruncOp(OpTy op) {
  unsigned srcW = op.getInput().getType().getIntOrFloatBitWidth();
  unsigned dstW = op.getResult().getType().getIntOrFloatBitWidth();
  if (srcW <= dstW)
    return op.emitOpError("result type must be narrower than operand type");
  return success();
}

LogicalResult ExtSIOp::verify()  { return verifyExtOp(*this); }
LogicalResult ExtUIOp::verify()  { return verifyExtOp(*this); }
LogicalResult TruncIOp::verify() { return verifyTruncOp(*this); }
LogicalResult ExtFOp::verify()   { return verifyExtOp(*this); }
LogicalResult TruncFOp::verify() { return verifyTruncOp(*this); }

//===----------------------------------------------------------------------===//
// CastOpInterface — areCastCompatible
// Reference: mlir/lib/Dialect/Arith/IR/ArithOps.cpp checkWidthChangeCast
//===----------------------------------------------------------------------===//

/// Check that inputs/outputs are valid and have the expected type.
static bool areValidCastTypes(TypeRange inputs, TypeRange outputs) {
  return inputs.size() == 1 && outputs.size() == 1;
}

/// Integer extension: dst must be wider than src.
bool ExtSIOp::areCastCompatible(TypeRange inputs, TypeRange outputs) {
  if (!areValidCastTypes(inputs, outputs)) return false;
  auto src = llvm::dyn_cast<IntegerType>(inputs[0]);
  auto dst = llvm::dyn_cast<IntegerType>(outputs[0]);
  return src && dst && dst.getWidth() > src.getWidth();
}

bool ExtUIOp::areCastCompatible(TypeRange inputs, TypeRange outputs) {
  if (!areValidCastTypes(inputs, outputs)) return false;
  auto src = llvm::dyn_cast<IntegerType>(inputs[0]);
  auto dst = llvm::dyn_cast<IntegerType>(outputs[0]);
  return src && dst && dst.getWidth() > src.getWidth();
}

/// Integer truncation: dst must be narrower than src.
bool TruncIOp::areCastCompatible(TypeRange inputs, TypeRange outputs) {
  if (!areValidCastTypes(inputs, outputs)) return false;
  auto src = llvm::dyn_cast<IntegerType>(inputs[0]);
  auto dst = llvm::dyn_cast<IntegerType>(outputs[0]);
  return src && dst && dst.getWidth() < src.getWidth();
}

/// Int → float: any integer to any float.
bool SIToFPOp::areCastCompatible(TypeRange inputs, TypeRange outputs) {
  if (!areValidCastTypes(inputs, outputs)) return false;
  return llvm::isa<IntegerType>(inputs[0]) && llvm::isa<FloatType>(outputs[0]);
}

/// Float → int: any float to any integer.
bool FPToSIOp::areCastCompatible(TypeRange inputs, TypeRange outputs) {
  if (!areValidCastTypes(inputs, outputs)) return false;
  return llvm::isa<FloatType>(inputs[0]) && llvm::isa<IntegerType>(outputs[0]);
}

/// Float extension: dst must be wider than src.
bool ExtFOp::areCastCompatible(TypeRange inputs, TypeRange outputs) {
  if (!areValidCastTypes(inputs, outputs)) return false;
  auto src = llvm::dyn_cast<FloatType>(inputs[0]);
  auto dst = llvm::dyn_cast<FloatType>(outputs[0]);
  return src && dst && dst.getWidth() > src.getWidth();
}

/// Float truncation: dst must be narrower than src.
bool TruncFOp::areCastCompatible(TypeRange inputs, TypeRange outputs) {
  if (!areValidCastTypes(inputs, outputs)) return false;
  auto src = llvm::dyn_cast<FloatType>(inputs[0]);
  auto dst = llvm::dyn_cast<FloatType>(outputs[0]);
  return src && dst && dst.getWidth() < src.getWidth();
}

//===----------------------------------------------------------------------===//
// TableGen-generated op definitions
//===----------------------------------------------------------------------===//

#define GET_OP_CLASSES
#include "CIR/CIROps.cpp.inc"
