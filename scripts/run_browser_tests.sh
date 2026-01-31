#!/bin/bash
# Compile test cases and start browser test server

set -e

COT="./zig-out/bin/cot"
CASES_DIR="test/cases"
WASM_DIR="test/browser/wasm"
PORT="${1:-8080}"

# Ensure compiler is built
if [ ! -f "$COT" ]; then
    echo "Building compiler..."
    zig build
fi

# Create output directory
mkdir -p "$WASM_DIR"

echo "Compiling test cases to Wasm..."
compiled=0
failed=0

# Find all .cot files and compile
for cot_file in $(find "$CASES_DIR" -name "*.cot" | sort); do
    rel_path="${cot_file#$CASES_DIR/}"
    name="${rel_path%.cot}"
    wasm_file="$WASM_DIR/${name}.wasm"

    # Create subdirectory if needed
    mkdir -p "$(dirname "$wasm_file")"

    if "$COT" "$cot_file" -o "$wasm_file" 2>/dev/null; then
        ((compiled++)) || true
    else
        echo "  Failed: $name"
        ((failed++)) || true
    fi
done

echo "Compiled: $compiled, Failed: $failed"
echo ""
echo "Starting server on http://localhost:$PORT"
echo "Open http://localhost:$PORT/runner.html in your browser"
echo "Press Ctrl+C to stop"
echo ""

cd test/browser
python3 -m http.server "$PORT"
