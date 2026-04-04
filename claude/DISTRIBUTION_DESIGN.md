# COT Distribution & Plugin Architecture Design

**Date:** 2026-04-04
**Status:** Phase A and Phase C (partial) implemented. Phase B and D remain.
**Goal:** Language developers can `brew install cot`, link against libcir/libcot, write a frontend in any language, and inject custom passes — without touching COT source.

---

## The Vision

```
brew install cot

# A language developer writes their frontend in any language:
find_package(CIR REQUIRED)         # CMake finds libcir headers + library
find_package(COT REQUIRED)         # CMake finds libcot headers + library
target_link_libraries(my_lang CIR::CIR COT::COT)

# Or via C API (Go, Zig, Rust, Python...):
#include <cir-c/CIR.h>            # C API for building CIR ops
#include <cot-c/COT.h>            # C API for running passes + codegen

# Custom passes as plugins:
cot build file.mylang --load-pass-plugin=./libMyOpt.dylib --my-opt-pass
```

---

## Architecture Overview

```
                          ┌─────────────────────────────┐
                          │     Language Frontend        │
                          │  (any language via C API)    │
                          └──────────┬──────────────────┘
                                     │ CIR Module (MLIR bytecode or in-memory)
                                     ▼
┌────────────────┐    ┌─────────────────────────────────────┐
│  Pass Plugins  │───▶│          COT Pass Pipeline          │
│  (.dylib/.so)  │    │                                     │
│                │    │  [pre-sema hooks]                    │
│  Custom CIR→CIR│    │  Sema (type check + cast insert)    │
│  transforms    │    │  verify                              │
│                │    │  [post-sema hooks]                   │
│  Custom optim. │    │  CIRToLLVM + FuncToLLVM              │
│  passes        │    │  [pre-codegen hooks]                 │
└────────────────┘    └──────────┬──────────────────────────┘
                                 │ LLVM IR
                                 ▼
                          ┌──────────────┐
                          │ LLVM Backend │
                          │ native/wasm  │
                          └──────────────┘
```

**Three independent extension points:**
1. **Frontends** — any language, via C API or C++ API, produces CIR
2. **Passes** — loadable plugins, registered at runtime, inserted into pipeline
3. **Targets** — LLVM handles this (no work needed)

---

## Part 1: Library Distribution

### Install Layout

Match the LLVM/MLIR pattern exactly. After `make install PREFIX=/opt/homebrew`:

```
<prefix>/
├── bin/
│   └── cot                              # CLI driver
├── lib/
│   ├── libCIR.a                         # CIR dialect (static)
│   ├── libCOT.a                         # Compiler passes (static)
│   ├── libCIRCApi.a                     # CIR C API (static)
│   ├── libCOTCApi.a                     # COT C API (static)
│   └── cmake/
│       ├── cir/
│       │   ├── CIRConfig.cmake          # find_package(CIR) entry point
│       │   ├── CIRConfigVersion.cmake   # version compatibility
│       │   ├── CIRTargets.cmake         # IMPORTED target definitions
│       │   └── CIRTargets-release.cmake # build-config specifics
│       └── cot/
│           ├── COTConfig.cmake
│           ├── COTConfigVersion.cmake
│           ├── COTTargets.cmake
│           └── COTTargets-release.cmake
├── include/
│   ├── CIR/                             # C++ dialect headers
│   │   ├── CIRDialect.h
│   │   ├── CIROps.h
│   │   ├── CIRTypes.h
│   │   ├── CIRDialect.td               # TableGen sources (for re-generation)
│   │   ├── CIROps.td
│   │   ├── CIRTypes.td
│   │   ├── CIROps.h.inc                # Generated (must install)
│   │   ├── CIROps.cpp.inc
│   │   ├── CIRTypes.h.inc
│   │   ├── CIRTypes.cpp.inc
│   │   ├── CIRDialect.cpp.inc
│   │   ├── CIREnums.h.inc
│   │   └── CIREnums.cpp.inc
│   ├── COT/                             # C++ pass headers
│   │   ├── Compiler.h
│   │   ├── Passes.h
│   │   └── CIRToLLVMPatterns.h
│   ├── cir-c/                           # C API headers
│   │   └── CIR.h
│   └── cot-c/                           # C API headers
│       └── COT.h
└── share/
    └── cot/
        └── examples/                    # Example frontend + plugin
```

