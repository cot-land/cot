# `cot mcp` — Compiler-Powered MCP Server

**Status:** Spec
**Target:** 0.4
**Parallel-safe:** Yes — touches only `compiler/lsp/mcp_*.zig` and `compiler/cli.zig` + `compiler/main.zig` (minor additions)

---

## Overview

Add a `cot mcp` subcommand that starts an MCP (Model Context Protocol) server over stdio. It reuses the LSP's analysis infrastructure (`analysis.zig`, `document_store.zig`, `types.zig`) to give Claude Code compiler-powered tools: diagnostics, type info, symbol listing, build, and test execution.

The existing Cot-written MCP server (`mcp/cot-mcp.cot`) becomes an example app / stdlib showcase. `cot mcp` replaces it for production use.

---

## Architecture

```
cot mcp (stdio)
  ├── mcp_main.zig      — Entry point: stdio JSON-RPC loop (like lsp/main.zig)
  ├── mcp_server.zig     — Method dispatch + tool handlers
  ├── analysis.zig       — REUSE: frontend pipeline (parse → check → errors)
  ├── document_store.zig — REUSE: file caching (optional, for repeated checks)
  ├── types.zig          — REUSE: Position, Range, Diagnostic helpers
  └── transport.zig      — NEW or REUSE: JSON-RPC framing
```

### Protocol

MCP uses JSON-RPC 2.0 over stdio, newline-delimited (NOT Content-Length framed like LSP). This is the one difference from LSP transport — `mcp_main.zig` reads line-by-line instead of using `transport.zig`.

### Message Flow

```
Client → {"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}
Server → {"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2024-11-05",...}}

Client → {"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}
Server → {"jsonrpc":"2.0","id":2,"result":{"tools":[...]}}

Client → {"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"check_file","arguments":{"path":"src/main.cot"}}}
Server → {"jsonrpc":"2.0","id":3,"result":{"content":[{"type":"text","text":"..."}]}}
```

---

## Tools

### 1. `check_file` — Compile and return diagnostics

**Input:**
```json
{"path": "src/main.cot"}
```

**What it does:**
1. Reads file from disk (absolute or relative path)
2. Runs `analysis.analyze()` — Scanner → Parser → Checker
3. Collects errors via callback
4. Returns diagnostics with line numbers

**Output (success):**
```
No errors found in src/main.cot
```

**Output (errors):**
```
src/main.cot:12:5: error E1024: undefined variable 'foo'
src/main.cot:25:10: error E2001: type mismatch: expected i64, got string
```

**Implementation:** Call `analysis.analyze()` from `compiler/lsp/analysis.zig`, convert errors via `diagnostics.convertErrors()`, format as text.

### 2. `get_type` — Type of expression at position

**Input:**
```json
{"path": "src/main.cot", "line": 12, "character": 15}
```

**What it does:**
1. Analyzes file
2. Converts LSP position to byte offset via `types.lspToByteOffset()`
3. Finds AST node at offset via `hover.findNodeAtOffset()`
4. Looks up type in `checker.expr_types`
5. Returns type as string

**Output:**
```
Type at line 12, col 15: List(i64)
```

**Implementation:** Reuse `hover.getHover()` from `compiler/lsp/hover.zig`, extract the type string.

### 3. `find_definition` — Where a symbol is defined

**Input:**
```json
{"path": "src/main.cot", "line": 12, "character": 15}
```

**What it does:**
1. Analyzes file
2. Finds identifier at position
3. Looks up in scope chain
4. Returns definition location

**Output:**
```
Defined at src/main.cot:5:1 (function declaration)
```

**Implementation:** Reuse `goto.getDefinition()` from `compiler/lsp/goto.zig`.

### 4. `list_symbols` — All symbols in a file

**Input:**
```json
{"path": "src/main.cot"}
```

**What it does:**
1. Analyzes file
2. Walks AST root declarations
3. Lists functions, structs, enums, consts, imports

**Output:**
```
Functions:
  main() void (line 5)
  processData(input: string) i64 (line 20)

Structs:
  Point { x: i64, y: i64 } (line 1)

Imports:
  std/json (line 1)
  std/string (line 2)
```

**Implementation:** Reuse `document_symbol.getDocumentSymbols()` from `compiler/lsp/document_symbol.zig`, format as text.

### 5. `build` — Compile a file

