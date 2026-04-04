package main

// libtc — TypeScript-Cot frontend (Go)
//
// C ABI entry point for the cot driver. Parses TypeScript source,
// walks the AST, emits CIR MLIR ops, serializes to bytecode.
//
// Reference: libzc/lib.zig — same C ABI pattern
// Reference: ~/claude/references/typescript-go/ — TypeScript-Go parser

/*
#include <stdlib.h>
#include <string.h>
*/
import "C"
import (
	"unsafe"

	"github.com/microsoft/typescript-go/internal/ast"
	"github.com/microsoft/typescript-go/internal/core"
	"github.com/microsoft/typescript-go/internal/parser"
)

//export tc_parse
func tc_parse(sourcePtr *C.char, sourceLen C.size_t, filename *C.char,
	outPtr **C.char, outLen *C.size_t) C.int {

	// Convert C strings to Go
	source := C.GoStringN(sourcePtr, C.int(sourceLen))
	fname := C.GoString(filename)

	// Parse with TypeScript-Go parser
	opts := ast.SourceFileParseOptions{
		FileName: fname,
	}
	sf := parser.ParseSourceFile(opts, source, core.ScriptKindTS)
	if sf == nil {
		return -1
	}
	if diags := sf.Diagnostics(); len(diags) > 0 {
		return -1
	}

	// Generate CIR
	gen := NewGen()
	gen.Generate(sf)

	// Serialize to bytecode
	bytes, err := SerializeToBytecode(gen.module)
	if err != nil {
		gen.Destroy()
		return -1
	}

	// Copy to C-allocated memory (driver manages lifetime)
	cBytes := C.malloc(C.size_t(len(bytes)))
	C.memcpy(cBytes, unsafe.Pointer(&bytes[0]), C.size_t(len(bytes)))
	*outPtr = (*C.char)(cBytes)
	*outLen = C.size_t(len(bytes))

	gen.Destroy()
	return 0
}

// Required for c-archive build mode
func main() {}
