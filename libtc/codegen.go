package main

// AST walker: TypeScript AST → CIR MLIR ops
//
// Architecture ported from:
//   libzc/astgen.zig — Zig AstGen single-pass recursive dispatch
//   ~/claude/references/zig/lib/std/zig/AstGen.zig
//
// Reference: TypeScript-Go parser AST
//   ~/claude/references/typescript-go/internal/ast/

import (
	"strconv"

	"github.com/microsoft/typescript-go/internal/ast"
)

// LoopContext tracks header/exit blocks for break/continue.
type LoopContext struct {
	header MlirBlock
	exit   MlirBlock
}

// Gen holds codegen state for one module.
type Gen struct {
	ctx    MlirContext
	module MlirModule
	b      Builder

	// Current scope
	paramNames  []string
	paramValues []MlirValue
	localNames  []string
	localAddrs  []MlirValue
	localTypes  []MlirType

	// Current function state
	currentFunc   MlirOperation
	currentBlock  MlirBlock
	hasTerminator bool

	// Loop stack for break/continue
	loopStack []LoopContext

	// Struct (interface) type registry
	structNames      []string
	structTypes      []MlirType
	structFieldNames [][]string
	structFieldTypes [][]MlirType
}

// NewGen creates a new code generator with MLIR context and module.
func NewGen() *Gen {
	ctx := createContext()
	return &Gen{
		ctx:    ctx,
		module: createModule(ctx),
		b:      newBuilder(ctx),
	}
}

// Destroy releases MLIR resources.
func (g *Gen) Destroy() {
	destroyModule(g.module)
	destroyContext(g.ctx)
}

// Generate walks the TypeScript AST and emits CIR ops.
func (g *Gen) Generate(sf *ast.SourceFile) {
	for _, stmt := range sf.Statements.Nodes {
		g.mapDecl(stmt)
	}
}

// ptrType returns the !cir.ptr opaque pointer type.
func (g *Gen) ptrType() MlirType {
	return g.b.ParseType("!cir.ptr")
}

// ============================================================
// Declaration dispatch
// ============================================================

func (g *Gen) mapDecl(node *ast.Node) {
	switch node.Kind {
	case ast.KindFunctionDeclaration:
		g.mapFuncDecl(node)
	case ast.KindInterfaceDeclaration:
		g.mapInterfaceDecl(node)
	}
}

func (g *Gen) mapInterfaceDecl(node *ast.Node) {
	id := node.AsInterfaceDeclaration()
	name := id.Name().AsIdentifier().Text

	var fieldNames []string
	var fieldTypes []MlirType
	typeStr := "!cir.struct<\"" + name + "\""

	if id.Members != nil {
		for _, member := range id.Members.Nodes {
			if member.Kind == ast.KindPropertySignature {
				ps := member.AsPropertySignatureDeclaration()
				fname := ps.Name().AsIdentifier().Text
				fieldNames = append(fieldNames, fname)
				ftype := g.b.IntType(32) // default i32
				ftypeName := "i32"
				if ps.Type != nil {
					ftype = g.resolveType(ps.Type)
					ftypeName = g.resolveTypeName(ps.Type)
				}
				fieldTypes = append(fieldTypes, ftype)
				typeStr += ", " + fname + ": " + ftypeName
			}
		}
	}
	typeStr += ">"

	structType := g.b.ParseType(typeStr)
	g.structNames = append(g.structNames, name)
	g.structTypes = append(g.structTypes, structType)
	g.structFieldNames = append(g.structFieldNames, fieldNames)
	g.structFieldTypes = append(g.structFieldTypes, fieldTypes)
}

