# COT Compiler Toolkit — unified build
#
# Usage:
#   make          Build everything
#   make test     Run all test layers
#   make install  Install to PREFIX (default: /usr/local)
#   make clean    Remove build artifacts
#
# Build order: cmake configure → libcir (C++) → libzc (Zig) + libtc (Go) → libcot + cot

ZIG ?= ~/bin/zig-nightly
PREFIX ?= /usr/local

MLIR_DIR ?= /opt/homebrew/Cellar/llvm@20/20.1.8/lib/cmake/mlir
LLVM_DIR ?= /opt/homebrew/Cellar/llvm@20/20.1.8/lib/cmake/llvm

.PHONY: all configure configure-debug libcir libzc libtc libsc cot debug test test-lit test-gate test-inline test-build install clean

all: cot

# Step 1: Configure cmake (creates build/), ensure Release mode
configure:
	@cmake -B build -DCMAKE_BUILD_TYPE=Release \
		-DMLIR_DIR=$(MLIR_DIR) -DLLVM_DIR=$(LLVM_DIR) \
		-DCMAKE_EXPORT_COMPILE_COMMANDS=ON 2>&1 | tail -3
	@sed -i '' 's/CMAKE_BUILD_TYPE:STRING=Debug/CMAKE_BUILD_TYPE:STRING=Release/' build/CMakeCache.txt 2>/dev/null || true

# Debug build: -g -O0 for lldb stepping through pipeline
# Force reconfigure by patching cache (cmake --fresh unreliable)
configure-debug:
	@cmake -B build -DMLIR_DIR=$(MLIR_DIR) -DLLVM_DIR=$(LLVM_DIR) \
		-DCMAKE_EXPORT_COMPILE_COMMANDS=ON 2>&1 | tail -3
	@sed -i '' 's/CMAKE_BUILD_TYPE:STRING=Release/CMAKE_BUILD_TYPE:STRING=Debug/' build/CMakeCache.txt

# Step 2: Build libcir first (libzc/libtc link against it)
libcir: configure
	@cmake --build build --target CIR --parallel

# Step 3: Non-CMake frontends (need libCIR.a from step 2)
libzc: libcir
	@cd libzc && $(ZIG) build -Doptimize=ReleaseSafe

libtc: libcir
	@cd libtc && CGO_ENABLED=1 go build -buildmode=c-archive -o libtc.a .

libsc: libcir
	@swiftc -emit-library -static -o libsc/libsc.a \
		-import-objc-header libsc/bridge.h \
		-I libcir/c-api -I libcir/include -I build/libcir/include \
		-I /opt/homebrew/Cellar/llvm@20/20.1.8/include \
		libsc/sc.swift

# Step 4: Build everything (libcot + cot driver link against libzc/libtc/libsc)
cot: libzc libtc libsc
	@cmake --build build --parallel

# Debug build: -g -O0 for lldb/CodeLLDB stepping
# Flips to Debug, rebuilds C++ (Zig/Go/Swift unaffected), leaves binary with symbols
debug:
	@sed -i '' 's/CMAKE_BUILD_TYPE:STRING=Release/CMAKE_BUILD_TYPE:STRING=Debug/' build/CMakeCache.txt 2>/dev/null || true
	@cmake --build build --parallel

# Tests
test: cot
	@bin/lit test/lit/ -v
	@./build/cot/cot test
	@cd test && bash run_inline.sh ../build/cot/cot
	@cd test && bash run.sh ../build/cot/cot

test-lit: cot
	@bin/lit test/lit/ -v

test-gate: cot
	@./build/cot/cot test

test-inline: cot
	@cd test && bash run_inline.sh ../build/cot/cot

test-build: cot
	@cd test && bash run.sh ../build/cot/cot

# Install (Homebrew-compatible layout)
install: cot
	@cmake --install build --prefix=$(PREFIX)

clean:
	@rm -rf build
	@cd libzc && rm -rf zig-out .zig-cache 2>/dev/null || true
	@rm -f libtc/libtc.a libtc/libtc.h 2>/dev/null || true
	@rm -f libsc/libsc.a 2>/dev/null || true