### Naming Convention

Follow MLIR's pattern: library name = directory name = CMake target namespace.

| Library | Static Archive | CMake Target | C API Library | C API Header |
|---------|---------------|--------------|---------------|--------------|
| CIR dialect | `libCIR.a` | `CIR::CIR` | `libCIRCApi.a` | `cir-c/CIR.h` |
| COT passes | `libCOT.a` | `COT::COT` | `libCOTCApi.a` | `cot-c/COT.h` |

### Dependency Chain

```
CIR::CIR depends on:
  MLIRIR, MLIRSupport, MLIRFuncDialect,
  MLIRCastInterfaces, MLIRControlFlowInterfaces,
  MLIRSideEffectInterfaces, MLIRInferTypeOpInterface

COT::COT depends on:
  CIR::CIR,
  MLIRPass, MLIRParser, MLIRAsmParser,
  MLIRLLVMDialect, MLIRLLVMCommonConversion,
  MLIRFuncToLLVM, MLIRTargetLLVMIRExport,
  LLVMCore, LLVMSupport, LLVMTarget, LLVMAArch64*, LLVMX86*
```

All transitive deps declared via `INTERFACE_LINK_LIBRARIES` in the CMake
targets file. Downstream projects just write `target_link_libraries(mylib COT::COT)`
and CMake resolves everything.

### CMake Config File Design

**CIRConfig.cmake:**
```cmake
# Compute install prefix from this file's location (3 dirs up from lib/cmake/cir/)
get_filename_component(CIR_INSTALL_PREFIX "${CMAKE_CURRENT_LIST_FILE}" PATH)
get_filename_component(CIR_INSTALL_PREFIX "${CIR_INSTALL_PREFIX}" PATH)
get_filename_component(CIR_INSTALL_PREFIX "${CIR_INSTALL_PREFIX}" PATH)

set(CIR_INCLUDE_DIRS "${CIR_INSTALL_PREFIX}/include")
set(CIR_CMAKE_DIR "${CIR_INSTALL_PREFIX}/lib/cmake/cir")

# CIR requires MLIR
find_package(MLIR REQUIRED CONFIG
  HINTS "${CIR_INSTALL_PREFIX}/lib/cmake/mlir"
        "${MLIR_DIR}")

# Import CIR targets
if(NOT TARGET CIR::CIR)
  include("${CIR_CMAKE_DIR}/CIRTargets.cmake")
endif()

set(CIR_EXPORTED_TARGETS CIR::CIR CIR::CIRCApi)
```

**Downstream consumer CMakeLists.txt:**
```cmake
cmake_minimum_required(VERSION 3.20)
project(my-lang)

find_package(CIR REQUIRED CONFIG)
find_package(COT REQUIRED CONFIG)

add_executable(my-lang-compiler main.cpp codegen.cpp)
target_link_libraries(my-lang-compiler PRIVATE COT::COT CIR::CIR)
```

---

## Part 2: C API Expansion

The C API is the bridge for non-C++ frontends. Current state: only `cirRegisterDialect()`.
Goal: a frontend in Go, Zig, Rust, or Python can build a complete CIR module.

### C API Header: `cir-c/CIR.h`

Reference: `mlir-c/IR.h` pattern — opaque types, plain C functions, no exceptions.

