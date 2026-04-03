//===- CIRCApi.cpp - CIR dialect C API implementation ----------------===//

#include "CIRCApi.h"
#include "CIR/CIROps.h"
#include "mlir/CAPI/Registration.h"

void cirRegisterDialect(MlirContext ctx) {
  mlir::MLIRContext *context = unwrap(ctx);
  context->getOrLoadDialect<cir::CIRDialect>();
}
