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
	"unsafe"

	"github.com/microsoft/typescript-go/internal/ast"
)

// isNullBlock checks if an MlirBlock wrapper holds a null pointer.
func isNullBlock(b MlirBlock) bool {
	return unsafe.Pointer(b.ptr.ptr) == nil
}

// isNullValue checks if an MlirValue wrapper holds a null pointer.
func isNullValue(v MlirValue) bool {
	return unsafe.Pointer(v.ptr.ptr) == nil
}

// isNullType checks if an MlirType wrapper holds a null pointer.
func isNullType(t MlirType) bool {
	return unsafe.Pointer(t.ptr.ptr) == nil
}

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
	currentFunc    MlirOperation
	currentBlock   MlirBlock
	hasTerminator  bool
	currentRetType MlirType // return type of current function (for try propagation)

	// Loop stack for break/continue
	loopStack []LoopContext

	// Struct (interface) type registry
	structNames      []string
	structTypes      []MlirType
	structFieldNames [][]string
	structFieldTypes [][]MlirType

	// Type alias registry (e.g. type Result = number | Error)
	typeAliasNames []string
	typeAliasTypes []MlirType

	// Enum type registry
	enumNames        []string
	enumTypes        []MlirType
	enumMemberNames  [][]string
	enumMemberValues [][]int64

	// Try/catch state: pending catch block for exception unwinding
	pendingCatchBlock MlirBlock
	pendingCatchVar   string
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
	case ast.KindTypeAliasDeclaration:
		g.mapTypeAliasDecl(node)
	case ast.KindEnumDeclaration:
		g.mapEnumDecl(node)
	}
}

// mapTypeAliasDecl handles type alias declarations.
// Recognizes patterns like: type Result = number | Error → !cir.error_union<i32>
func (g *Gen) mapTypeAliasDecl(node *ast.Node) {
	ta := node.AsTypeAliasDeclaration()
	name := ta.Name().AsIdentifier().Text
	ty := g.resolveType(ta.Type)
	g.typeAliasNames = append(g.typeAliasNames, name)
	g.typeAliasTypes = append(g.typeAliasTypes, ty)
}

func (g *Gen) mapEnumDecl(node *ast.Node) {
	ed := node.AsEnumDeclaration()
	name := ed.Name().AsIdentifier().Text

	var memberNames []string
	var memberValues []int64
	nextVal := int64(0)

	if ed.Members != nil {
		for _, member := range ed.Members.Nodes {
			if member.Kind == ast.KindEnumMember {
				em := member.AsEnumMember()
				mname := em.Name().AsIdentifier().Text
				memberNames = append(memberNames, mname)
				// Use explicit initializer if present, otherwise auto-assign
				if em.Initializer != nil && em.Initializer.Kind == ast.KindNumericLiteral {
					lit := em.Initializer.AsNumericLiteral()
					v, _ := strconv.ParseInt(lit.Text, 10, 64)
					memberValues = append(memberValues, v)
					nextVal = v + 1
				} else {
					memberValues = append(memberValues, nextVal)
					nextVal++
				}
			}
		}
	}

	tagType := g.b.IntType(32)
	enumType := CirEnumTypeGet(g.ctx, name, tagType, memberNames, memberValues)

	g.enumNames = append(g.enumNames, name)
	g.enumTypes = append(g.enumTypes, enumType)
	g.enumMemberNames = append(g.enumMemberNames, memberNames)
	g.enumMemberValues = append(g.enumMemberValues, memberValues)
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
	if len(resultTypes) > 0 {
		g.currentRetType = resultTypes[0]
	} else {
		g.currentRetType = MlirType{}
	}
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
			CirBuildBr(g.currentBlock, g.b.loc, g.loopStack[len(g.loopStack)-1].exit, nil)
			g.hasTerminator = true
		}
	case ast.KindContinueStatement:
		if len(g.loopStack) > 0 {
			CirBuildBr(g.currentBlock, g.b.loc, g.loopStack[len(g.loopStack)-1].header, nil)
			g.hasTerminator = true
		}
	case ast.KindBlock:
		g.mapBlock(g.currentBlock, node)
	case ast.KindSwitchStatement:
		g.mapSwitchStmt(node)
	case ast.KindTryStatement:
		g.mapTryStmt(node)
	case ast.KindThrowStatement:
		g.mapThrowStmt(node)
	}
}