```c
#ifndef CIR_C_CIR_H
#define CIR_C_CIR_H

#include "mlir-c/IR.h"
#include "mlir-c/Support.h"

#ifdef __cplusplus
extern "C" {
#endif

//===----------------------------------------------------------------------===//
// Dialect Registration
//===----------------------------------------------------------------------===//

/// Register the CIR dialect with an MLIR context.
void cirRegisterDialect(MlirContext ctx);

//===----------------------------------------------------------------------===//
// Type Constructors
//===----------------------------------------------------------------------===//

/// Get !cir.ptr type.
MlirType cirPointerTypeGet(MlirContext ctx);

/// Get !cir.ref<T> type.
MlirType cirRefTypeGet(MlirContext ctx, MlirType pointeeType);

/// Get !cir.struct<"name", fields...> type.
MlirType cirStructTypeGet(MlirContext ctx, MlirStringRef name,
                          intptr_t nFields,
                          MlirStringRef *fieldNames,
                          MlirType *fieldTypes);

/// Get !cir.array<N x T> type.
MlirType cirArrayTypeGet(MlirContext ctx, int64_t size,
                         MlirType elementType);

/// Get !cir.slice<T> type.
MlirType cirSliceTypeGet(MlirContext ctx, MlirType elementType);

//===----------------------------------------------------------------------===//
// Type Queries
//===----------------------------------------------------------------------===//

/// Check if a type is !cir.ptr.
bool cirTypeIsPointer(MlirType type);

/// Check if a type is !cir.ref<T>.
bool cirTypeIsRef(MlirType type);

/// Get pointee type from !cir.ref<T>.
MlirType cirRefTypeGetPointee(MlirType refType);

/// Check if a type is !cir.struct.
bool cirTypeIsStruct(MlirType type);

/// Get struct field count.
intptr_t cirStructTypeGetNumFields(MlirType structType);

/// Get struct field index by name. Returns -1 if not found.
int cirStructTypeGetFieldIndex(MlirType structType, MlirStringRef name);

/// Check if a type is !cir.slice<T>.
bool cirTypeIsSlice(MlirType type);

/// Get element type from !cir.slice<T>.
MlirType cirSliceTypeGetElement(MlirType sliceType);

//===----------------------------------------------------------------------===//
// Op Builders (convenience wrappers around mlirOperationCreate)
//===----------------------------------------------------------------------===//

/// Create cir.constant with integer value.
MlirValue cirBuildConstantInt(MlirBlock block, MlirLocation loc,
                              MlirType type, int64_t value);

/// Create cir.constant with float value.
MlirValue cirBuildConstantFloat(MlirBlock block, MlirLocation loc,
                                MlirType type, double value);

/// Create cir.string_constant "value" : !cir.slice<i8>.
MlirValue cirBuildStringConstant(MlirBlock block, MlirLocation loc,
                                 MlirStringRef value);

/// Create cir.add (and similar binary ops).
MlirValue cirBuildAdd(MlirBlock block, MlirLocation loc,
                      MlirType type, MlirValue lhs, MlirValue rhs);
MlirValue cirBuildSub(MlirBlock block, MlirLocation loc,
                      MlirType type, MlirValue lhs, MlirValue rhs);
MlirValue cirBuildMul(MlirBlock block, MlirLocation loc,
                      MlirType type, MlirValue lhs, MlirValue rhs);
MlirValue cirBuildDiv(MlirBlock block, MlirLocation loc,
                      MlirType type, MlirValue lhs, MlirValue rhs);

/// Create cir.cmp with predicate (0=eq, 1=ne, 2=slt, 3=sle, 4=sgt, 5=sge).
MlirValue cirBuildCmp(MlirBlock block, MlirLocation loc,
                      int predicate, MlirValue lhs, MlirValue rhs);

/// Create cir.alloca for stack allocation.
MlirValue cirBuildAlloca(MlirBlock block, MlirLocation loc,
                         MlirType elemType);

/// Create cir.store.
void cirBuildStore(MlirBlock block, MlirLocation loc,
                   MlirValue value, MlirValue addr);

/// Create cir.load.
MlirValue cirBuildLoad(MlirBlock block, MlirLocation loc,
                       MlirType resultType, MlirValue addr);

/// Create cir.struct_init from field values.
MlirValue cirBuildStructInit(MlirBlock block, MlirLocation loc,
                             MlirType structType,
                             intptr_t nFields, MlirValue *fields);

/// Create cir.field_val to extract a field.
MlirValue cirBuildFieldVal(MlirBlock block, MlirLocation loc,
                           MlirType resultType, MlirValue input,
                           int64_t fieldIndex);

/// Create cir.array_init from element values.
MlirValue cirBuildArrayInit(MlirBlock block, MlirLocation loc,
                            MlirType arrayType,
                            intptr_t nElements, MlirValue *elements);

/// Create cir.addr_of (&x).
MlirValue cirBuildAddrOf(MlirBlock block, MlirLocation loc,
                         MlirType refType, MlirValue addr);

/// Create cir.deref (*p).
MlirValue cirBuildDeref(MlirBlock block, MlirLocation loc,
                        MlirType resultType, MlirValue ref);

//===----------------------------------------------------------------------===//
// Control Flow Builders
//===----------------------------------------------------------------------===//

/// Create cir.br (unconditional branch).
void cirBuildBr(MlirBlock block, MlirLocation loc,
                MlirBlock dest,
                intptr_t nArgs, MlirValue *args);

/// Create cir.condbr (conditional branch).
void cirBuildCondBr(MlirBlock block, MlirLocation loc,
                    MlirValue condition,
                    MlirBlock trueDest, MlirBlock falseDest);

/// Create cir.select (ternary).
MlirValue cirBuildSelect(MlirBlock block, MlirLocation loc,
                         MlirType resultType, MlirValue condition,
                         MlirValue trueVal, MlirValue falseVal);

/// Create cir.trap (abort).
void cirBuildTrap(MlirBlock block, MlirLocation loc);

#ifdef __cplusplus
}
#endif

#endif // CIR_C_CIR_H
```

