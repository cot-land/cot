# LLVM/MLIR Coding Standards for CIR

Extracted from https://llvm.org/docs/CodingStandards.html and
https://mlir.llvm.org/getting_started/DeveloperGuide/ (April 2026).

Applies to all C++ code in `libcir/` and `libcir-passes/`.

---

## 1. Naming Conventions

| Entity | Style | Examples |
|--------|-------|---------|
| Types, classes, structs, enums | UpperCamelCase | `TextFileReader`, `ValueKind` |
| Variables, parameters, members | **camelBack** (MLIR deviation from LLVM) | `leader`, `numBoats` |
| Functions, methods | camelBack | `openFile()`, `isFoo()`, `getNumOperands()` |
| Enumerators | PREFIX_UpperCamel | `VK_Argument`, `VK_BasicBlock` |
| Namespaces | lowercase | `cir`, `llvm`, `mlir` |
| STL-like methods | snake_case | `begin()`, `end()`, `push_back()` |
| Template parameters | UpperCamelCase | `typename ValueType` |
| Macros | ALL_CAPS_UNDERSCORES | `LLVM_DEBUG(...)` |

**MLIR deviation:** MLIR uses `camelBack` for variables (e.g., `numOps`, `resultType`),
not LLVM's UpperCamelCase. Since CIR is an MLIR project, use camelBack.

**Enum prefixes** must match the enum name:
```cpp
enum class ValueKind { VK_Argument, VK_BasicBlock, VK_Function };
```

**Function naming patterns:**
- Getters: `getNumOperands()`, `getType()`
- Predicates: `isFoo()`, `hasTrait()`, `canFold()`
- Actions: `emitError()`, `replaceAllUsesWith()`

---

## 2. File Organization

### Header Guards

All-caps path with underscores. No `#pragma once`.

```cpp
#ifndef CIR_DIALECT_CIRDIALECT_H
#define CIR_DIALECT_CIRDIALECT_H
// ...
#endif // CIR_DIALECT_CIRDIALECT_H
```

### Include Order

Four groups, each sorted lexicographically, separated by blank lines:

```cpp
#include "CIR/CIRDialect.h"          // 1. Main module header (matching .cpp)

#include "CIR/CIRTypes.h"            // 2. Local/private project headers

#include "mlir/IR/BuiltinOps.h"      // 3. LLVM/MLIR project headers
#include "mlir/Pass/Pass.h"
#include "llvm/ADT/SmallVector.h"

#include <memory>                     // 4. System headers
#include <string>
```

### Forward Declarations

Use forward declarations for pointer/reference types to minimize includes.
Only `#include` when you need the full definition (inheritance, member objects).

### Self-Contained Headers

Every header must compile on its own. Include all prerequisites.

---

## 3. Comment Style

### File Headers

Every source file starts with:
```cpp
//===- CIRDialect.cpp - CIR Dialect Implementation ----------*- C++ -*-===//
//
// Part of the COT Project.
//
//===----------------------------------------------------------------------===//
///
/// \file
/// This file implements the CIR dialect and its operations.
///
//===----------------------------------------------------------------------===//
```

### Doxygen

Use `///` for all documentation comments (MLIR rule: document regardless of visibility):

```cpp
/// Represents a CIR function type.
///
/// \p inputTypes are the function argument types.
/// \returns the constructed FunctionType.
CIRFunctionType getFunctionType(TypeRange inputTypes, TypeRange resultTypes);
```

- First sentence is the brief description
- `\p name` to reference parameters in prose
- `\param name` for parameter docs
- `\returns` for return value docs
- `\code ... \endcode` for examples

### Inline Comments

- C++ style `//` preferred
- Named arguments in calls: `emit(/*prefix=*/nullptr)`
- No restating what the code obviously does

---

## 4. Formatting

Run `clang-format` with the repo's `.clang-format` config.

| Rule | Value |
|------|-------|
| Line length | 80 columns max |
| Indentation | 2 spaces (no tabs) |
| Trailing whitespace | Forbidden |
| Line endings | Unix LF |
| Namespace bodies | Not indented |

### Braces

```cpp
// Functions: opening brace on next line
void foo()
{
  // ...
}

// Control flow: opening brace on same line
if (condition) {
  // ...
} else {
  // ...
}

// Single simple statement: braces optional
if (x)
  return;

// BUT use braces if any branch in an if/else chain uses them
if (x) {
  foo();
  bar();
} else {
  baz();  // braces required for consistency
}
```

### Spaces

```cpp
if (condition)        // Space before paren in control flow
while (running)       // Space before paren in control flow
somefunc(42)          // NO space before paren in function calls
assert(x > 0)        // NO space before paren in function calls
```

### Namespace closing

```cpp
namespace cir {
// no indentation
} // namespace cir
```

---

## 5. C++ Feature Usage

### Required

