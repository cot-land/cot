//===- CIRCApi.h - CIR dialect C API ----------------------------*- C -*-===//
//
// C API for registering the CIR dialect.
// Frontends in any language (Zig, Rust, Go) use this to produce CIR.
//
//===------------------------------------------------------------------===//

#ifndef CIR_C_API_H
#define CIR_C_API_H

#include "mlir-c/IR.h"

#ifdef __cplusplus
extern "C" {
#endif

/// Register the CIR dialect with an MLIR context.
void cirRegisterDialect(MlirContext ctx);

#ifdef __cplusplus
}
#endif

#endif // CIR_C_API_H