func (g *Gen) mapFuncDecl(node *ast.Node) {
	fd := node.AsFunctionDeclaration()
	name := fd.Name().AsIdentifier().Text

	var paramTypes []MlirType
	var pNames []string
	if fd.Parameters != nil {
		for _, param := range fd.Parameters.Nodes {
			pd := param.AsParameterDeclaration()
			pNames = append(pNames, pd.Name().AsIdentifier().Text)
			if pd.Type != nil {
				paramTypes = append(paramTypes, g.resolveType(pd.Type))
			} else {
				paramTypes = append(paramTypes, g.b.IntType(32))
			}
		}
	}

	var resultTypes []MlirType
	if fd.Type != nil {
		resultTypes = append(resultTypes, g.resolveType(fd.Type))
	}

	funcOp, entryBlock := g.b.CreateFunc(g.module, name, paramTypes, resultTypes)
	g.currentFunc = funcOp
	g.paramNames = pNames
	g.paramValues = nil
	for i := range paramTypes {
		g.paramValues = append(g.paramValues, BlockGetArgument(entryBlock, i))
	}
	g.localNames = nil
	g.localAddrs = nil
	g.localTypes = nil
	g.loopStack = nil

	g.hasTerminator = false
	g.currentBlock = entryBlock
	if fd.Body != nil {
		g.mapBlock(entryBlock, fd.Body.AsNode())
	}
	if !g.hasTerminator {
		g.b.Emit(g.currentBlock, "func.return", nil, nil, nil)
	}
}

// ============================================================
// Block and statement mapping
// ============================================================

func (g *Gen) mapBlock(block MlirBlock, node *ast.Node) {
	g.hasTerminator = false
	g.currentBlock = block
	blk := node.AsBlock()
	if blk.Statements != nil {
		for _, stmt := range blk.Statements.Nodes {
			if g.hasTerminator {
				break
			}
			g.mapStmt(stmt)
		}
	}
}

func (g *Gen) mapStmt(node *ast.Node) {
	switch node.Kind {
	case ast.KindReturnStatement:
		g.mapReturn(node)
	case ast.KindExpressionStatement:
		g.mapExprStmt(node)
	case ast.KindVariableStatement:
		g.mapVarStmt(node)
	case ast.KindIfStatement:
		g.mapIfStmt(node)
	case ast.KindWhileStatement:
		g.mapWhileStmt(node)
	case ast.KindForStatement:
		g.mapForStmt(node)
	case ast.KindBreakStatement:
		if len(g.loopStack) > 0 {
			g.b.EmitBranch(g.currentBlock, "cir.br", nil, []MlirBlock{g.loopStack[len(g.loopStack)-1].exit})
			g.hasTerminator = true
		}
	case ast.KindContinueStatement:
		if len(g.loopStack) > 0 {
			g.b.EmitBranch(g.currentBlock, "cir.br", nil, []MlirBlock{g.loopStack[len(g.loopStack)-1].header})
			g.hasTerminator = true
		}
	case ast.KindBlock:
		g.mapBlock(g.currentBlock, node)
	}
}

func (g *Gen) mapReturn(node *ast.Node) {
	rs := node.AsReturnStatement()
	if rs.Expression != nil {
		val := g.mapExpr(g.currentBlock, rs.Expression, g.b.IntType(32))
		g.b.Emit(g.currentBlock, "func.return", nil, []MlirValue{val}, nil)
	} else {
		g.b.Emit(g.currentBlock, "func.return", nil, nil, nil)
	}
	g.hasTerminator = true
}

func (g *Gen) mapExprStmt(node *ast.Node) {
	es := node.AsExpressionStatement()
	expr := es.Expression
	// Handle assignment expressions as statements
	if expr.Kind == ast.KindBinaryExpression {
		be := expr.AsBinaryExpression()
		opKind := be.OperatorToken.Kind
		if opKind == ast.KindEqualsToken {
			g.mapAssign(be)
			return
		}
		if isCompoundAssign(opKind) {
			g.mapCompoundAssign(be)
			return
		}
	}
	g.mapExpr(g.currentBlock, expr, g.b.IntType(32))
}

func (g *Gen) mapVarStmt(node *ast.Node) {
	vs := node.AsVariableStatement()
	declList := vs.DeclarationList.AsVariableDeclarationList()
	for _, decl := range declList.Declarations.Nodes {
		g.mapVarDecl(decl)
	}
}

