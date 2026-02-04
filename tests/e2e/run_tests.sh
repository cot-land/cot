#!/bin/bash
# E2E Test Runner for Cot Compiler
# Runs tests on both Wasm and Native targets

set -e

SCRIPT_DIR="$(dirname "$0")"
PROJECT_ROOT="$SCRIPT_DIR/../.."
COT_BIN="${COT_BIN:-$PROJECT_ROOT/zig-out/bin/cot}"
TEST_DIR="$SCRIPT_DIR"
TEMP_DIR="/tmp/cot_e2e_tests"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Counters
PASSED=0
FAILED=0
SKIPPED=0

mkdir -p "$TEMP_DIR"

# Run a single test
run_test() {
    local test_file="$1"
    local expected="$2"
    local target="$3"
    local test_name=$(basename "$test_file" .cot)

    if [ "$target" = "wasm" ]; then
        local out_file="$TEMP_DIR/${test_name}.wasm"
        if ! $COT_BIN --target=wasm32 "$test_file" -o "$out_file" 2>/dev/null; then
            echo -e "${RED}✗${NC} $test_name ($target) - compile error"
            return 1
        fi

        local result=$(node -e "
            const fs=require('fs');
            const wasm=fs.readFileSync('$out_file');
            WebAssembly.instantiate(wasm).then(r=>{
                const code=Number(r.instance.exports.main());
                process.exit(code > 127 ? code - 256 : code);
            }).catch(e=>{console.error(e);process.exit(255)});
        " 2>/dev/null; echo $?)
    else
        local out_file="$TEMP_DIR/${test_name}"
        if ! $COT_BIN "$test_file" -o "$out_file" 2>/dev/null; then
            echo -e "${RED}✗${NC} $test_name ($target) - compile error"
            return 1
        fi

        local result=$("$out_file" 2>/dev/null; echo $?)
    fi

    if [ "$result" = "$expected" ]; then
        echo -e "${GREEN}✓${NC} $test_name ($target)"
        return 0
    else
        echo -e "${RED}✗${NC} $test_name ($target) - expected $expected, got $result"
        return 1
    fi
}

# Parse test file for expected value
# Format: first line comment like: // expect: 42
get_expected() {
    local test_file="$1"
    head -1 "$test_file" | grep -o 'expect: [0-9-]*' | cut -d' ' -f2
}

# Main
echo "═══════════════════════════════════════════════"
echo "Cot E2E Test Suite"
echo "═══════════════════════════════════════════════"
echo ""

TARGET="${1:-both}"  # wasm, native, or both

for test_file in "$TEST_DIR"/test_*.cot; do
    [ -f "$test_file" ] || continue

    expected=$(get_expected "$test_file")
    if [ -z "$expected" ]; then
        expected=42  # Default expected value
    fi

    if [ "$TARGET" = "wasm" ] || [ "$TARGET" = "both" ]; then
        if run_test "$test_file" "$expected" "wasm"; then
            ((PASSED++))
        else
            ((FAILED++))
        fi
    fi

    if [ "$TARGET" = "native" ] || [ "$TARGET" = "both" ]; then
        if run_test "$test_file" "$expected" "native"; then
            ((PASSED++))
        else
            ((FAILED++))
        fi
    fi
done

echo ""
echo "═══════════════════════════════════════════════"
if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}All $PASSED tests passed${NC}"
else
    echo -e "${RED}$FAILED failed${NC}, ${GREEN}$PASSED passed${NC}"
fi
echo "═══════════════════════════════════════════════"

exit $FAILED