### C API Header: `cot-c/COT.h`

```c
#ifndef COT_C_COT_H
#define COT_C_COT_H

#include "mlir-c/IR.h"
#include "mlir-c/Pass.h"

#ifdef __cplusplus
extern "C" {
#endif

//===----------------------------------------------------------------------===//
// Context + Pipeline
//===----------------------------------------------------------------------===//

/// Initialize an MLIR context with all CIR-required dialects.
void cotInitContext(MlirContext ctx);

/// Run Sema (type checking + cast insertion) on a CIR module.
/// Returns 0 on success, 1 on failure.
int cotRunSema(MlirModule module);

/// Lower CIR to LLVM dialect. Returns 0/1.
int cotLowerToLLVM(MlirModule module);

/// Full pipeline: Sema → verify → lower → LLVM IR → object → link.
/// Returns 0/1.
int cotEmitBinary(MlirModule module, const char *outputPath);

//===----------------------------------------------------------------------===//
// Pass Creation (for use with MlirPassManager)
//===----------------------------------------------------------------------===//

/// Create the Sema pass (returns MlirPass, caller manages lifetime).
MlirPass cotCreateSemanticAnalysisPass(void);

/// Create the CIR→LLVM lowering pass.
MlirPass cotCreateCIRToLLVMPass(void);

//===----------------------------------------------------------------------===//
// Configurable Pipeline
//===----------------------------------------------------------------------===//

/// Opaque pipeline builder handle.
typedef struct { void *ptr; } CotPipelineBuilder;

/// Create a pipeline builder with the default COT pipeline.
CotPipelineBuilder cotPipelineBuilderCreate(MlirContext ctx);

/// Destroy a pipeline builder.
void cotPipelineBuilderDestroy(CotPipelineBuilder builder);

/// Insert a pass before Sema.
void cotPipelineBuilderAddPreSemaPass(CotPipelineBuilder builder,
                                      MlirPass pass);

/// Insert a pass after Sema (before lowering).
void cotPipelineBuilderAddPostSemaPass(CotPipelineBuilder builder,
                                       MlirPass pass);

/// Insert a pass after lowering (on LLVM dialect).
void cotPipelineBuilderAddPostLoweringPass(CotPipelineBuilder builder,
                                           MlirPass pass);

/// Run the configured pipeline on a module. Returns 0/1.
int cotPipelineBuilderRun(CotPipelineBuilder builder, MlirModule module);

#ifdef __cplusplus
}
#endif

#endif // COT_C_COT_H
```

### Migration for Existing Frontends

Once the C API is expanded, libzc and libtc can migrate from raw `mlirOperationCreate`
calls to `cirBuildAdd`, `cirBuildStructInit`, etc. This:
- Reduces per-frontend boilerplate by ~60%
- Guarantees correct op construction (no mismatched attributes)
- Makes the frontend contract enforceable at the API level

---

## Part 3: Pass Plugin Interface

### Plugin Convention

Match MLIR's `mlirGetPassPluginInfo()` pattern exactly:

```c
// Plugin must export this symbol:
extern "C" mlir::PassPluginLibraryInfo mlirGetPassPluginInfo() {
  return {
    MLIR_PLUGIN_API_VERSION,
    "MyOptPasses",     // plugin name
    "1.0.0",           // plugin version
    []() {
      // Register all passes when plugin loads
      mlir::PassRegistration<MyCustomPass>();
    }
  };
}
```

### How Plugins Register

