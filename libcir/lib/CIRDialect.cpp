//===- CIRDialect.cpp - CIR dialect implementation --------------------===//

#include "CIR/CIROps.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/Interfaces/CastInterfaces.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
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
// !cir.enum — custom parse/print + verifier + helpers
// Syntax: !cir.enum<"Color", i32, Red: 0, Green: 1, Blue: 2>
//===----------------------------------------------------------------------===//

mlir::Type EnumType::parse(mlir::AsmParser &parser) {
  std::string name;
  if (parser.parseLess() || parser.parseString(&name) || parser.parseComma())
    return {};
  mlir::Type tagType;
  if (parser.parseType(tagType))
    return {};
  llvm::SmallVector<mlir::StringAttr> variantNames;
  llvm::SmallVector<int64_t> variantValues;
  while (succeeded(parser.parseOptionalComma())) {
    llvm::StringRef vname;
    int64_t vval;
    if (parser.parseKeyword(&vname) || parser.parseColon() ||
        parser.parseInteger(vval))
      return {};
    variantNames.push_back(
        mlir::StringAttr::get(parser.getContext(), vname));
    variantValues.push_back(vval);
  }
  if (parser.parseGreater()) return {};
  return get(parser.getContext(), name, tagType, variantNames, variantValues);
}

void EnumType::print(mlir::AsmPrinter &p) const {
  p << "<\"" << getName() << "\", " << getTagType();
  auto names = getVariantNames();
  auto values = getVariantValues();
  for (size_t i = 0; i < names.size(); i++)
    p << ", " << names[i].getValue() << ": " << values[i];
  p << ">";
}

mlir::LogicalResult EnumType::verify(
    llvm::function_ref<mlir::InFlightDiagnostic()> emitError,
    llvm::StringRef name, mlir::Type tagType,
    llvm::ArrayRef<mlir::StringAttr> variantNames,
    llvm::ArrayRef<int64_t> variantValues) {
  if (name.empty())
    return emitError() << "enum type must have a name";
  if (variantNames.size() != variantValues.size())
    return emitError() << "variant names count must match variant values count";
  if (!tagType.isIntOrIndex())
    return emitError() << "tag type must be an integer type";
  return mlir::success();
}

int64_t EnumType::getVariantValue(llvm::StringRef variantName) const {
  auto names = getVariantNames();
  auto values = getVariantValues();
  for (size_t i = 0; i < names.size(); i++)
    if (names[i].getValue() == variantName) return values[i];
  return -1;
}

//===----------------------------------------------------------------------===//
// !cir.tagged_union — custom parse/print + verifier + helpers
// Syntax: !cir.tagged_union<"Shape", circle: i32, rect: i32, none: void>
//===----------------------------------------------------------------------===//

mlir::Type TaggedUnionType::parse(mlir::AsmParser &parser) {
  std::string name;
  if (parser.parseLess() || parser.parseString(&name))
    return {};
  llvm::SmallVector<mlir::StringAttr> variantNames;
  llvm::SmallVector<mlir::Type> variantTypes;
  while (succeeded(parser.parseOptionalComma())) {
    llvm::StringRef vname;
    mlir::Type vtype;
    if (parser.parseKeyword(&vname) || parser.parseColon() ||
        parser.parseType(vtype))
      return {};
    variantNames.push_back(
        mlir::StringAttr::get(parser.getContext(), vname));
    variantTypes.push_back(vtype);
  }
  if (parser.parseGreater()) return {};
  return get(parser.getContext(), name, variantNames, variantTypes);
}

void TaggedUnionType::print(mlir::AsmPrinter &p) const {
  p << "<\"" << getName() << "\"";
  auto names = getVariantNames();
  auto types = getVariantTypes();
  for (size_t i = 0; i < names.size(); i++)
    p << ", " << names[i].getValue() << ": " << types[i];
  p << ">";
}

mlir::LogicalResult TaggedUnionType::verify(
    llvm::function_ref<mlir::InFlightDiagnostic()> emitError,
    llvm::StringRef name,
    llvm::ArrayRef<mlir::StringAttr> variantNames,
    llvm::ArrayRef<mlir::Type> variantTypes) {
  if (name.empty())
    return emitError() << "tagged union must have a name";
  if (variantNames.size() != variantTypes.size())
    return emitError() << "variant names count must match variant types count";
  return mlir::success();
}