func (g *Gen) mapVarDecl(node *ast.Node) {
	vd := node.AsVariableDeclaration()
	varName := vd.Name().AsIdentifier().Text
	varType := g.b.IntType(32)
	if vd.Type != nil {
		varType = g.resolveType(vd.Type)
	}

	// Infer array type from initializer if it's an array literal
	if vd.Initializer != nil && vd.Initializer.Kind == ast.KindArrayLiteralExpression {
		ale := vd.Initializer.AsArrayLiteralExpression()
		nElems := 0
		if ale.Elements != nil {
			nElems = len(ale.Elements.Nodes)
		}
		typeStr := "!cir.array<" + strconv.Itoa(nElems) + " x i32>"
		varType = g.b.ParseType(typeStr)
	}

	// Allocate on stack
	addr := g.b.Emit(g.currentBlock, "cir.alloca", []MlirType{g.ptrType()}, nil,
		[]MlirNamedAttr{g.b.NamedAttr("elem_type", g.b.TypeAttr(varType))})

	// Store initializer if present
	if vd.Initializer != nil {
		val := g.mapExpr(g.currentBlock, vd.Initializer, varType)
		g.b.Emit(g.currentBlock, "cir.store", nil, []MlirValue{val, addr}, nil)
	}

	g.localNames = append(g.localNames, varName)
	g.localAddrs = append(g.localAddrs, addr)
	g.localTypes = append(g.localTypes, varType)
}

func (g *Gen) mapAssign(be *ast.BinaryExpression) {
	if be.Left.Kind != ast.KindIdentifier {
		return
	}
	name := be.Left.AsIdentifier().Text
	for i, n := range g.localNames {
		if n == name {
			val := g.mapExpr(g.currentBlock, be.Right, g.localTypes[i])
			g.b.Emit(g.currentBlock, "cir.store", nil, []MlirValue{val, g.localAddrs[i]}, nil)
			return
		}
	}
}

func (g *Gen) mapCompoundAssign(be *ast.BinaryExpression) {
	if be.Left.Kind != ast.KindIdentifier {
		return
	}
	name := be.Left.AsIdentifier().Text
	for i, n := range g.localNames {
		if n == name {
			current := g.b.Emit(g.currentBlock, "cir.load", []MlirType{g.localTypes[i]},
				[]MlirValue{g.localAddrs[i]}, nil)
			rhs := g.mapExpr(g.currentBlock, be.Right, g.localTypes[i])
			opName := compoundAssignOp(be.OperatorToken.Kind)
			result := g.b.Emit(g.currentBlock, opName, []MlirType{g.localTypes[i]},
				[]MlirValue{current, rhs}, nil)
			g.b.Emit(g.currentBlock, "cir.store", nil, []MlirValue{result, g.localAddrs[i]}, nil)
			return
		}
	}
}

func (g *Gen) mapIfStmt(node *ast.Node) {
	is := node.AsIfStatement()
	cond := g.mapExpr(g.currentBlock, is.Expression, g.b.IntType(1))

	thenBlock := g.b.AddBlock(g.currentFunc)
	elseBlock := g.b.AddBlock(g.currentFunc)
	mergeBlock := g.b.AddBlock(g.currentFunc)

	g.b.EmitBranch(g.currentBlock, "cir.condbr", []MlirValue{cond}, []MlirBlock{thenBlock, elseBlock})

	// Then
	g.currentBlock = thenBlock
	g.hasTerminator = false
	if is.ThenStatement != nil {
		if is.ThenStatement.Kind == ast.KindBlock {
			g.mapBlock(thenBlock, is.ThenStatement)
		} else {
			g.mapStmt(is.ThenStatement)
		}
	}
	thenTerminated := g.hasTerminator
	if !thenTerminated {
		g.b.EmitBranch(g.currentBlock, "cir.br", nil, []MlirBlock{mergeBlock})
	}

	// Else
	g.currentBlock = elseBlock
	g.hasTerminator = false
	if is.ElseStatement != nil {
		if is.ElseStatement.Kind == ast.KindBlock {
			g.mapBlock(elseBlock, is.ElseStatement)
		} else {
			g.mapStmt(is.ElseStatement)
		}
	}
	elseTerminated := g.hasTerminator
	if !elseTerminated {
		g.b.EmitBranch(g.currentBlock, "cir.br", nil, []MlirBlock{mergeBlock})
	}

	g.currentBlock = mergeBlock
	// If both branches return, merge is unreachable — add trap terminator
	if thenTerminated && elseTerminated {
		g.b.Emit(mergeBlock, "cir.trap", nil, nil, nil)
		g.hasTerminator = true
	} else {
		g.hasTerminator = false
	}
}