A plugin is a shared library (`.dylib`/`.so`) that exports `mlirGetPassPluginInfo`.
When loaded, its registration callback runs, which calls `PassRegistration<T>()`.
This adds the pass to MLIR's global pass registry. The pass can then be referenced
by its `--argument` name in the pipeline.

### Extension Points in the COT Pipeline

The current hardcoded pipeline:
```
Sema → verify → CIRToLLVM → FuncToLLVM → LLVM IR → native
```

Becomes a configurable pipeline with 3 extension points:

```
[pre-sema passes]        ← Extension point 1: CIR → CIR (before type checking)
Sema
verify
[post-sema passes]       ← Extension point 2: CIR → CIR (typed, verified)
CIRToLLVM + FuncToLLVM
[post-lowering passes]   ← Extension point 3: LLVM dialect → LLVM dialect
LLVM IR → native
```

**Extension point 1 (pre-sema):** For passes that transform CIR before types are
checked. Example: macro expansion, desugaring, custom syntax lowering.

**Extension point 2 (post-sema):** For optimization and analysis passes on typed,
verified CIR. This is where most custom passes go. Example: ARC insertion,
dead code elimination, custom linting, domain-specific optimization.

**Extension point 3 (post-lowering):** For passes on the LLVM dialect before
final IR emission. Rare, but needed for target-specific transforms.

### Pipeline Builder (C++ API)

```cpp
// In COT/Pipeline.h
namespace cot {

class PipelineBuilder {
public:
  explicit PipelineBuilder(mlir::MLIRContext *ctx);

  /// Add a pass to run before Sema.
  void addPreSemaPass(std::unique_ptr<mlir::Pass> pass);

  /// Add a pass to run after Sema (on typed, verified CIR).
  void addPostSemaPass(std::unique_ptr<mlir::Pass> pass);

  /// Add a pass to run after CIR→LLVM lowering.
  void addPostLoweringPass(std::unique_ptr<mlir::Pass> pass);

  /// Build and run the full pipeline on a module.
  /// Includes: [pre-sema] → Sema → verify → [post-sema] → CIRToLLVM →
  ///           [post-lowering] → LLVM IR → native
  int run(mlir::ModuleOp module);

  /// Build and run up to CIR emission (no lowering).
  int runToTypedCIR(mlir::ModuleOp module);

  /// Build and run up to LLVM dialect (no native codegen).
  int runToLLVM(mlir::ModuleOp module);

private:
  mlir::MLIRContext *ctx_;
  llvm::SmallVector<std::unique_ptr<mlir::Pass>> preSemaPasses_;
  llvm::SmallVector<std::unique_ptr<mlir::Pass>> postSemaPasses_;
  llvm::SmallVector<std::unique_ptr<mlir::Pass>> postLoweringPasses_;
};

} // namespace cot
```

### CLI Plugin Loading

```bash
# Load a pass plugin and use it in the pipeline
cot build file.ac --load-pass-plugin=./libMyOpt.dylib --post-sema-pass=my-opt

# Multiple plugins
cot build file.ac \
  --load-pass-plugin=./libARC.dylib \
  --load-pass-plugin=./libLint.dylib \
  --post-sema-pass=arc-insert \
  --post-sema-pass=my-linter

# Inspect CIR after custom passes
cot emit-cir file.ac --load-pass-plugin=./libMyOpt.dylib --post-sema-pass=my-opt
```

Implementation: `cot/main.cpp` uses `mlir::PassPlugin::load()` to load `.dylib`,
then calls `registerPassRegistryCallbacks()`, then looks up the named pass from
MLIR's pass registry.

### Example Plugin: A Custom Lint Pass

```cpp
// my_lint_plugin.cpp
#include "CIR/CIROps.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Tools/Plugins/PassPlugin.h"

namespace {
class DivByZeroLintPass
    : public mlir::PassWrapper<DivByZeroLintPass,
                               mlir::OperationPass<mlir::func::FuncOp>> {
public:
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(DivByZeroLintPass)
  StringRef getArgument() const final { return "cir-div-zero-lint"; }
  StringRef getDescription() const final {
    return "Warn on potential division by zero in CIR";
  }

  void getDependentDialects(mlir::DialectRegistry &reg) const override {
    reg.insert<cir::CIRDialect>();
  }

  void runOnOperation() override {
    getOperation().walk([&](cir::DivOp op) {
      if (auto constOp = op.getRhs().getDefiningOp<cir::ConstantOp>()) {
        if (auto intAttr = llvm::dyn_cast<mlir::IntegerAttr>(constOp.getValue())) {
          if (intAttr.getInt() == 0) {
            op.emitWarning("division by constant zero");
          }
        }
      }
    });
  }
};
} // namespace

extern "C" LLVM_ATTRIBUTE_WEAK mlir::PassPluginLibraryInfo
mlirGetPassPluginInfo() {
  return {MLIR_PLUGIN_API_VERSION, "DivZeroLint", "1.0.0", []() {
    mlir::PassRegistration<DivByZeroLintPass>();
  }};
}
```

