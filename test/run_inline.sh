#!/bin/bash
# Inline test runner with per-test timeout.
# Auto-discovers all test/inline/*.ac files.
# Each test is compiled and executed with a timeout to catch infinite loops.

COT="${1:-../cot/build/cot}"
TIMEOUT=10  # seconds per test
PASS=0
FAIL=0
ERRORS=""

for f in $(ls inline/*.ac 2>/dev/null | sort); do
    name=$(basename "$f" .ac)

    # Run cot test with a timeout — catches both compile hangs and runtime hangs
    output=$(perl -e 'alarm shift; exec @ARGV' "$TIMEOUT" "$COT" test "$f" 2>&1)
    code=$?

    if [ $code -eq 142 ] || [ $code -eq 137 ]; then
        echo "  TIMEOUT $name (killed after ${TIMEOUT}s)"
        FAIL=$((FAIL + 1))
        ERRORS="$ERRORS\n  $name: timeout (infinite loop?)"
    elif [ $code -eq 0 ]; then
        # Count tests from output (e.g. "running 3 test(s)")
        count=$(echo "$output" | grep -o '[0-9]* test(s)' | head -1)
        echo "  PASS $name ($count)"
        PASS=$((PASS + 1))
    else
        echo "  FAIL $name (exit $code)"
        FAIL=$((FAIL + 1))
        ERRORS="$ERRORS\n  $name: exit $code"
    fi
done

echo ""
echo "inline: $PASS passed, $FAIL failed"
if [ $FAIL -gt 0 ]; then
    echo -e "\nFailures:$ERRORS"
    exit 1
fi
