// Bridging header for libsc — imports CIR C API + MLIR C API into Swift
//
// Reference: libtc/mlir.go CGo includes — same set of headers
#ifndef LIBSC_BRIDGE_H
#define LIBSC_BRIDGE_H

#include "mlir-c/IR.h"
#include "mlir-c/Support.h"
#include "mlir-c/BuiltinTypes.h"
#include "mlir-c/BuiltinAttributes.h"
#include "CIRCApi.h"

#endif // LIBSC_BRIDGE_H
