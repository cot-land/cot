# COT Compiler Toolkit — unified build
#
# Usage:
#   make          Build everything (libcir → libcot → libzc → libtc → cot)
#   make test     Run all test layers
#   make clean    Remove build artifacts
#
# Dependencies must be built in order. Parallel where safe.

ZIG ?= ~/bin/zig-nightly

.PHONY: all libcir libcot libzc libtc cot test test-lit test-gate test-inline test-build clean

all: cot

libcir:
	@cd libcir/build && cmake --build . --parallel

libcot: libcir
	@cd libcot/build && cmake --build . --parallel

libzc: libcir
	@cd libzc && $(ZIG) build -Doptimize=ReleaseSafe

libtc: libcir
	@cd libtc && CGO_ENABLED=1 go build -buildmode=c-archive -o libtc.a .

cot: libcot libzc libtc
	@cd cot/build && cmake --build . --parallel

test: test-lit test-gate test-inline test-build

test-lit: cot
	@bin/lit test/lit/ -v

test-gate: cot
	@cd cot/build && ./cot test

test-inline: cot
	@cd test && bash run_inline.sh ../cot/build/cot

test-build: cot
	@cd test && bash run.sh ../cot/build/cot

clean:
	@cd libcir/build && cmake --build . --target clean 2>/dev/null || true
	@cd libcot/build && cmake --build . --target clean 2>/dev/null || true
	@cd libzc && rm -rf zig-out .zig-cache 2>/dev/null || true
	@rm -f libtc/libtc.a libtc/libtc.h 2>/dev/null || true
	@cd cot/build && cmake --build . --target clean 2>/dev/null || true
