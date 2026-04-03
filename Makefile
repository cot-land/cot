# COT Compiler Toolkit — unified build
#
# Usage:
#   make          Build everything (libcir → libcot → libzc → cot)
#   make test     Run all test layers
#   make clean    Remove build artifacts
#
# Dependencies must be built in order. Parallel where safe.

ZIG ?= ~/bin/zig-nightly

.PHONY: all libcir libcot libzc cot test test-lit test-gate test-inline test-build clean

all: cot

libcir:
	@cd libcir/build && cmake --build . --parallel

libcot: libcir
	@cd libcot/build && cmake --build . --parallel

libzc: libcir
	@cd libzc && $(ZIG) build -Doptimize=ReleaseSafe

cot: libcot libzc
	@cd cot/build && cmake --build . --parallel

test: test-lit test-gate test-inline test-build

test-lit: cot
	@bin/lit test/lit/ -v

test-gate: cot
	@cd cot/build && ./cot test

test-inline: cot
	@cd cot/build && ./cot test ../../test/inline/005_inline_test.ac
	@cd cot/build && ./cot test ../../test/inline/010_bitwise_test.ac
	@cd cot/build && ./cot test ../../test/inline/015_variables_test.ac
	@cd cot/build && ./cot test ../../test/inline/016_if_expr_test.ac
	@cd cot/build && ./cot test ../../test/inline/017_while_test.ac
	@cd cot/build && ./cot test ../../test/inline/018_break_continue_test.ac
	@cd cot/build && ./cot test ../../test/inline/019_for_test.ac
	@cd cot/build && ./cot test ../../test/inline/020_nested_calls_test.ac

test-build: cot
	@cd test && bash run.sh ../cot/build/cot

clean:
	@cd libcir/build && cmake --build . --target clean 2>/dev/null || true
	@cd libcot/build && cmake --build . --target clean 2>/dev/null || true
	@cd libzc && rm -rf zig-out .zig-cache 2>/dev/null || true
	@cd cot/build && cmake --build . --target clean 2>/dev/null || true
