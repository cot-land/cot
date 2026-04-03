//===- CIRToLLVMPatterns.h - CIR → LLVM pattern helpers ----------*- C++ -*-===//
//
// Shared includes and utilities for CIR-to-LLVM conversion patterns.
// Each category of patterns is in its own .cpp file.
//
//===----------------------------------------------------------------------===//
#ifndef COT_CIR_TO_LLVM_PATTERNS_H
#define COT_CIR_TO_LLVM_PATTERNS_H

#include "COT/Passes.h"
#include "CIR/CIROps.h"

#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/Conversion/LLVMCommon/ConversionTarget.h"
#include "mlir/Conversion/LLVMCommon/TypeConverter.h"
#include "mlir/Transforms/DialectConversion.h"

using namespace mlir;

#endif // COT_CIR_TO_LLVM_PATTERNS_H