int TaggedUnionType::getVariantIndex(llvm::StringRef variantName) const {
  auto names = getVariantNames();
  for (size_t i = 0; i < names.size(); i++)
    if (names[i].getValue() == variantName) return static_cast<int>(i);
  return -1;
}

mlir::Type TaggedUnionType::getVariantType(llvm::StringRef variantName) const {
  int idx = getVariantIndex(variantName);
  if (idx < 0) return {};
  return getVariantTypes()[idx];
}

unsigned TaggedUnionType::getMaxPayloadBitWidth() const {
  unsigned maxBits = 0;
  for (auto t : getVariantTypes()) {
    if (auto intTy = llvm::dyn_cast<mlir::IntegerType>(t))
      maxBits = std::max(maxBits, intTy.getWidth());
    else if (auto floatTy = llvm::dyn_cast<mlir::FloatType>(t))
      maxBits = std::max(maxBits, floatTy.getWidth());
  }
  return maxBits;
}

//===----------------------------------------------------------------------===//
// !cir.optional<T> — isPointerLike helper
//===----------------------------------------------------------------------===//

bool OptionalType::isPointerLike() const {
  return llvm::isa<cir::PointerType, cir::RefType>(getPayloadType());
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
// cir.alloca — verifier (result must be !cir.ptr)
//===----------------------------------------------------------------------===//

LogicalResult AllocaOp::verify() {
  if (!llvm::isa<cir::PointerType>(getResult().getType()))
    return emitOpError("result must be !cir.ptr, got ") << getResult().getType();
  return success();
}

//===----------------------------------------------------------------------===//
// cir.store / cir.load — verifiers (addr must be !cir.ptr)
//===----------------------------------------------------------------------===//

LogicalResult StoreOp::verify() {
  if (!llvm::isa<cir::PointerType>(getAddr().getType()))
    return emitOpError("address must be !cir.ptr, got ") << getAddr().getType();
  return success();
}

LogicalResult LoadOp::verify() {
  if (!llvm::isa<cir::PointerType>(getAddr().getType()))
    return emitOpError("address must be !cir.ptr, got ") << getAddr().getType();
  return success();
}

//===----------------------------------------------------------------------===//
// BranchOpInterface — getSuccessorOperands
// Reference: mlir/Dialect/ControlFlow/IR/ControlFlowOps.cpp
//===----------------------------------------------------------------------===//

SuccessorOperands BrOp::getSuccessorOperands(unsigned index) {
  assert(index == 0 && "invalid successor index");
  return SuccessorOperands(getDestOperandsMutable());
}

SuccessorOperands CondBrOp::getSuccessorOperands(unsigned index) {
  assert(index < 2 && "invalid successor index");
  // CondBrOp has no block arguments — return empty operands
  return SuccessorOperands(MutableOperandRange(getOperation(), 0, 0));
}

//===----------------------------------------------------------------------===//
// cir.addr_of — verifier
//===----------------------------------------------------------------------===//

LogicalResult AddrOfOp::verify() {
  if (!llvm::isa<cir::PointerType>(getAddr().getType()))
    return emitOpError("input must be !cir.ptr");
  if (!llvm::isa<cir::RefType>(getResult().getType()))
    return emitOpError("result must be !cir.ref<T>");
  return success();
}

//===----------------------------------------------------------------------===//
// cir.deref — verifier
//===----------------------------------------------------------------------===//

LogicalResult DerefOp::verify() {
  auto refType = llvm::dyn_cast<cir::RefType>(getRef().getType());
  if (!refType)
    return emitOpError("input must be !cir.ref<T>");
  if (getResult().getType() != refType.getPointeeType())
    return emitOpError("result type must match ref pointee type: expected ")
        << refType.getPointeeType() << ", got " << getResult().getType();
  return success();
}

//===----------------------------------------------------------------------===//
// cir.struct_init — custom print/parse + verifier
// Reference: FIR fir.insert_value — aggregate construction from fields
//===----------------------------------------------------------------------===//

/// Parse: cir.struct_init(%a, %b) : !cir.struct<"Point", x: i32, y: i32>
ParseResult StructInitOp::parse(OpAsmParser &parser, OperationState &result) {
  llvm::SmallVector<OpAsmParser::UnresolvedOperand> operands;
  if (parser.parseLParen())
    return failure();
  if (failed(parser.parseOptionalRParen())) {
    do {
      OpAsmParser::UnresolvedOperand operand;
      if (parser.parseOperand(operand))
        return failure();
      operands.push_back(operand);
    } while (succeeded(parser.parseOptionalComma()));
    if (parser.parseRParen())
      return failure();
  }
  Type resultType;
  if (parser.parseColonType(resultType))
    return failure();
  result.addTypes(resultType);
  // Resolve operands using field types from struct type
  auto structType = llvm::dyn_cast<cir::StructType>(resultType);
  if (!structType)
    return parser.emitError(parser.getNameLoc(), "expected !cir.struct type");
  auto fieldTypes = structType.getFieldTypes();
  if (operands.size() != fieldTypes.size())
    return parser.emitError(parser.getNameLoc(),
        "operand count does not match struct field count");
  for (unsigned i = 0; i < operands.size(); i++) {
    if (parser.resolveOperand(operands[i], fieldTypes[i], result.operands))
      return failure();
  }
  return success();
}

/// Print: cir.struct_init(%a, %b) : !cir.struct<"Point", x: i32, y: i32>
void StructInitOp::print(OpAsmPrinter &p) {
  p << "(";
  p.printOperands(getFields());
  p << ") : " << getResult().getType();
}

/// Verify: field count matches struct type, field types match.
LogicalResult StructInitOp::verify() {
  auto structType = llvm::dyn_cast<cir::StructType>(getResult().getType());
  if (!structType)
    return emitOpError("result must be a !cir.struct type");
  auto fieldTypes = structType.getFieldTypes();
  if (getFields().size() != fieldTypes.size())
    return emitOpError("expected ") << fieldTypes.size()
        << " fields, got " << getFields().size();
  for (unsigned i = 0; i < fieldTypes.size(); i++) {
    if (getFields()[i].getType() != fieldTypes[i])
      return emitOpError("field ") << i << " type mismatch: expected "
          << fieldTypes[i] << ", got " << getFields()[i].getType();
  }
  return success();
}

//===----------------------------------------------------------------------===//
// cir.field_val — verifier
//===----------------------------------------------------------------------===//

LogicalResult FieldValOp::verify() {
  auto structType = llvm::dyn_cast<cir::StructType>(getInput().getType());
  if (!structType)
    return emitOpError("input must be a !cir.struct type");
  int64_t idx = getFieldIndex();
  auto fieldTypes = structType.getFieldTypes();
  if (idx < 0 || static_cast<size_t>(idx) >= fieldTypes.size())
    return emitOpError("field index ") << idx << " out of range for struct with "
        << fieldTypes.size() << " fields";
  if (getResult().getType() != fieldTypes[idx])
    return emitOpError("result type ") << getResult().getType()
        << " does not match field type " << fieldTypes[idx];
  return success();
}

//===----------------------------------------------------------------------===//
// cir.field_ptr — verifier
//===----------------------------------------------------------------------===//

LogicalResult FieldPtrOp::verify() {
  if (!llvm::isa<cir::PointerType>(getBase().getType()))
    return emitOpError("base must be !cir.ptr");
  if (!llvm::isa<cir::PointerType>(getResult().getType()))
    return emitOpError("result must be !cir.ptr");
  auto structType = llvm::dyn_cast<cir::StructType>(getElemType());
  if (!structType)
    return emitOpError("elem_type must be a !cir.struct type");
  int64_t idx = getFieldIndex();
  if (idx < 0 || static_cast<size_t>(idx) >= structType.getFieldTypes().size())
    return emitOpError("field index out of range");
  return success();
}

//===----------------------------------------------------------------------===//
// cir.array_init — custom print/parse + verifier
//===----------------------------------------------------------------------===//

ParseResult ArrayInitOp::parse(OpAsmParser &parser, OperationState &result) {
  llvm::SmallVector<OpAsmParser::UnresolvedOperand> operands;
  if (parser.parseLParen())
    return failure();
  if (failed(parser.parseOptionalRParen())) {
    do {
      OpAsmParser::UnresolvedOperand operand;
      if (parser.parseOperand(operand))
        return failure();
      operands.push_back(operand);
    } while (succeeded(parser.parseOptionalComma()));
    if (parser.parseRParen())
      return failure();
  }
  Type resultType;
  if (parser.parseColonType(resultType))
    return failure();
  result.addTypes(resultType);
  auto arrayType = llvm::dyn_cast<cir::ArrayType>(resultType);
  if (!arrayType)
    return parser.emitError(parser.getNameLoc(), "expected !cir.array type");
  auto elemType = arrayType.getElementType();
  for (auto &op : operands) {
    if (parser.resolveOperand(op, elemType, result.operands))
      return failure();
  }
  return success();
}

void ArrayInitOp::print(OpAsmPrinter &p) {
  p << "(";
  p.printOperands(getElements());
  p << ") : " << getResult().getType();
}

LogicalResult ArrayInitOp::verify() {
  auto arrayType = llvm::dyn_cast<cir::ArrayType>(getResult().getType());
  if (!arrayType)
    return emitOpError("result must be a !cir.array type");
  if (static_cast<int64_t>(getElements().size()) != arrayType.getSize())
    return emitOpError("expected ") << arrayType.getSize()
        << " elements, got " << getElements().size();
  auto elemType = arrayType.getElementType();
  for (auto [i, elem] : llvm::enumerate(getElements())) {
    if (elem.getType() != elemType)
      return emitOpError("element ") << i << " type mismatch: expected "
          << elemType << ", got " << elem.getType();
  }
  return success();
}

//===----------------------------------------------------------------------===//
// cir.elem_val — verifier
//===----------------------------------------------------------------------===//

LogicalResult ElemValOp::verify() {
  auto arrayType = llvm::dyn_cast<cir::ArrayType>(getInput().getType());
  if (!arrayType)
    return emitOpError("input must be a !cir.array type");
  int64_t idx = getIndex();
  if (idx < 0 || idx >= arrayType.getSize())
    return emitOpError("index ") << idx << " out of range for array of size "
        << arrayType.getSize();
  if (getResult().getType() != arrayType.getElementType())
    return emitOpError("result type must match array element type");
  return success();
}

//===----------------------------------------------------------------------===//
// cir.elem_ptr — verifier
//===----------------------------------------------------------------------===//

LogicalResult ElemPtrOp::verify() {
  if (!llvm::isa<cir::PointerType>(getBase().getType()))
    return emitOpError("base must be !cir.ptr");
  if (!llvm::isa<cir::PointerType>(getResult().getType()))
    return emitOpError("result must be !cir.ptr");
  if (!llvm::isa<cir::ArrayType>(getElemType()))
    return emitOpError("elem_type must be a !cir.array type");
  return success();
}

//===----------------------------------------------------------------------===//
// cir.string_constant — verifier
//===----------------------------------------------------------------------===//

LogicalResult StringConstantOp::verify() {
  auto sliceType = llvm::dyn_cast<cir::SliceType>(getResult().getType());
  if (!sliceType)
    return emitOpError("result must be !cir.slice<T>");
  // String constants produce slice<i8>
  auto elemType = sliceType.getElementType();
  if (!elemType.isInteger(8))
    return emitOpError("string constant must produce !cir.slice<i8>, got ")
        << getResult().getType();
  return success();
}

//===----------------------------------------------------------------------===//
// cir.slice_ptr — verifier
//===----------------------------------------------------------------------===//

LogicalResult SlicePtrOp::verify() {
  if (!llvm::isa<cir::SliceType>(getInput().getType()))
    return emitOpError("input must be !cir.slice<T>");
  if (!llvm::isa<cir::PointerType>(getResult().getType()))
    return emitOpError("result must be !cir.ptr");
  return success();
}

//===----------------------------------------------------------------------===//
// cir.slice_len — verifier
//===----------------------------------------------------------------------===//

LogicalResult SliceLenOp::verify() {
  if (!llvm::isa<cir::SliceType>(getInput().getType()))
    return emitOpError("input must be !cir.slice<T>");
  if (!getResult().getType().isInteger(64))
    return emitOpError("result must be i64");
  return success();
}

//===----------------------------------------------------------------------===//
// cir.slice_elem — verifier
//===----------------------------------------------------------------------===//

LogicalResult SliceElemOp::verify() {
  auto sliceType = llvm::dyn_cast<cir::SliceType>(getInput().getType());
  if (!sliceType)
    return emitOpError("input must be !cir.slice<T>");
  if (getResult().getType() != sliceType.getElementType())
    return emitOpError("result type must match slice element type");
  return success();
}

//===----------------------------------------------------------------------===//
// cir.none — verifier
//===----------------------------------------------------------------------===//

LogicalResult NoneOp::verify() {
  if (!llvm::isa<cir::OptionalType>(getResult().getType()))
    return emitOpError("result must be !cir.optional<T>");
  return success();
}

//===----------------------------------------------------------------------===//
// cir.wrap_optional — verifier
//===----------------------------------------------------------------------===//

LogicalResult WrapOptionalOp::verify() {
  auto optType = llvm::dyn_cast<cir::OptionalType>(getResult().getType());
  if (!optType)
    return emitOpError("result must be !cir.optional<T>");
  if (getInput().getType() != optType.getPayloadType())
    return emitOpError("input type must match optional payload type");
  return success();
}

//===----------------------------------------------------------------------===//
// cir.is_non_null — verifier
//===----------------------------------------------------------------------===//

LogicalResult IsNonNullOp::verify() {
  if (!llvm::isa<cir::OptionalType>(getInput().getType()))
    return emitOpError("input must be !cir.optional<T>");
  return success();
}

//===----------------------------------------------------------------------===//
// cir.optional_payload — verifier
//===----------------------------------------------------------------------===//

LogicalResult OptionalPayloadOp::verify() {
  auto optType = llvm::dyn_cast<cir::OptionalType>(getInput().getType());
  if (!optType)
    return emitOpError("input must be !cir.optional<T>");
  if (getResult().getType() != optType.getPayloadType())
    return emitOpError("result type must match optional payload type");
  return success();
}

LogicalResult GenericApplyOp::verify() {
  if (getSubsKeys().size() != getSubsTypes().size())
    return emitOpError("substitution keys and types must have same count");
  return success();
}

//===----------------------------------------------------------------------===//
// Tagged union op verifiers
//===----------------------------------------------------------------------===//

LogicalResult UnionInitOp::verify() {
  auto tuType = llvm::dyn_cast<cir::TaggedUnionType>(getResult().getType());
  if (!tuType)
    return emitOpError("result must be !cir.tagged_union<...>");
  int idx = tuType.getVariantIndex(getVariant());
  if (idx < 0)
    return emitOpError("variant '") << getVariant()
        << "' not found in union '" << tuType.getName() << "'";
  return success();
}

LogicalResult UnionTagOp::verify() {
  if (!llvm::isa<cir::TaggedUnionType>(getInput().getType()))
    return emitOpError("input must be !cir.tagged_union<...>");
  if (!getResult().getType().isInteger(8))
    return emitOpError("result must be i8");
  return success();
}

LogicalResult UnionPayloadOp::verify() {
  auto tuType = llvm::dyn_cast<cir::TaggedUnionType>(getInput().getType());
  if (!tuType)
    return emitOpError("input must be !cir.tagged_union<...>");
  int idx = tuType.getVariantIndex(getVariant());
  if (idx < 0)
    return emitOpError("variant '") << getVariant() << "' not found";
  return success();
}

//===----------------------------------------------------------------------===//
// cir.switch — verifier + BranchOpInterface + custom parse/print
//===----------------------------------------------------------------------===//

LogicalResult SwitchOp::verify() {
  auto numCases = getCaseValues().size();
  auto numDests = getCaseDests().size();
  if (numCases != numDests)
    return emitOpError("case values count (") << numCases
        << ") must match case destinations count (" << numDests << ")";
  return success();
}

SuccessorOperands SwitchOp::getSuccessorOperands(unsigned index) {
  return SuccessorOperands(MutableOperandRange(getOperation(), 0, 0));
}

/// Parse: 0: ^bb1, 1: ^bb2, 2: ^bb3
static ParseResult parseSwitchCases(
    OpAsmParser &parser, DenseI64ArrayAttr &caseValues,
    SmallVectorImpl<Block *> &caseDests) {
  SmallVector<int64_t> values;
  if (failed(parser.parseOptionalRSquare())) {
    do {
      int64_t val;
      Block *dest;
      if (parser.parseInteger(val) || parser.parseColon() ||
          parser.parseSuccessor(dest))
        return failure();
      values.push_back(val);
      caseDests.push_back(dest);
    } while (succeeded(parser.parseOptionalComma()));
    if (parser.parseRSquare())
      return failure();
  }
  caseValues = DenseI64ArrayAttr::get(parser.getContext(), values);
  return success();
}

/// Print: 0: ^bb1, 1: ^bb2, 2: ^bb3
static void printSwitchCases(OpAsmPrinter &p, SwitchOp op,
                              DenseI64ArrayAttr caseValues,
                              SuccessorRange caseDests) {
  for (size_t i = 0; i < caseValues.size(); i++) {
    if (i > 0) p << ", ";
    p << caseValues[i] << ": " << caseDests[i];
  }
}

//===----------------------------------------------------------------------===//
// Enum op verifiers
//===----------------------------------------------------------------------===//

LogicalResult EnumConstantOp::verify() {
  auto enumType = llvm::dyn_cast<cir::EnumType>(getResult().getType());
  if (!enumType)
    return emitOpError("result must be !cir.enum<...>");
  auto val = enumType.getVariantValue(getVariant());
  if (val < 0)
    return emitOpError("variant '") << getVariant()
        << "' not found in enum '" << enumType.getName() << "'";
  return success();
}

LogicalResult EnumValueOp::verify() {
  auto enumType = llvm::dyn_cast<cir::EnumType>(getInput().getType());
  if (!enumType)
    return emitOpError("input must be !cir.enum<...>");
  if (getResult().getType() != enumType.getTagType())
    return emitOpError("result type must match enum tag type: expected ")
        << enumType.getTagType() << ", got " << getResult().getType();
  return success();
}

//===----------------------------------------------------------------------===//
// Error union verifiers
// Reference: Zig E!T — wrap_errunion_payload, wrap_errunion_err, is_err,
//            unwrap_errunion_payload, unwrap_errunion_err
//===----------------------------------------------------------------------===//

LogicalResult WrapResultOp::verify() {
  auto euType = llvm::dyn_cast<cir::ErrorUnionType>(getResult().getType());
  if (!euType)
    return emitOpError("result must be !cir.error_union<T>");
  if (getInput().getType() != euType.getPayloadType())
    return emitOpError("input type must match error union payload type");
  return success();
}

LogicalResult WrapErrorOp::verify() {
  auto euType = llvm::dyn_cast<cir::ErrorUnionType>(getResult().getType());
  if (!euType)
    return emitOpError("result must be !cir.error_union<T>");
  if (!getInput().getType().isInteger(16))
    return emitOpError("input must be i16 error code");
  return success();
}

LogicalResult IsErrorOp::verify() {
  if (!llvm::isa<cir::ErrorUnionType>(getInput().getType()))
    return emitOpError("input must be !cir.error_union<T>");
  return success();
}

LogicalResult ErrorPayloadOp::verify() {
  auto euType = llvm::dyn_cast<cir::ErrorUnionType>(getInput().getType());
  if (!euType)
    return emitOpError("input must be !cir.error_union<T>");
  if (getResult().getType() != euType.getPayloadType())
    return emitOpError("result type must match error union payload type");
  return success();
}

LogicalResult ErrorCodeOp::verify() {
  if (!llvm::isa<cir::ErrorUnionType>(getInput().getType()))
    return emitOpError("input must be !cir.error_union<T>");
  if (!getResult().getType().isInteger(16))
    return emitOpError("result must be i16");
  return success();
}

//===----------------------------------------------------------------------===//
// cir.invoke — BranchOpInterface
//===----------------------------------------------------------------------===//

SuccessorOperands InvokeOp::getSuccessorOperands(unsigned index) {
  assert(index < 2 && "invalid successor index");
  return SuccessorOperands(MutableOperandRange(getOperation(), 0, 0));
}

//===----------------------------------------------------------------------===//
// cir.array_to_slice — verifier
//===----------------------------------------------------------------------===//

LogicalResult ArrayToSliceOp::verify() {
  if (!llvm::isa<cir::PointerType>(getBase().getType()))
    return emitOpError("base must be !cir.ptr");
  if (!llvm::isa<cir::SliceType>(getResult().getType()))
    return emitOpError("result must be !cir.slice<T>");
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