func (g *Gen) mapWhileStmt(node *ast.Node) {
	ws := node.AsWhileStatement()
	headerBlock := g.b.AddBlock(g.currentFunc)
	bodyBlock := g.b.AddBlock(g.currentFunc)
	exitBlock := g.b.AddBlock(g.currentFunc)

	g.b.EmitBranch(g.currentBlock, "cir.br", nil, []MlirBlock{headerBlock})

	// Header: evaluate condition
	g.currentBlock = headerBlock
	cond := g.mapExpr(headerBlock, ws.Expression, g.b.IntType(1))
	g.b.EmitBranch(headerBlock, "cir.condbr", []MlirValue{cond}, []MlirBlock{bodyBlock, exitBlock})

	// Body
	g.loopStack = append(g.loopStack, LoopContext{header: headerBlock, exit: exitBlock})
	g.currentBlock = bodyBlock
	g.hasTerminator = false
	if ws.Statement.Kind == ast.KindBlock {
		g.mapBlock(bodyBlock, ws.Statement)
	} else {
		g.mapStmt(ws.Statement)
	}
	g.loopStack = g.loopStack[:len(g.loopStack)-1]
	if !g.hasTerminator {
		g.b.EmitBranch(g.currentBlock, "cir.br", nil, []MlirBlock{headerBlock})
	}

	g.currentBlock = exitBlock
	g.hasTerminator = false
}

func (g *Gen) mapForStmt(node *ast.Node) {
	fs := node.AsForStatement()
	// for (init; cond; incr) body → desugared to while

	// Emit initializer
	if fs.Initializer != nil {
		if fs.Initializer.Kind == ast.KindVariableDeclarationList {
			vdl := fs.Initializer.AsVariableDeclarationList()
			for _, decl := range vdl.Declarations.Nodes {
				g.mapVarDecl(decl)
			}
		}
	}

	headerBlock := g.b.AddBlock(g.currentFunc)
	bodyBlock := g.b.AddBlock(g.currentFunc)
	exitBlock := g.b.AddBlock(g.currentFunc)

	g.b.EmitBranch(g.currentBlock, "cir.br", nil, []MlirBlock{headerBlock})

	// Header: condition
	g.currentBlock = headerBlock
	if fs.Condition != nil {
		cond := g.mapExpr(headerBlock, fs.Condition, g.b.IntType(1))
		g.b.EmitBranch(headerBlock, "cir.condbr", []MlirValue{cond}, []MlirBlock{bodyBlock, exitBlock})
	} else {
		g.b.EmitBranch(headerBlock, "cir.br", nil, []MlirBlock{bodyBlock})
	}

	// Body
	g.loopStack = append(g.loopStack, LoopContext{header: headerBlock, exit: exitBlock})
	g.currentBlock = bodyBlock
	g.hasTerminator = false
	if fs.Statement.Kind == ast.KindBlock {
		g.mapBlock(bodyBlock, fs.Statement)
	} else {
		g.mapStmt(fs.Statement)
	}
	g.loopStack = g.loopStack[:len(g.loopStack)-1]

	// Incrementor
	if !g.hasTerminator && fs.Incrementor != nil {
		if fs.Incrementor.Kind == ast.KindBinaryExpression {
			be := fs.Incrementor.AsBinaryExpression()
			if isCompoundAssign(be.OperatorToken.Kind) {
				g.mapCompoundAssign(be)
			} else if be.OperatorToken.Kind == ast.KindEqualsToken {
				g.mapAssign(be)
			}
		}
	}
	if !g.hasTerminator {
		g.b.EmitBranch(g.currentBlock, "cir.br", nil, []MlirBlock{headerBlock})
	}

	g.currentBlock = exitBlock
	g.hasTerminator = false
}

