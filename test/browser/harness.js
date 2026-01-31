// Cot Wasm Test Harness
// Tests compiled .wasm files in the browser

const tests = [
    // Arithmetic
    { name: 'arithmetic/add', expected: 42 },
    { name: 'arithmetic/mul', expected: 20 },
    { name: 'arithmetic/sub', expected: 8 },
    { name: 'arithmetic/div', expected: 5 },
    { name: 'arithmetic/mod', expected: 3 },
    { name: 'arithmetic/precedence', expected: 14 },
    { name: 'arithmetic/parens', expected: 20 },
    { name: 'arithmetic/complex', expected: 17 },
    { name: 'arithmetic/chain_add', expected: 15 },

    // Control Flow
    { name: 'control_flow/if_true', expected: 1 },
    { name: 'control_flow/if_false', expected: 0 },
    { name: 'control_flow/if_else', expected: 20 },
    { name: 'control_flow/while_simple', expected: 10 },
    { name: 'control_flow/while_break', expected: 5 },
    { name: 'control_flow/while_continue', expected: 20 },
    { name: 'control_flow/nested_if', expected: 3 },
    { name: 'control_flow/nested_while', expected: 6 },
    { name: 'control_flow/comparison_lt', expected: 1 },
    { name: 'control_flow/comparison_le', expected: 1 },
    { name: 'control_flow/comparison_gt', expected: 1 },
    { name: 'control_flow/comparison_ge', expected: 1 },
    { name: 'control_flow/comparison_eq', expected: 1 },
    { name: 'control_flow/comparison_ne', expected: 1 },

    // Functions
    { name: 'functions/simple_call', expected: 42 },
    { name: 'functions/one_param', expected: 10 },
    { name: 'functions/two_params', expected: 7 },
    { name: 'functions/three_params', expected: 14 },
    { name: 'functions/recursion', expected: 120 },
    { name: 'functions/fibonacci', expected: 55 },
    { name: 'functions/chained_calls', expected: 12 },
    { name: 'functions/mutual_recursion', expected: 1 },

    // Memory
    { name: 'memory/local_var', expected: 42 },
    { name: 'memory/multiple_locals', expected: 30 },
    { name: 'memory/reassign', expected: 100 },
    { name: 'memory/swap', expected: 5 },
    { name: 'memory/accumulator', expected: 55 },

    // Structs
    { name: 'structs/simple', expected: 15 },
    { name: 'structs/field_access', expected: 42 },
    { name: 'structs/field_update', expected: 100 },
    { name: 'structs/nested', expected: 6 },
    { name: 'structs/pass_to_fn', expected: 26 },
];

async function runTests() {
    const results = document.getElementById('results');
    const summary = document.getElementById('summary');
    const progressBar = document.getElementById('progressBar');
    const progressText = document.getElementById('progressText');

    let passed = 0;
    let failed = 0;
    let skipped = 0;

    progressBar.max = tests.length;

    for (let i = 0; i < tests.length; i++) {
        const test = tests[i];
        progressBar.value = i + 1;
        progressText.textContent = `Running: ${test.name} (${i + 1}/${tests.length})`;

        try {
            const response = await fetch(`wasm/${test.name}.wasm`);
            if (!response.ok) {
                skipped++;
                results.innerHTML += `<div class="test-result fail">⊘ ${test.name}: wasm file not found</div>`;
                continue;
            }

            const wasm = await WebAssembly.instantiateStreaming(response);
            const result = wasm.instance.exports.main();

            if (result === test.expected) {
                passed++;
                results.innerHTML += `<div class="test-result pass">✓ ${test.name}</div>`;
            } else {
                failed++;
                results.innerHTML += `<div class="test-result fail">✗ ${test.name}: got ${result}, expected ${test.expected}</div>`;
            }
        } catch (e) {
            failed++;
            results.innerHTML += `<div class="test-result fail">✗ ${test.name}: ${e.message}</div>`;
        }
    }

    progressText.textContent = 'Complete!';
    summary.innerHTML = `
        <span class="passed">${passed} passed</span> |
        <span class="failed">${failed} failed</span> |
        ${skipped} skipped |
        ${tests.length} total
    `;
}

runTests();
