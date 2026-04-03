#!/bin/bash
# Test runner for ac language tests.
# Each test file returns exit code 42 on success.
# Pattern: MLIR lit-inspired, simplified for bootstrapping.

COT="${1:-../cot/build/cot}"
PASS=0
FAIL=0
ERRORS=""

for f in $(ls *.ac | sort); do
    name=$(basename "$f" .ac)
    tmpfile="/tmp/cot_test_${name}"

    if $COT build "$f" -o "$tmpfile" 2>/dev/null; then
        "$tmpfile" 2>/dev/null
        code=$?
        if [ $code -eq 42 ]; then
            echo "  ✓ $name"
            PASS=$((PASS + 1))
        else
            echo "  ✗ $name (exit $code, expected 42)"
            FAIL=$((FAIL + 1))
            ERRORS="$ERRORS\n  $name: exit $code"
        fi
        rm -f "$tmpfile"
    else
        echo "  ✗ $name (build failed)"
        FAIL=$((FAIL + 1))
        ERRORS="$ERRORS\n  $name: build failed"
    fi
done

echo ""
echo "$PASS passed, $FAIL failed"
if [ $FAIL -gt 0 ]; then
    echo -e "\nFailures:$ERRORS"
    exit 1
fi