// ============================================================
// Expression mapping
// ============================================================

func (g *Gen) mapExpr(block MlirBlock, node *ast.Node, resultType MlirType) MlirValue {
	switch node.Kind {
	case ast.KindNumericLiteral:
		return g.mapNumericLiteral(block, node, resultType)
	case ast.KindIdentifier:
		return g.mapIdentifier(block, node)
	case ast.KindBinaryExpression:
		return g.mapBinaryExpr(block, node, resultType)
	case ast.KindCallExpression:
		return g.mapCallExpr(block, node, resultType)
	case ast.KindParenthesizedExpression:
		return g.mapExpr(block, node.AsParenthesizedExpression().Expression, resultType)
	case ast.KindPrefixUnaryExpression:
		return g.mapPrefixUnary(block, node, resultType)
	case ast.KindConditionalExpression:
		return g.mapConditionalExpr(block, node, resultType)
	case ast.KindPropertyAccessExpression:
		return g.mapPropertyAccess(block, node, resultType)
	case ast.KindArrayLiteralExpression:
		return g.mapArrayLiteral(block, node, resultType)
	case ast.KindElementAccessExpression:
		return g.mapElementAccess(block, node, resultType)
	case ast.KindObjectLiteralExpression:
		return g.mapObjectLiteral(block, node, resultType)
	case ast.KindTrueKeyword:
		boolType := g.b.IntType(1)
		return g.b.Emit(block, "cir.constant", []MlirType{boolType}, nil,
			[]MlirNamedAttr{g.b.NamedAttr("value", g.b.IntAttr(boolType, 1))})
	case ast.KindFalseKeyword:
		boolType := g.b.IntType(1)
		return g.b.Emit(block, "cir.constant", []MlirType{boolType}, nil,
			[]MlirNamedAttr{g.b.NamedAttr("value", g.b.IntAttr(boolType, 0))})
	default:
		return g.b.Emit(block, "cir.constant", []MlirType{resultType}, nil,
			[]MlirNamedAttr{g.b.NamedAttr("value", g.b.IntAttr(resultType, 0))})
	}
}

func (g *Gen) mapNumericLiteral(block MlirBlock, node *ast.Node, resultType MlirType) MlirValue {
	lit := node.AsNumericLiteral()
	val, _ := strconv.ParseInt(lit.Text, 10, 64)
	return g.b.Emit(block, "cir.constant", []MlirType{resultType}, nil,
		[]MlirNamedAttr{g.b.NamedAttr("value", g.b.IntAttr(resultType, val))})
}

func (g *Gen) mapIdentifier(block MlirBlock, node *ast.Node) MlirValue {
	name := node.AsIdentifier().Text
	for i := len(g.localNames) - 1; i >= 0; i-- {
		if g.localNames[i] == name {
			return g.b.Emit(block, "cir.load", []MlirType{g.localTypes[i]},
				[]MlirValue{g.localAddrs[i]}, nil)
		}
	}
	for i, n := range g.paramNames {
		if n == name {
			return g.paramValues[i]
		}
	}
	return MlirValue{}
}