| Pattern | Rule |
|---------|------|
| `isa<>`, `cast<>`, `dyn_cast<>` | Use instead of `dynamic_cast` (no RTTI) |
| `llvm_unreachable()` | For code paths that must never execute |
| `assert(cond && "msg")` | For testable invariants |
| `raw_ostream` | Instead of `iostream` (`#include <iostream>` forbidden in libraries) |
| `'\n'` | Instead of `std::endl` (avoids flush) |
| `++i` | Prefer pre-increment over post-increment |
| `llvm::SmallVector` | Instead of `std::vector` for small/known-size collections |
| `llvm::DenseMap` | Instead of `std::map` / `std::unordered_map` |
| `llvm::StringRef` | Instead of `const std::string&` for non-owning string references |

### Allowed with Care

| Pattern | Rule |
|---------|------|
| `auto` | OK when type is obvious: `auto *op = cast<FuncOp>(...)`, iterators, lambdas |
| `auto &` | For values (avoid copies); `auto *` for pointers |
| Range-for | Preferred: `for (auto &op : block.getOperations())` |
| Braced init | OK for aggregates: `map.insert({key, value})`. NOT for constructor calls with logic |

### Forbidden

| Pattern | Why |
|---------|-----|
| Exceptions | LLVM builds with `-fno-exceptions` |
| RTTI / `dynamic_cast` | LLVM builds with `-fno-rtti`; use `isa/cast/dyn_cast` |
| `#include <iostream>` | Use `raw_ostream` |
| `std::endl` | Use `'\n'` |
| Global constructors/destructors | Non-deterministic init order |
| `using namespace std` | Never. `using namespace llvm/mlir` OK in `.cpp` after includes |

---

## 6. Code Structure

### Early Returns (Mandatory Pattern)

```cpp
// GOOD: early exit
Value simplify(Operation *op) {
  if (!op->hasOneUse())
    return {};
  if (!isa<AddOp>(op))
    return {};
  // actual logic at low indentation
  return foldedValue;
}

// BAD: deep nesting
Value simplify(Operation *op) {
  if (op->hasOneUse()) {
    if (isa<AddOp>(op)) {
      // logic buried in indentation
    }
  }
  return {};
}
```

### No `else` After Return

```cpp
// GOOD
if (failed)
  return failure();
doWork();  // no else needed

// BAD
if (failed)
  return failure();
else
  doWork();
```

### Extract Predicates

```cpp
// GOOD: named predicate
static bool containsUnsupportedOp(Block &block) {
  return llvm::any_of(block, [](Operation &op) {
    return isa<UnresolvedOp>(op);
  });
}

// BAD: inline loop computing boolean
```

### Anonymous Namespaces

Use `static` for file-scoped functions. Use anonymous namespaces only for class
declarations that must be file-local:

```cpp
// For functions: use static
static LogicalResult simplifyAdd(AddOp op) { ... }

// For classes: use anonymous namespace
namespace {
struct MyRewritePattern : OpRewritePattern<AddOp> { ... };
} // namespace
```

### Non-Const References for Output Args

MLIR convention: non-nullable output arguments are passed by non-const reference
(except IR units like Region, Block, Operation):

```cpp
void getResults(SmallVectorImpl<Value> &results);  // output param
```

---

## 7. MLIR-Specific Conventions

### Pass Registration

Prefix dialect name to pass names and options:

```cpp
// Pass name: -cir-type-inference
// Option: -cir-type-inference-max-iterations=10
```

### IR Verification

- Only verify **local** properties of an operation
- Never follow def-use chains in verifiers
- Never look at the producer of operands or users of results
- Passes assume input IR is verifier-valid
- Passes must produce verifier-valid output IR

### Testing (FileCheck/lit)

```
// RUN: cir-opt %s --cir-type-inference | FileCheck %s

// CHECK-LABEL: func @test_add
// CHECK-NEXT:    %[[A:.*]] = cir.constant 1 : i32
// CHECK-NEXT:    %[[B:.*]] = cir.constant 2 : i32
// CHECK-NEXT:    %[[C:.*]] = cir.add %[[A]], %[[B]] : i32
// CHECK-NEXT:    return %[[C]] : i32
```

Rules:
- `CHECK-LABEL` to anchor function boundaries
- Use `%[[NAME:.*]]` captures for SSA values
- Test minimal behavior, not formatting details
- Prefix negative tests with `negative_` or `no_`
- Meaningful variable names: `%base`, `%mask` not `%arg0`
- Block comments to describe what pattern is being tested

### TableGen Conventions

Operations defined in `.td` files following ODS (Operation Definition Specification):
- One `.td` file per dialect or logical group
- Op names use UpperCamelCase: `CIR_AddOp`, `CIR_FuncOp`
- Dialect prefix in op mnemonic: `cir.add`, `cir.func`

### Pass Structure

```cpp
namespace {
struct TypeInferencePass
    : public PassWrapper<TypeInferencePass, OperationPass<ModuleOp>> {
  void runOnOperation() override {
    ModuleOp module = getOperation();
    // ...
  }
  StringRef getArgument() const final { return "cir-type-inference"; }
  StringRef getDescription() const final {
    return "Infer types for CIR operations";
  }
};
} // namespace
```
