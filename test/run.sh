#!/bin/bash
# Build test runner with per-test timeout.
# Each test file returns exit code 42 on success.
# Pattern: MLIR lit-inspired, simplified for bootstrapping.

COT="${1:-../cot/build/cot}"
TIMEOUT=10  # seconds per test
PASS=0
FAIL=0
ERRORS=""

for f in $(ls *.ac 2>/dev/null | sort); do
    name=$(basename "$f" .ac)
    tmpfile="/tmp/cot_test_${name}"

    # Compile with timeout
    if perl -e 'alarm shift; exec @ARGV' "$TIMEOUT" $COT build "$f" -o "$tmpfile" 2>/dev/null; then
        # Run binary with timeout
        perl -e 'alarm shift; exec @ARGV' "$TIMEOUT" "$tmpfile" 2>/dev/null
        code=$?
        rm -f "$tmpfile"

        if [ $code -eq 42 ]; then
            echo "  PASS $name"
            PASS=$((PASS + 1))
        elif [ $code -eq 142 ] || [ $code -eq 137 ]; then
            echo "  TIMEOUT $name (killed after ${TIMEOUT}s)"
            FAIL=$((FAIL + 1))
            ERRORS="$ERRORS\n  $name: timeout (infinite loop?)"
        else
            echo "  FAIL $name (exit $code, expected 42)"
            FAIL=$((FAIL + 1))
            ERRORS="$ERRORS\n  $name: exit $code"
        fi
    else
        echo "  FAIL $name (build failed)"
        FAIL=$((FAIL + 1))
        ERRORS="$ERRORS\n  $name: build failed"
        rm -f "$tmpfile"
    fi
done

echo ""
echo "build: $PASS passed, $FAIL failed"
if [ $FAIL -gt 0 ]; then
    echo -e "\nFailures:$ERRORS"
    exit 1
fi