func (g *Gen) mapBinaryExpr(block MlirBlock, node *ast.Node, resultType MlirType) MlirValue {
	be := node.AsBinaryExpression()
	opKind := be.OperatorToken.Kind

	// Comparisons return i1 but operands should be i32
	opResultType := resultType
	if isCmpOp(opKind) && isI1Type(resultType, g.b) {
		opResultType = g.b.IntType(32)
	}

	lhs := g.mapExpr(block, be.Left, opResultType)
	rhs := g.mapExpr(block, be.Right, opResultType)

	switch opKind {
	// Arithmetic
	case ast.KindPlusToken:
		return g.b.Emit(block, "cir.add", []MlirType{opResultType}, []MlirValue{lhs, rhs}, nil)
	case ast.KindMinusToken:
		return g.b.Emit(block, "cir.sub", []MlirType{opResultType}, []MlirValue{lhs, rhs}, nil)
	case ast.KindAsteriskToken:
		return g.b.Emit(block, "cir.mul", []MlirType{opResultType}, []MlirValue{lhs, rhs}, nil)
	case ast.KindSlashToken:
		return g.b.Emit(block, "cir.div", []MlirType{opResultType}, []MlirValue{lhs, rhs}, nil)
	case ast.KindPercentToken:
		return g.b.Emit(block, "cir.rem", []MlirType{opResultType}, []MlirValue{lhs, rhs}, nil)
	// Bitwise
	case ast.KindAmpersandToken:
		return g.b.Emit(block, "cir.bit_and", []MlirType{opResultType}, []MlirValue{lhs, rhs}, nil)
	case ast.KindBarToken:
		return g.b.Emit(block, "cir.bit_or", []MlirType{opResultType}, []MlirValue{lhs, rhs}, nil)
	case ast.KindCaretToken:
		return g.b.Emit(block, "cir.bit_xor", []MlirType{opResultType}, []MlirValue{lhs, rhs}, nil)
	case ast.KindLessThanLessThanToken:
		return g.b.Emit(block, "cir.shl", []MlirType{opResultType}, []MlirValue{lhs, rhs}, nil)
	case ast.KindGreaterThanGreaterThanToken:
		return g.b.Emit(block, "cir.shr", []MlirType{opResultType}, []MlirValue{lhs, rhs}, nil)
	// Comparisons
	case ast.KindEqualsEqualsToken, ast.KindEqualsEqualsEqualsToken:
		return g.emitCmp(block, lhs, rhs, 0)
	case ast.KindExclamationEqualsToken, ast.KindExclamationEqualsEqualsToken:
		return g.emitCmp(block, lhs, rhs, 1)
	case ast.KindLessThanToken:
		return g.emitCmp(block, lhs, rhs, 2)
	case ast.KindLessThanEqualsToken:
		return g.emitCmp(block, lhs, rhs, 3)
	case ast.KindGreaterThanToken:
		return g.emitCmp(block, lhs, rhs, 4)
	case ast.KindGreaterThanEqualsToken:
		return g.emitCmp(block, lhs, rhs, 5)
	}
	return MlirValue{}
}

func (g *Gen) emitCmp(block MlirBlock, lhs, rhs MlirValue, predicate int64) MlirValue {
	boolType := g.b.IntType(1)
	i64Type := g.b.IntType(64)
	return g.b.Emit(block, "cir.cmp", []MlirType{boolType}, []MlirValue{lhs, rhs},
		[]MlirNamedAttr{g.b.NamedAttr("predicate", g.b.IntAttr(i64Type, predicate))})
}

func (g *Gen) mapCallExpr(block MlirBlock, node *ast.Node, resultType MlirType) MlirValue {
	ce := node.AsCallExpression()
	calleeName := ""
	var args []MlirValue

	// Method call: p.distance() — callee is PropertyAccessExpression
	// Reference: Zig AstGen — methods desugar to call with receiver as first arg
	if ce.Expression.Kind == ast.KindPropertyAccessExpression {
		pa := ce.Expression.AsPropertyAccessExpression()
		calleeName = pa.Name().AsIdentifier().Text
		// Emit receiver as first argument
		receiver := g.mapExpr(block, pa.Expression, resultType)
		args = append(args, receiver)
	} else if ce.Expression.Kind == ast.KindIdentifier {
		calleeName = ce.Expression.AsIdentifier().Text
	}

	if ce.Arguments != nil {
		for _, arg := range ce.Arguments.Nodes {
			args = append(args, g.mapExpr(block, arg, resultType))
		}
	}
	return g.b.Emit(block, "func.call", []MlirType{resultType}, args,
		[]MlirNamedAttr{g.b.NamedAttr("callee", g.b.FlatSymbolRefAttr(calleeName))})
}