func (g *Gen) mapReturn(node *ast.Node) {
	rs := node.AsReturnStatement()
	if rs.Expression != nil {
		val := g.mapExpr(g.currentBlock, rs.Expression, g.currentRetType)
		// If function returns error union and value is the payload type,
		// wrap it with wrap_result
		if CirTypeIsErrorUnion(g.currentRetType) {
			valType := ValueGetType(val)
			if !CirTypeIsErrorUnion(valType) {
				val = CirBuildWrapResult(g.currentBlock, g.b.loc, g.currentRetType, val)
			}
		}
		// Auto-cast integer width mismatches (e.g., i64 slice_len → i32 number)
		valType := ValueGetType(val)
		retType := g.currentRetType
		valWidth := MlirIntegerTypeGetWidth(valType)
		retWidth := MlirIntegerTypeGetWidth(retType)
		if valWidth > 0 && retWidth > 0 && valWidth != retWidth {
			if valWidth > retWidth {
				val = CirBuildTruncI(g.currentBlock, g.b.loc, retType, val)
			} else {
				val = CirBuildExtSI(g.currentBlock, g.b.loc, retType, val)
			}
		}
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
		varType = CirArrayTypeGet(g.ctx, int64(nElems), g.b.IntType(32))
	}

	// Allocate on stack
	addr := CirBuildAlloca(g.currentBlock, g.b.loc, varType)

	// Store initializer if present
	if vd.Initializer != nil {
		val := g.mapExpr(g.currentBlock, vd.Initializer, varType)
		CirBuildStore(g.currentBlock, g.b.loc, val, addr)
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
			CirBuildStore(g.currentBlock, g.b.loc, val, g.localAddrs[i])
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
			current := CirBuildLoad(g.currentBlock, g.b.loc, g.localTypes[i], g.localAddrs[i])
			rhs := g.mapExpr(g.currentBlock, be.Right, g.localTypes[i])
			result := emitBinOp(g.currentBlock, g.b.loc, be.OperatorToken.Kind, g.localTypes[i], current, rhs)
			CirBuildStore(g.currentBlock, g.b.loc, result, g.localAddrs[i])
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

	CirBuildCondBr(g.currentBlock, g.b.loc, cond, thenBlock, elseBlock)

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
		CirBuildBr(g.currentBlock, g.b.loc, mergeBlock, nil)
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
		CirBuildBr(g.currentBlock, g.b.loc, mergeBlock, nil)
	}

	g.currentBlock = mergeBlock
	// If both branches return, merge is unreachable — add trap terminator
	if thenTerminated && elseTerminated {
		CirBuildTrap(mergeBlock, g.b.loc)
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

	CirBuildBr(g.currentBlock, g.b.loc, headerBlock, nil)

	// Header: evaluate condition
	g.currentBlock = headerBlock
	cond := g.mapExpr(headerBlock, ws.Expression, g.b.IntType(1))
	CirBuildCondBr(headerBlock, g.b.loc, cond, bodyBlock, exitBlock)

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
		CirBuildBr(g.currentBlock, g.b.loc, headerBlock, nil)
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

	CirBuildBr(g.currentBlock, g.b.loc, headerBlock, nil)

	// Header: condition
	g.currentBlock = headerBlock
	if fs.Condition != nil {
		cond := g.mapExpr(headerBlock, fs.Condition, g.b.IntType(1))
		CirBuildCondBr(headerBlock, g.b.loc, cond, bodyBlock, exitBlock)
	} else {
		CirBuildBr(headerBlock, g.b.loc, bodyBlock, nil)
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
		CirBuildBr(g.currentBlock, g.b.loc, headerBlock, nil)
	}

	g.currentBlock = exitBlock
	g.hasTerminator = false
}

// ============================================================
// Switch statement
// ============================================================

// mapSwitchStmt handles TypeScript switch(expr) { case X: ...; default: ... }
// Emits cir.enum_value to extract integer tag from enum discriminant,
// then cir.switch for multi-way branch to case blocks.
// Reference: Zig AstGen switchExpr — condition + case dispatch
func (g *Gen) mapSwitchStmt(node *ast.Node) {
	ss := node.AsSwitchStatement()
	caseBlock := ss.CaseBlock.AsCaseBlock()

	// Evaluate discriminant expression
	condVal := g.mapExpr(g.currentBlock, ss.Expression, g.b.IntType(32))
	condType := ValueGetType(condVal)

	// If condition is an enum, extract the integer tag
	switchVal := condVal
	if CirTypeIsEnum(condType) {
		tagType := CirEnumTypeGetTagType(condType)
		switchVal = CirBuildEnumValue(g.currentBlock, g.b.loc, tagType, condVal)
	}

	// Create merge block (all cases branch here after their body)
	mergeBlock := g.b.AddBlock(g.currentFunc)

	// First pass: collect case values, create case blocks, find default
	var caseValues []int64
	var caseDests []MlirBlock
	var defaultDest MlirBlock
	hasDefault := false

	type caseInfo struct {
		block  MlirBlock
		clause *ast.CaseOrDefaultClause
	}
	var caseInfos []caseInfo

	if caseBlock.Clauses != nil {
		for _, clause := range caseBlock.Clauses.Nodes {
			armBlock := g.b.AddBlock(g.currentFunc)
			ci := caseInfo{block: armBlock}

			if clause.Kind == ast.KindCaseClause {
				cc := clause.AsCaseOrDefaultClause()
				ci.clause = cc
				// Resolve the case value
				var caseVal int64
				if cc.Expression != nil {
					// Handle Color.Red style: PropertyAccessExpression
					if cc.Expression.Kind == ast.KindPropertyAccessExpression {
						pa := cc.Expression.AsPropertyAccessExpression()
						memberName := pa.Name().AsIdentifier().Text
						// Look up enum member value
						if pa.Expression.Kind == ast.KindIdentifier {
							enumName := pa.Expression.AsIdentifier().Text
							for i, en := range g.enumNames {
								if en == enumName {
									for j, mn := range g.enumMemberNames[i] {
										if mn == memberName {
											caseVal = g.enumMemberValues[i][j]
											break
										}
									}
									break
								}
							}
						}
					} else if cc.Expression.Kind == ast.KindNumericLiteral {
						lit := cc.Expression.AsNumericLiteral()
						caseVal, _ = strconv.ParseInt(lit.Text, 10, 64)
					}
				}
				caseValues = append(caseValues, caseVal)
				caseDests = append(caseDests, armBlock)
			} else if clause.Kind == ast.KindDefaultClause {
				cc := clause.AsCaseOrDefaultClause()
				ci.clause = cc
				defaultDest = armBlock
				hasDefault = true
			}
			caseInfos = append(caseInfos, ci)
		}
	}

	// If no default clause, create a default block that branches to merge
	if !hasDefault {
		defaultDest = g.b.AddBlock(g.currentFunc)
		CirBuildBr(defaultDest, g.b.loc, mergeBlock, nil)
	}

	// Emit cir.switch in the current block
	CirBuildSwitch(g.currentBlock, g.b.loc, switchVal, caseValues, caseDests, defaultDest)

	// Second pass: emit body for each case
	allTerminated := true
	for _, ci := range caseInfos {
		g.currentBlock = ci.block
		g.hasTerminator = false
		if ci.clause != nil && ci.clause.Statements != nil {
			for _, stmt := range ci.clause.Statements.Nodes {
				if g.hasTerminator {
					break
				}
				g.mapStmt(stmt)
			}
		}
		if !g.hasTerminator {
			CirBuildBr(g.currentBlock, g.b.loc, mergeBlock, nil)
		}
		if !g.hasTerminator {
			allTerminated = false
		}
	}
	_ = allTerminated

	g.currentBlock = mergeBlock
	g.hasTerminator = false
}

// ============================================================
// Error union: try/catch/throw
// ============================================================

// mapThrowStmt handles: throw expr
// Emits cir.throw — exception-based error handling.
// TypeScript uses throw/try/catch natively, so we emit exception ops directly.
func (g *Gen) mapThrowStmt(node *ast.Node) {
	ts := node.AsThrowStatement()
	// Evaluate the throw expression as an i32 exception value
	throwVal := g.mapExpr(g.currentBlock, ts.Expression, g.b.IntType(32))
	CirBuildThrow(g.currentBlock, g.b.loc, throwVal)
	g.hasTerminator = true
}

// mapTryStmt handles TypeScript try/catch using exception-based error handling:
//
//	try { body } catch (e) { handler }
//
// Calls inside the try body are emitted as cir.invoke (with normal/unwind
// successors). The catch block begins with cir.landingpad to receive the
// exception value.
//
// Pattern:
//   try block → calls become cir.invoke with unwind to catch block
//   catch (e) { ... } → cir.landingpad, e is bound to caught value (i32)
func (g *Gen) mapTryStmt(node *ast.Node) {
	ts := node.AsTryStatement()

	catchBlock := g.b.AddBlock(g.currentFunc)
	mergeBlock := g.b.AddBlock(g.currentFunc)

	// Save scope state
	savedCatchBlock := g.pendingCatchBlock
	savedCatchVar := g.pendingCatchVar
	g.pendingCatchBlock = catchBlock

	// Emit try body — calls will use cir.invoke with unwind to catchBlock
	if ts.TryBlock != nil {
		g.mapBlock(g.currentBlock, ts.TryBlock)
	}
	tryTerminated := g.hasTerminator
	if !tryTerminated {
		CirBuildBr(g.currentBlock, g.b.loc, mergeBlock, nil)
	}

	// Restore catch context
	g.pendingCatchBlock = savedCatchBlock
	g.pendingCatchVar = savedCatchVar

	// Emit catch clause with landingpad
	g.currentBlock = catchBlock
	g.hasTerminator = false

	// Emit cir.landingpad at the start of catch block to receive exception value
	exnType := g.b.IntType(32)
	exnVal := CirBuildLandingPad(catchBlock, g.b.loc, exnType)

	if ts.CatchClause != nil {
		cc := ts.CatchClause.AsCatchClause()
		// Bind the catch variable to the landingpad result
		if cc.VariableDeclaration != nil {
			vd := cc.VariableDeclaration.AsVariableDeclaration()
			varName := vd.Name().AsIdentifier().Text
			addr := CirBuildAlloca(g.currentBlock, g.b.loc, exnType)
			CirBuildStore(g.currentBlock, g.b.loc, exnVal, addr)
			g.localNames = append(g.localNames, varName)
			g.localAddrs = append(g.localAddrs, addr)
			g.localTypes = append(g.localTypes, exnType)
		}
		if cc.Block != nil {
			g.mapBlock(g.currentBlock, cc.Block)
		}
	}
	catchTerminated := g.hasTerminator
	if !catchTerminated {
		CirBuildBr(g.currentBlock, g.b.loc, mergeBlock, nil)
	}

	g.currentBlock = mergeBlock
	if tryTerminated && catchTerminated {
		CirBuildTrap(mergeBlock, g.b.loc)
		g.hasTerminator = true
	} else {
		g.hasTerminator = false
	}
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
		return CirBuildConstantBool(block, g.b.loc, true)
	case ast.KindFalseKeyword:
		return CirBuildConstantBool(block, g.b.loc, false)
	case ast.KindNullKeyword:
		// null → cir.none (need optional type from context)
		if CirTypeIsOptional(resultType) {
			return CirBuildNone(block, g.b.loc, resultType)
		}
		// null in error union context → wrap_error with code 0
		if CirTypeIsErrorUnion(resultType) {
			errCode := CirBuildConstantInt(block, g.b.loc, g.b.IntType(16), 0)
			return CirBuildWrapError(block, g.b.loc, resultType, errCode)
		}
		return CirBuildConstantInt(block, g.b.loc, resultType, 0)
	case ast.KindStringLiteral:
		lit := node.AsStringLiteral()
		// Strip surrounding quotes from text
		text := lit.Text
		return CirBuildStringConstant(block, g.b.loc, text)
	default:
		return CirBuildConstantInt(block, g.b.loc, resultType, 0)
	}
}

