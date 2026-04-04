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

.PHONY: all configure libcir libzc libtc cot test test-lit test-gate test-inline test-build install clean

all: cot

# Step 1: Configure cmake (creates build/)
configure:
	@cmake -B build -DCMAKE_BUILD_TYPE=Release \
		-DMLIR_DIR=$(MLIR_DIR) -DLLVM_DIR=$(LLVM_DIR) \
		-DCMAKE_EXPORT_COMPILE_COMMANDS=ON 2>&1 | tail -3

# Step 2: Build libcir first (libzc/libtc link against it)
libcir: configure
	@cmake --build build --target CIR --parallel

# Step 3: Non-CMake frontends (need libCIR.a from step 2)
libzc: libcir
	@cd libzc && $(ZIG) build -Doptimize=ReleaseSafe

libtc: libcir
	@cd libtc && CGO_ENABLED=1 go build -buildmode=c-archive -o libtc.a .

# Step 4: Build everything (libcot + cot driver link against libzc/libtc)
cot: libzc libtc
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