func (g *Gen) mapPrefixUnary(block MlirBlock, node *ast.Node, resultType MlirType) MlirValue {
	pu := node.AsPrefixUnaryExpression()
	operand := g.mapExpr(block, pu.Operand, resultType)
	switch pu.Operator {
	case ast.KindMinusToken:
		return g.b.Emit(block, "cir.neg", []MlirType{resultType}, []MlirValue{operand}, nil)
	case ast.KindTildeToken:
		return g.b.Emit(block, "cir.bit_not", []MlirType{resultType}, []MlirValue{operand}, nil)
	case ast.KindExclamationToken:
		one := g.b.Emit(block, "cir.constant", []MlirType{resultType}, nil,
			[]MlirNamedAttr{g.b.NamedAttr("value", g.b.IntAttr(resultType, 1))})
		return g.b.Emit(block, "cir.bit_xor", []MlirType{resultType}, []MlirValue{operand, one}, nil)
	}
	return operand
}

// Array literal: [1, 2, 3] → cir.array_init
func (g *Gen) mapArrayLiteral(block MlirBlock, node *ast.Node, resultType MlirType) MlirValue {
	ale := node.AsArrayLiteralExpression()
	var elemVals []MlirValue
	elemType := g.b.IntType(32)
	if ale.Elements != nil {
		for _, elem := range ale.Elements.Nodes {
			elemVals = append(elemVals, g.mapExpr(block, elem, elemType))
		}
	}
	// Build array type string
	typeStr := "!cir.array<" + strconv.Itoa(len(elemVals)) + " x i32>"
	arrayType := g.b.ParseType(typeStr)
	return g.b.Emit(block, "cir.array_init", []MlirType{arrayType}, elemVals, nil)
}

// Element access: arr[i] → cir.elem_val
func (g *Gen) mapElementAccess(block MlirBlock, node *ast.Node, resultType MlirType) MlirValue {
	ea := node.AsElementAccessExpression()
	arr := g.mapExpr(block, ea.Expression, resultType)
	// Get constant index from argument
	var idxVal int64
	if ea.ArgumentExpression != nil && ea.ArgumentExpression.Kind == ast.KindNumericLiteral {
		lit := ea.ArgumentExpression.AsNumericLiteral()
		idxVal, _ = strconv.ParseInt(lit.Text, 10, 64)
	}
	return g.b.Emit(block, "cir.elem_val", []MlirType{resultType}, []MlirValue{arr},
		[]MlirNamedAttr{g.b.NamedAttr("index", g.b.IntAttr(g.b.IntType(64), idxVal))})
}

// Property access: p.x → cir.field_val
func (g *Gen) mapPropertyAccess(block MlirBlock, node *ast.Node, resultType MlirType) MlirValue {
	pa := node.AsPropertyAccessExpression()
	fieldName := pa.Name().AsIdentifier().Text

	// Emit object expression
	obj := g.mapExpr(block, pa.Expression, resultType)
	objType := ValueGetType(obj)

	// Find struct index and field index
	for i, st := range g.structTypes {
		if TypeEqual(st, objType) {
			for j, fn := range g.structFieldNames[i] {
				if fn == fieldName {
					return g.b.Emit(block, "cir.field_val",
						[]MlirType{g.structFieldTypes[i][j]}, []MlirValue{obj},
						[]MlirNamedAttr{g.b.NamedAttr("field_index",
							g.b.IntAttr(g.b.IntType(64), int64(j)))})
				}
			}
			break
		}
	}
	return MlirValue{}
}