Build the plugin:
```cmake
add_library(DivZeroLint SHARED my_lint_plugin.cpp)
find_package(CIR REQUIRED CONFIG)
target_link_libraries(DivZeroLint PRIVATE CIR::CIR MLIRIR MLIRPass)
```

Use it:
```bash
cot build file.ac --load-pass-plugin=./libDivZeroLint.dylib --post-sema-pass=cir-div-zero-lint
```

### Non-C++ Passes via External Pass API

MLIR provides `mlirCreateExternalPass()` for Go/Zig/Rust passes:

```c
// Go example via CGo:
void myGoPassRun(MlirOperation op, MlirExternalPass pass, void *userData) {
    // Walk CIR ops using MLIR C API
    // Call cirBuild* to create new ops
    // Use mlirOperationErase to remove ops
}

MlirPass createMyGoPass() {
    MlirExternalPassCallbacks callbacks = {
        .construct = NULL,
        .destruct = NULL,
        .initialize = NULL,
        .clone = NULL,
        .run = myGoPassRun
    };
    return mlirCreateExternalPass(
        mlirTypeIDCreate(),
        mlirStringRefCreateFromCString("my-go-pass"),
        mlirStringRefCreateFromCString("my-go-pass"),
        mlirStringRefCreateFromCString("A pass written in Go"),
        mlirStringRefCreate("", 0),  // any operation
        0, NULL,  // no dependent dialects
        callbacks, NULL);
}
```

---

## Part 4: Build System — IMPLEMENTED

### Current State (implemented 2026-04-04)

```
Makefile (orchestrates build order)
  ├── cmake -B build (configure once)
  ├── cmake --build build --target CIR    # libcir first (libzc/libtc need it)
  ├── cd libzc && zig build               # Zig frontend (links libCIR.a)
  ├── cd libtc && go build                # Go frontend (links libCIR.a)
  └── cmake --build build                 # libcot + cot driver
```

**Single `build/` directory** replaces old `libcir/build/`, `libcot/build/`, `cot/build/`.

**Files implemented:**
- `CMakeLists.txt` — top-level super-build with `add_subdirectory`
- `cmake/CIRConfig.cmake.in` — `find_package(CIR)` template
- `cmake/COTConfig.cmake.in` — `find_package(COT)` template
- `libcir/CMakeLists.txt` — generator expressions, install targets, exports `CIR::CIR`
- `libcot/CMakeLists.txt` — links CIR target, install targets, exports `COT::COT`
- `cot/CMakeLists.txt` — links COT/CIR targets, LLVM backends
- `Makefile` — thin wrapper with correct build ordering

**Install verified** — `cmake --install build --prefix=/tmp/cot-test` produces:
```
bin/cot
lib/libCIR.a, lib/libCOT.a
lib/cmake/cir/{CIRConfig,CIRConfigVersion,CIRTargets,CIRTargets-release}.cmake
lib/cmake/cot/{COTConfig,COTConfigVersion,COTTargets,COTTargets-release}.cmake
include/CIR/*.h, *.td, *.inc
include/COT/*.h
include/cir-c/CIR.h
```

### Zig/Go Frontend Integration

libzc and libtc are not C++ and don't use CMake. They link against libCIR via:
- **libzc (Zig):** Links `build/libcir/libCIR.a` in `build.zig`
- **libtc (Go):** Links via CGo LDFLAGS pointing to `build/libcir/`

After `cot` is installed, a Zig frontend developer would:
```zig
// build.zig
const cir_prefix = "/opt/homebrew"; // or from env
exe.addIncludePath(.{ .cwd_relative = cir_prefix ++ "/include" });
exe.addLibraryPath(.{ .cwd_relative = cir_prefix ++ "/lib" });
exe.linkSystemLibrary("CIR");
```

