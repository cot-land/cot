package main

import (
	"fmt"
	"testing"

	"github.com/microsoft/typescript-go/internal/ast"
	"github.com/microsoft/typescript-go/internal/core"
	"github.com/microsoft/typescript-go/internal/parser"
)

func TestParseAdd(t *testing.T) {
	source := `function add(a: number, b: number): number { return a + b; }`
	opts := ast.SourceFileParseOptions{
		FileName: "/test.ts",
	}
	sf := parser.ParseSourceFile(opts, source, core.ScriptKindTS)
	if sf == nil {
		t.Fatal("ParseSourceFile returned nil")
	}
	if sf.Diagnostics() != nil && len(sf.Diagnostics()) > 0 {
		t.Fatalf("Parse errors: %v", sf.Diagnostics())
	}
	stmts := sf.Statements.Nodes
	if len(stmts) != 1 {
		t.Fatalf("Expected 1 statement, got %d", len(stmts))
	}
	if stmts[0].Kind != ast.KindFunctionDeclaration {
		t.Fatalf("Expected FunctionDeclaration, got %v", stmts[0].Kind)
	}
	fd := stmts[0].AsFunctionDeclaration()
	name := fd.Name().AsIdentifier().Text
	fmt.Printf("Parsed function: %s\n", name)
	if name != "add" {
		t.Fatalf("Expected function name 'add', got '%s'", name)
	}
	t.Logf("Successfully parsed: function %s with %d params", name, len(fd.Parameters.Nodes))
}