// Object literal: { x: 1, y: 2 } → cir.struct_init (when resultType is a struct)
func (g *Gen) mapObjectLiteral(block MlirBlock, node *ast.Node, resultType MlirType) MlirValue {
	ole := node.AsObjectLiteralExpression()

	// Find struct index from resultType
	structIdx := -1
	for i, st := range g.structTypes {
		if TypeEqual(st, resultType) {
			structIdx = i
			break
		}
	}
	if structIdx < 0 {
		// Fallback: return zero constant
		return g.b.Emit(block, "cir.constant", []MlirType{g.b.IntType(32)}, nil,
			[]MlirNamedAttr{g.b.NamedAttr("value", g.b.IntAttr(g.b.IntType(32), 0))})
	}

	fieldNames := g.structFieldNames[structIdx]
	fieldTypes := g.structFieldTypes[structIdx]
	nFields := len(fieldNames)

	// Initialize all field values to zero
	fieldVals := make([]MlirValue, nFields)
	for i := 0; i < nFields; i++ {
		fieldVals[i] = g.b.Emit(block, "cir.constant", []MlirType{fieldTypes[i]}, nil,
			[]MlirNamedAttr{g.b.NamedAttr("value", g.b.IntAttr(fieldTypes[i], 0))})
	}

	// Fill in provided fields from the object literal
	if ole.Properties != nil {
		for _, prop := range ole.Properties.Nodes {
			if prop.Kind == ast.KindPropertyAssignment {
				pa := prop.AsPropertyAssignment()
				propName := pa.Name().AsIdentifier().Text
				// Find field index
				for j, fn := range fieldNames {
					if fn == propName {
						fieldVals[j] = g.mapExpr(block, pa.Initializer, fieldTypes[j])
						break
					}
				}
			}
		}
	}

	return g.b.Emit(block, "cir.struct_init", []MlirType{resultType}, fieldVals, nil)
}

// cond ? thenVal : elseVal → cir.select
func (g *Gen) mapConditionalExpr(block MlirBlock, node *ast.Node, resultType MlirType) MlirValue {
	ce := node.AsConditionalExpression()
	cond := g.mapExpr(block, ce.Condition, g.b.IntType(1))
	thenVal := g.mapExpr(block, ce.WhenTrue, resultType)
	elseVal := g.mapExpr(block, ce.WhenFalse, resultType)
	return g.b.Emit(block, "cir.select", []MlirType{resultType}, []MlirValue{cond, thenVal, elseVal}, nil)
}

// ============================================================
// Type resolution
// ============================================================

func (g *Gen) resolveType(node *ast.Node) MlirType {
	switch node.Kind {
	case ast.KindNumberKeyword:
		return g.b.IntType(32)
	case ast.KindBooleanKeyword:
		return g.b.IntType(1)
	case ast.KindVoidKeyword:
		return g.b.IntType(0)
	case ast.KindTypeReference:
		tr := node.AsTypeReference()
		if tr.TypeName != nil && tr.TypeName.Kind == ast.KindIdentifier {
			name := tr.TypeName.AsIdentifier().Text
			for i, sn := range g.structNames {
				if sn == name {
					return g.structTypes[i]
				}
			}
		}
	}
	return g.b.IntType(32)
}

func (g *Gen) resolveTypeName(node *ast.Node) string {
	switch node.Kind {
	case ast.KindNumberKeyword:
		return "i32"
	case ast.KindBooleanKeyword:
		return "i1"
	case ast.KindVoidKeyword:
		return "i0"
	}
	return "i32"
}

// ============================================================
// Helpers
// ============================================================

func isCmpOp(kind ast.Kind) bool {
	return kind == ast.KindEqualsEqualsToken ||
		kind == ast.KindEqualsEqualsEqualsToken ||
		kind == ast.KindExclamationEqualsToken ||
		kind == ast.KindExclamationEqualsEqualsToken ||
		kind == ast.KindLessThanToken ||
		kind == ast.KindLessThanEqualsToken ||
		kind == ast.KindGreaterThanToken ||
		kind == ast.KindGreaterThanEqualsToken
}

func isCompoundAssign(kind ast.Kind) bool {
	return kind == ast.KindPlusEqualsToken ||
		kind == ast.KindMinusEqualsToken ||
		kind == ast.KindAsteriskEqualsToken ||
		kind == ast.KindSlashEqualsToken ||
		kind == ast.KindPercentEqualsToken
}

func compoundAssignOp(kind ast.Kind) string {
	switch kind {
	case ast.KindPlusEqualsToken:
		return "cir.add"
	case ast.KindMinusEqualsToken:
		return "cir.sub"
	case ast.KindAsteriskEqualsToken:
		return "cir.mul"
	case ast.KindSlashEqualsToken:
		return "cir.div"
	case ast.KindPercentEqualsToken:
		return "cir.rem"
	}
	return "cir.add"
}

func isI1Type(ty MlirType, b Builder) bool {
	return TypeEqual(ty, b.IntType(1))
}