A Go frontend developer would:
```go
// #cgo CFLAGS: -I/opt/homebrew/include
// #cgo LDFLAGS: -L/opt/homebrew/lib -lCIR -lCOT
// #include <cir-c/CIR.h>
// #include <cot-c/COT.h>
import "C"
```

---

## Part 5: Implementation Plan

### Phase A: CMake Restructure (Foundation) — DONE

1. ✓ Create top-level `CMakeLists.txt` with `add_subdirectory`
2. ✓ Update `libcir/CMakeLists.txt` — generator expressions, `install()`, exports
3. ✓ Update `libcot/CMakeLists.txt` — links CIR target, `install()`, exports
4. ✓ Update `cot/CMakeLists.txt` — links CMake targets, not `.a` paths
5. ✓ Create `cmake/CIRConfig.cmake.in` and `cmake/COTConfig.cmake.in`
6. ✓ Verify: `cmake --install build --prefix=/tmp/cot-test` produces correct layout
7. ✓ Update `Makefile` — thin wrapper, correct build ordering (libcir → libzc/libtc → cot)
8. ✓ Update `libzc/build.zig` and `libtc/mlir.go` paths to `build/libcir/`
9. ✓ Remove old separate build directories (`libcir/build`, `libcot/build`, `cot/build`)

### Phase B: C API Expansion (Frontend Enablement) — NOT STARTED

1. Define `cir-c/CIR.h` with full type + op builder API (as designed above)
2. Implement in `libcir/c-api/CIRCApi.cpp`
3. Define `cot-c/COT.h` with pipeline + pass API
4. Implement in `libcot/c-api/COTCApi.cpp`
5. Migrate libzc to use `cirBuild*` functions instead of raw `mlirOperationCreate`
6. Migrate libtc to use `cirBuild*` functions instead of raw `mlirOperationCreate`
7. Write `FRONTEND.md` documenting the contract

Can be done incrementally — add builders as new ops are added.

### Phase C: Pass Plugin Interface — PARTIAL

1. ✓ Add `PipelineBuilder` class to `COT/Pipeline.h` (3 extension points)
2. ✓ Refactor `Compiler.cpp` to use `PipelineBuilder` internally
3. Add `--load-pass-plugin` and `--post-sema-pass` to `cot/main.cpp`
4. Create example plugin (div-by-zero lint) in `examples/plugins/`
5. Test: build plugin as `.dylib`, load into `cot`, verify it runs

Remaining: CLI flag wiring (#3) and example plugin (#4-5).

### Phase D: Homebrew Formula — NOT STARTED

1. Write `Formula/cot.rb` Homebrew formula
2. Test: `brew install --build-from-source ./Formula/cot.rb`
3. Verify: `find_package(CIR)` works from Homebrew prefix
4. Verify: example plugin builds against installed CIR headers

Depends on: Phase A (done), install layout verified.

---

## Rules

1. **C API mirrors C++ API.** Every C++ op/type has a C API builder.
2. **No ABI breaks within a major version.** Add functions, never remove.
3. **CMake is the source of truth.** Makefile is convenience only.
4. **Plugins use MLIR's plugin convention.** `mlirGetPassPluginInfo()`, not custom.
5. **Extension points, not callbacks.** Passes are inserted into the pipeline, not
   called via hooks. This is the MLIR way.
6. **Static libraries by default.** Shared libraries are optional (for plugin hosts).
7. **Generated headers must be installed.** `.inc` files are part of the public API.

---

## What This Enables

Once implemented, a language developer can:

1. **Install COT from Homebrew** — `brew install cot`
2. **Write a frontend in any language** — use C API from Go/Zig/Rust/Python
3. **Produce CIR** — call `cirBuild*` functions, serialize to bytecode
4. **Run the standard pipeline** — `cotEmitBinary()` or `cot build file.mylang`
5. **Add custom passes** — write a `.dylib` plugin, load with `--load-pass-plugin`
6. **Compose pipelines** — `PipelineBuilder` API or CLI flags
7. **Target any architecture** — LLVM handles all backends

This is the Lattner vision: **CIR is the universal IR, COT is the universal compiler backend, frontends are pluggable, passes are composable.**
