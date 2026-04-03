//===- codegen.h - ac language codegen (AST → CIR) --------------*- C++ -*-===//
//
// Architecture: Zig AstGen single-pass recursive dispatch
//   ~/claude/references/zig/lib/std/zig/AstGen.zig (13,664 lines)
//
//===----------------------------------------------------------------------===//

#ifndef AC_CODEGEN_H
#define AC_CODEGEN_H

#include "parser.h"
#include "mlir/IR/BuiltinOps.h"

namespace ac {

mlir::OwningOpRef<mlir::ModuleOp> codegen(mlir::MLIRContext &ctx,
                                           std::string_view source,
                                           const Module &mod,
                                           bool testMode = false);

} // namespace ac

#endif // AC_CODEGEN_H