**Input:**
```json
{"path": "src/main.cot", "target": "native", "output": "app"}
```

**What it does:**
1. Invokes the full compilation pipeline via `driver.compileFile()`
2. Returns success with output path, or errors

**Output (success):**
```
Build successful: ./app (arm64-macos, 45.2 KB)
```

**Output (failure):**
```
Build failed:
src/main.cot:12:5: error E1024: undefined variable 'foo'
```

**Implementation:** Call `compileAndLink()` from `compiler/main.zig` (may need to extract into a callable function).

### 6. `run_tests` — Run tests in a file

**Input:**
```json
{"path": "test/e2e/features.cot", "target": "native"}
```

**What it does:**
1. Compiles in test mode
2. Executes the test binary
3. Captures stdout/stderr
4. Returns pass/fail results

**Output:**
```
127 passed, 0 failed

All tests passed.
```

**Output (failures):**
```
125 passed, 2 failed

FAIL: "string concatenation" at line 45
  expected: "hello world"
  got: "helloworld"

FAIL: "list bounds" at line 89
  expected error, got success
```

**Implementation:** Use `std.process.Child` to spawn `cot test <path>` and capture output. Alternatively, call the test pipeline directly in-process.

### 7. `get_syntax_reference` — Static docs (carried over)

No input. Returns the Cot syntax cheat sheet.

### 8. `get_stdlib_docs` — Static docs (carried over)

**Input:**
```json
{"module": "json"}
```

Returns function signatures for the specified stdlib module.

### 9. `get_project_info` — Static docs (carried over)

No input. Returns CLI commands, project structure, test writing guide.

---

## Implementation Plan

### Step 1: Wire up `cot mcp` subcommand

**Files:** `compiler/cli.zig`, `compiler/main.zig`

1. Add `mcp` to `Command` union in `cli.zig`
2. Add `"mcp"` recognition in `parseArgs()`
3. Add to help text
4. Add dispatch in `main.zig` → `mcp_main.run(allocator)`

### Step 2: Create `compiler/lsp/mcp_main.zig`

Stdio loop — read newline-delimited JSON-RPC, dispatch to `mcp_server`, write response + newline.

```
pub fn run(allocator: std.mem.Allocator) void {
    var server = McpServer.init(allocator);
    // Read lines from stdin
    // Parse JSON-RPC
    // Dispatch to server.handleMessage()
    // Write response + newline to stdout
}
```

### Step 3: Create `compiler/lsp/mcp_server.zig`

Method dispatch:
- `initialize` → protocol version, capabilities, server info
- `tools/list` → tool definitions with inputSchema
- `tools/call` → route to tool handler by name

Tool handlers call into existing LSP modules (`analysis.zig`, `hover.zig`, `goto.zig`, `document_symbol.zig`) and format results as text.

### Step 4: Static tool handlers

Port `get_syntax_reference`, `get_stdlib_docs`, `get_project_info` from the Cot MCP server. These are just embedded strings — straightforward.

### Step 5: Dynamic tool handlers

Implement `check_file`, `get_type`, `find_definition`, `list_symbols` using LSP analysis modules.

### Step 6: Build and test tools

Implement `build` and `run_tests`. These may spawn child processes or call the compilation pipeline directly.

### Step 7: Update `.mcp.json`

```json
{
  "mcpServers": {
    "cot-tools": {
      "type": "stdio",
      "command": "/path/to/cot",
      "args": ["mcp"]
    }
  }
}
```

---

## Testing

1. Manual: pipe JSON-RPC messages via stdin, verify responses
2. Each tool tested individually with known Cot files
3. Error cases: nonexistent file, syntax errors, type errors
4. Integration: configure in Claude Code, verify `/mcp` shows `cot-tools`

---

## Dependencies on Other Work

- **None for Steps 1-5** — all LSP infrastructure exists
- **Step 6 (`build`/`run_tests`)** may need `compileAndLink()` extracted into a callable function, or use `std.process.Child` to spawn `cot build`/`cot test`

---

## What This Replaces

The Cot-written MCP server (`mcp/cot-mcp.cot`) stays in the repo as:
- Example app demonstrating stdlib usage (json, io, string)
- Dogfooding showcase
- Reference for how MCP protocol works

`.mcp.json` switches from `./cot-mcp` to `cot mcp`.