func (g *Gen) mapNumericLiteral(block MlirBlock, node *ast.Node, resultType MlirType) MlirValue {
	lit := node.AsNumericLiteral()
	val, _ := strconv.ParseInt(lit.Text, 10, 64)
	// If result type is error union, the literal is the payload type
	if CirTypeIsErrorUnion(resultType) {
		payloadType := CirErrorUnionTypeGetPayload(resultType)
		return CirBuildConstantInt(block, g.b.loc, payloadType, val)
	}
	return CirBuildConstantInt(block, g.b.loc, resultType, val)
}

func (g *Gen) mapIdentifier(block MlirBlock, node *ast.Node) MlirValue {
	name := node.AsIdentifier().Text
	for i := len(g.localNames) - 1; i >= 0; i-- {
		if g.localNames[i] == name {
			return CirBuildLoad(block, g.b.loc, g.localTypes[i], g.localAddrs[i])
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
		return CirBuildAdd(block, g.b.loc, opResultType, lhs, rhs)
	case ast.KindMinusToken:
		return CirBuildSub(block, g.b.loc, opResultType, lhs, rhs)
	case ast.KindAsteriskToken:
		return CirBuildMul(block, g.b.loc, opResultType, lhs, rhs)
	case ast.KindSlashToken:
		return CirBuildDiv(block, g.b.loc, opResultType, lhs, rhs)
	case ast.KindPercentToken:
		return CirBuildRem(block, g.b.loc, opResultType, lhs, rhs)
	// Bitwise
	case ast.KindAmpersandToken:
		return CirBuildBitAnd(block, g.b.loc, opResultType, lhs, rhs)
	case ast.KindBarToken:
		return CirBuildBitOr(block, g.b.loc, opResultType, lhs, rhs)
	case ast.KindCaretToken:
		return CirBuildBitXor(block, g.b.loc, opResultType, lhs, rhs)
	case ast.KindLessThanLessThanToken:
		return CirBuildShl(block, g.b.loc, opResultType, lhs, rhs)
	case ast.KindGreaterThanGreaterThanToken:
		return CirBuildShr(block, g.b.loc, opResultType, lhs, rhs)
	// Comparisons
	case ast.KindEqualsEqualsToken, ast.KindEqualsEqualsEqualsToken:
		return CirBuildCmp(block, g.b.loc, 0, lhs, rhs)
	case ast.KindExclamationEqualsToken, ast.KindExclamationEqualsEqualsToken:
		return CirBuildCmp(block, g.b.loc, 1, lhs, rhs)
	case ast.KindLessThanToken:
		return CirBuildCmp(block, g.b.loc, 2, lhs, rhs)
	case ast.KindLessThanEqualsToken:
		return CirBuildCmp(block, g.b.loc, 3, lhs, rhs)
	case ast.KindGreaterThanToken:
		return CirBuildCmp(block, g.b.loc, 4, lhs, rhs)
	case ast.KindGreaterThanEqualsToken:
		return CirBuildCmp(block, g.b.loc, 5, lhs, rhs)
	}
	return MlirValue{}
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

	// If inside a try block, emit cir.invoke with normal/unwind successors
	// instead of a plain func.call.
	if !isNullBlock(g.pendingCatchBlock) {
		normalBlock := g.b.AddBlock(g.currentFunc)
		callResult := CirBuildInvoke(block, g.b.loc, calleeName, args, resultType, normalBlock, g.pendingCatchBlock)
		// Continue codegen in the normal successor block
		g.currentBlock = normalBlock
		_ = callResult
		return callResult
	}

	callResult := g.b.Emit(block, "func.call", []MlirType{resultType}, args,
		[]MlirNamedAttr{g.b.NamedAttr("callee", g.b.FlatSymbolRefAttr(calleeName))})

	return callResult
}

func (g *Gen) mapPrefixUnary(block MlirBlock, node *ast.Node, resultType MlirType) MlirValue {
	pu := node.AsPrefixUnaryExpression()
	operand := g.mapExpr(block, pu.Operand, resultType)
	switch pu.Operator {
	case ast.KindMinusToken:
		return CirBuildNeg(block, g.b.loc, resultType, operand)
	case ast.KindTildeToken:
		return CirBuildBitNot(block, g.b.loc, resultType, operand)
	case ast.KindExclamationToken:
		one := CirBuildConstantInt(block, g.b.loc, resultType, 1)
		return CirBuildBitXor(block, g.b.loc, resultType, operand, one)
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
	// Build array type via C API
	arrayType := CirArrayTypeGet(g.ctx, int64(len(elemVals)), g.b.IntType(32))
	return CirBuildArrayInit(block, g.b.loc, arrayType, elemVals)
}

// Element access: arr[i] → cir.elem_val
func (g *Gen) mapElementAccess(block MlirBlock, node *ast.Node, resultType MlirType) MlirValue {
	ea := node.AsElementAccessExpression()
	arr := g.mapExpr(block, ea.Expression, resultType)
	arrType := ValueGetType(arr)
	// Slice indexing: s[i] → cir.slice_elem
	if CirTypeIsSlice(arrType) {
		idx := g.mapExpr(block, ea.ArgumentExpression, g.b.IntType(64))
		return CirBuildSliceElem(block, g.b.loc, resultType, arr, idx)
	}
	// Array indexing: arr[i] → cir.elem_val (constant index)
	var idxVal int64
	if ea.ArgumentExpression != nil && ea.ArgumentExpression.Kind == ast.KindNumericLiteral {
		lit := ea.ArgumentExpression.AsNumericLiteral()
		idxVal, _ = strconv.ParseInt(lit.Text, 10, 64)
	}
	return CirBuildElemVal(block, g.b.loc, resultType, arr, idxVal)
}

// Property access: p.x → cir.field_val, Color.Red → cir.enum_constant
func (g *Gen) mapPropertyAccess(block MlirBlock, node *ast.Node, resultType MlirType) MlirValue {
	pa := node.AsPropertyAccessExpression()
	fieldName := pa.Name().AsIdentifier().Text

	// Check if this is an enum member access: Color.Red
	if pa.Expression.Kind == ast.KindIdentifier {
		exprName := pa.Expression.AsIdentifier().Text
		for i, en := range g.enumNames {
			if en == exprName {
				// Verify member name exists in this enum
				for _, mn := range g.enumMemberNames[i] {
					if mn == fieldName {
						return CirBuildEnumConstant(block, g.b.loc, g.enumTypes[i], fieldName)
					}
				}
			}
		}
	}

	// Emit object expression
	obj := g.mapExpr(block, pa.Expression, resultType)
	objType := ValueGetType(obj)

	// Slice field access: s.length → slice_len
	if CirTypeIsSlice(objType) {
		if fieldName == "length" || fieldName == "len" {
			return CirBuildSliceLen(block, g.b.loc, obj)
		}
		return MlirValue{}
	}

	// Find struct index and field index
	for i, st := range g.structTypes {
		if TypeEqual(st, objType) {
			for j, fn := range g.structFieldNames[i] {
				if fn == fieldName {
					return CirBuildFieldVal(block, g.b.loc, g.structFieldTypes[i][j], obj, int64(j))
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
		return CirBuildConstantInt(block, g.b.loc, g.b.IntType(32), 0)
	}

	fieldNames := g.structFieldNames[structIdx]
	fieldTypes := g.structFieldTypes[structIdx]
	nFields := len(fieldNames)

	// Initialize all field values to zero
	fieldVals := make([]MlirValue, nFields)
	for i := 0; i < nFields; i++ {
		fieldVals[i] = CirBuildConstantInt(block, g.b.loc, fieldTypes[i], 0)
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

	return CirBuildStructInit(block, g.b.loc, resultType, fieldVals)
}

// cond ? thenVal : elseVal → cir.select
func (g *Gen) mapConditionalExpr(block MlirBlock, node *ast.Node, resultType MlirType) MlirValue {
	ce := node.AsConditionalExpression()
	cond := g.mapExpr(block, ce.Condition, g.b.IntType(1))
	thenVal := g.mapExpr(block, ce.WhenTrue, resultType)
	elseVal := g.mapExpr(block, ce.WhenFalse, resultType)
	return CirBuildSelect(block, g.b.loc, resultType, cond, thenVal, elseVal)
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
	case ast.KindStringKeyword:
		return g.b.ParseType("!cir.slice<i8>")
	case ast.KindTypeReference:
		tr := node.AsTypeReference()
		if tr.TypeName != nil && tr.TypeName.Kind == ast.KindIdentifier {
			name := tr.TypeName.AsIdentifier().Text
			// Check type aliases first (e.g. Result → !cir.error_union<i32>)
			for i, an := range g.typeAliasNames {
				if an == name {
					return g.typeAliasTypes[i]
				}
			}
			// Check struct types
			for i, sn := range g.structNames {
				if sn == name {
					return g.structTypes[i]
				}
			}
			// Check enum types
			for i, en := range g.enumNames {
				if en == name {
					return g.enumTypes[i]
				}
			}
			// "Error" by itself → i16 error code type
			if name == "Error" {
				return g.b.IntType(16)
			}
		}
	case ast.KindUnionType:
		return g.resolveUnionType(node)
	}
	return g.b.IntType(32)
}

// resolveUnionType handles TypeScript union types like `number | Error`.
// If one arm is "Error", produces !cir.error_union<T> where T is the other arm.
// Otherwise falls back to the first type in the union.
func (g *Gen) resolveUnionType(node *ast.Node) MlirType {
	ut := node.AsUnionTypeNode()
	if ut.Types == nil || len(ut.Types.Nodes) == 0 {
		return g.b.IntType(32)
	}

	// Scan for "Error" type in the union arms
	var payloadType MlirType
	hasError := false
	for _, tn := range ut.Types.Nodes {
		if tn.Kind == ast.KindTypeReference {
			tr := tn.AsTypeReference()
			if tr.TypeName != nil && tr.TypeName.Kind == ast.KindIdentifier {
				name := tr.TypeName.AsIdentifier().Text
				if name == "Error" {
					hasError = true
					continue
				}
			}
		}
		// This arm is the payload type
		payloadType = g.resolveType(tn)
	}

	if hasError && !isNullType(payloadType) {
		return CirErrorUnionTypeGet(g.ctx, payloadType)
	}

	// Not an error union — fall back to first type
	return g.resolveType(ut.Types.Nodes[0])
}

func (g *Gen) resolveTypeName(node *ast.Node) string {
	switch node.Kind {
	case ast.KindNumberKeyword:
		return "i32"
	case ast.KindBooleanKeyword:
		return "i1"
	case ast.KindVoidKeyword:
		return "i0"
	case ast.KindStringKeyword:
		return "!cir.slice<i8>"
	case ast.KindTypeReference:
		tr := node.AsTypeReference()
		if tr.TypeName != nil && tr.TypeName.Kind == ast.KindIdentifier {
			name := tr.TypeName.AsIdentifier().Text
			// Check enum types — return the enum type string
			for _, en := range g.enumNames {
				if en == name {
					return "!cir.enum<\"" + name + "\">"
				}
			}
			// Check struct types
			for _, sn := range g.structNames {
				if sn == name {
					return "!cir.struct<\"" + name + "\">"
				}
			}
		}
	case ast.KindUnionType:
		// Check if it's T | Error → !cir.error_union<T>
		ut := node.AsUnionTypeNode()
		if ut.Types != nil {
			hasError := false
			payloadName := "i32"
			for _, tn := range ut.Types.Nodes {
				if tn.Kind == ast.KindTypeReference {
					tr := tn.AsTypeReference()
					if tr.TypeName != nil && tr.TypeName.Kind == ast.KindIdentifier {
						if tr.TypeName.AsIdentifier().Text == "Error" {
							hasError = true
							continue
						}
					}
				}
				payloadName = g.resolveTypeName(tn)
			}
			if hasError {
				return "!cir.error_union<" + payloadName + ">"
			}
		}
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

// emitBinOp emits a CIR binary op for the given compound-assignment token kind.
func emitBinOp(block MlirBlock, loc MlirLocation, kind ast.Kind, ty MlirType, lhs MlirValue, rhs MlirValue) MlirValue {
	switch kind {
	case ast.KindPlusEqualsToken:
		return CirBuildAdd(block, loc, ty, lhs, rhs)
	case ast.KindMinusEqualsToken:
		return CirBuildSub(block, loc, ty, lhs, rhs)
	case ast.KindAsteriskEqualsToken:
		return CirBuildMul(block, loc, ty, lhs, rhs)
	case ast.KindSlashEqualsToken:
		return CirBuildDiv(block, loc, ty, lhs, rhs)
	case ast.KindPercentEqualsToken:
		return CirBuildRem(block, loc, ty, lhs, rhs)
	}
	return CirBuildAdd(block, loc, ty, lhs, rhs)
}

func isI1Type(ty MlirType, b Builder) bool {
	return TypeEqual(ty, b.IntType(1))
}
