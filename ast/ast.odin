// Handles changing tokens into AST to be used for code generation
//  and also does the type checking during
package ast

import "core:fmt"
import "core:os"
import "core:strings"

import "../tokenizer"
import "../types"
import "../util"

ErrorMsg :: util.ErrorMsg

SYS_EXIT :: 60
SYS_WRITE :: 1

ASTState :: struct {
    vars: map[string]Variable,
}

AST :: union #no_nil {
    ^ASTPushLiteral,
    ^ASTUnaryOp,
    ^ASTBinOp,
    ^ASTSyscall0,
    ^ASTSyscall1,
    ^ASTSyscall2,
    ^ASTSyscall3,
    ^ASTDrop,
    ^ASTBlock,
    ^ASTVarRef,
}

// Full program here
//  TODO: Switch resolveTokens to return this
ASTProgram :: struct {
    main:^ASTBlock,
    macros:map[string]Macro
}

ASTBlock :: struct {
    nodes: [dynamic]AST,
    state: ASTState,
    // The types left after the block
    outputTypes:[dynamic]Type
}

// TODO: Switch to return ASTBlock
resolveTokens :: proc(tokens:[]Token) -> (out:^ASTBlock, err:util.ErrorMsg) {
    tw : TokWalk = { tokens, 0, {} }
    block := resolveBlock(&tw, true) or_return
    return block, nil
}

resolveBlock :: proc(tw:^TokWalk, isRoot:=false) -> (block:^ASTBlock, err:ErrorMsg) {
    block = new(ASTBlock)
    block.nodes = make([dynamic]AST)
    block.state = {
        make(map[string]Variable)
    }
    block.outputTypes = make([dynamic]Type)
    // Type stack
    ts := &block.outputTypes
    out := &block.nodes
    vars := &block.state.vars
    for curOk(tw) {
        exitBlk := resolveNextToken(tw, ts, vars, out) or_return
        if exitBlk {
            if isRoot {
                return block, util.locStr(tw.loc, "Found } in root")
            } else {
                return block, nil
            }
        }
    }
    if isRoot {
        return block, nil
    }
    return block, "Reached end of input without closing block"
}

resolveNextToken :: proc(tw:^TokWalk, ts:^[dynamic]Type, vars:^map[string]Variable, curAST:^[dynamic]AST) -> (exitBlock := false, err:ErrorMsg=nil){
    if !curOk(tw) do return {}, "Expected next token, but had nothing"
    cur := curr(tw)
    switch cur.type {
        case .Error: {
            return {}, util.locStr(cur.loc, 
                "Error Token found\n")
        }
        case .IntLit: {
            intLit := resolveIntLit(ts, cur) or_return
            append(curAST, intLit)
        }
        case .FloatLit: { 
            value := new(ASTPushLiteral)
            value ^= cur.value.(f64)
            pushType(ts, .Float)
            append(curAST, value)
        }
        case .StringLit: { 
            len, str := resolveStringLit(ts, cur) or_return
            append(curAST, len)
            append(curAST, str)
        }
        case .BoolLit: {
            value := new(ASTPushLiteral)
            value ^= cur.value.(bool)
            pushType(ts, .Bool)
            append(curAST, value)
        }
        case .Plus: {
            plus := resolvePlus(curAST, ts, cur) or_return
            append(curAST, plus)
        }
        case .Dash: { 
            dash := resolveDash(curAST, ts, cur) or_return
            append(curAST, dash)
        }
        case .Exit: {
            expectArgs(curAST^, ts, "exit", 
                {.Int}, cur.loc) or_return
            // Break even
            // popType()
            // pushType(.Int)

            value := new(ASTSyscall1)
            value.call = new(ASTPushLiteral)
            value.call.(^ASTPushLiteral) ^= SYS_EXIT
            value.arg1 = pop(curAST)
            append(curAST, value)
            // Consider dropping after exit calls cause value will never be used
            // append(&out, new(Drop))
        }
        case .Syscall0: {
            expectArgs(curAST^, ts, "syscall0", 
                {.Int}, cur.loc) or_return
            pushType(ts, .Int)
            value := new(ASTSyscall0)
            value.call = pop(curAST)
            append(curAST, value)
        }
        case .Syscall1: {
            expectArgs(curAST^, ts, "syscall1", 
                {.Int, .Any}, cur.loc) or_return
            pushType(ts, .Int)
            value := new(ASTSyscall1)
            value.call = pop(curAST)
            value.arg1 = pop(curAST)
            append(curAST, value)
        }
        case .Syscall2: {
            expectArgs(curAST^, ts, "syscall2", 
                {.Int, .Any, .Any}, cur.loc) or_return
            pushType(ts, .Int)
            value := new(ASTSyscall2)
            value.call = pop(curAST)
            value.arg1 = pop(curAST)
            value.arg2 = pop(curAST)
            append(curAST, value)
        }
        case .Syscall3: { 
            expectArgs(curAST^, ts, "syscall3", 
                {.Int, .Any, .Any, .Any}, cur.loc) or_return
            pushType(ts, .Int)
            value := new(ASTSyscall3)
            value.call = pop(curAST)
            value.arg1 = pop(curAST)
            value.arg2 = pop(curAST)
            value.arg3 = pop(curAST)
            append(curAST, value)
        }
        case .Drop: {
            expectArgs(curAST^, ts, "drop", {.Any}, cur.loc) or_return
            popType(ts)
            append(curAST, new(ASTDrop))
        }
        case .Macro: {
            return false, "TODO"
        }
        case .Puts: {
            // Should this instead become a proc?
            expectArgs(curAST^, ts, "puts", 
                {.Ptr, .Int}, cur.loc) or_return

            value := new(ASTSyscall3)
            value.call = new(ASTPushLiteral)
            value.call.(^ASTPushLiteral) ^= SYS_WRITE
            // stdout
            value.arg1 = new(ASTPushLiteral)
            value.arg1.(^ASTPushLiteral) ^= 1

            value.arg2 = pop(curAST)
            value.arg3 = pop(curAST)
            append(curAST, value)
        }
        case .Gt: { 
            return false, "> AST TODO"
        }
        case .If: { 
            return false, "< AST TODO"
        }
        case .Eq: {
            return false, "= AST TODO"
        }
        case .End: { 
            return false, "end AST TODO"
        }
        case .Let: { 
            resolveLet(cur.loc, tw, vars) or_return
        }
        case .Bang: { 
            return false, "! AST TODO"
        }
        case .Type: { 
            return false, "(type) AST TODO"
        }
        case .Colon: { 
            return false, ": AST TODO"
        }
        case .Ident: {
            // raw ident should give the value from variable
            varName := cur.value.(string)
            if varName not_in vars {
                return {}, util.locStr(cur.loc, 
                    "Unknown token of 's'", varName)
            }
            varRef := new(ASTVarRef)
            varRef.ident = varName
            pushType(ts, vars[varName].type)
            (&vars[varName]).used = true
            append(curAST, varRef)
        }
        case .OParen: {
            // Check for type casting
            if n, ok := peek(tw); ok && n.type == .Type {
                typeToken, _ := next(tw)
                typeValue := typeToken.value.(types.Type)
                expectNext(tw, .CParen)
                // Allow only casting from int to float and float to int for now

                // Ignore if casting to the same type
                if peekType(ts) == typeValue do return {}, nil
                if peekType(ts) == .Int && typeValue == .Float {
                    popType(ts)
                    pushType(ts, .Float)
                    unop := new(ASTUnaryOp)
                    unop.op = .CastIntToFloat
                    unop.value = pop(curAST)
                    append(curAST, unop)
                    next(tw)
                    return
                }
                if peekType(ts) == .Float && typeValue == .Int {
                    popType(ts)
                    pushType(ts, .Int)
                    unop := new(ASTUnaryOp)
                    unop.op = .CastFloatToInt
                    unop.value = pop(curAST)
                    append(curAST, unop)
                    next(tw)
                    return
                }
                return false, "Cannot currently cast to and from anything except int and float"
            }
            return false, "Invalid character after ("
        }
        case .CParen: { 
            return false, ") AST TODO"
        }
        case .OBrace: {
            next(tw)
            block := resolveBlock(tw, false) or_return
            append(curAST, block)
            // return false, "{ AST TODO\n"
        }
        case .CBrace: {
            next(tw)
            return true, nil
        }
    }
    next(tw)
    return false, nil
}


resolveIntLit :: proc(ts:^[dynamic]Type, intLit:Token) -> (^ASTPushLiteral, util.ErrorMsg) {
    if intLit.type != .IntLit do return nil, util.locStr(intLit.loc,
        "Invalid token type for an Int Lit")
    value := newIntLit(intLit.value.(int))
    pushType(ts, .Int)
    return value, nil
}

// Handle setting up "string lit" AST 
resolveStringLit :: proc(ts:^[dynamic]Type, strLit:Token) -> (^ASTPushLiteral, ^ASTPushLiteral, ErrorMsg) {
    // Length
    length := new(ASTPushLiteral)
    length ^= len(strLit.value.(string))
    pushType(ts, .Int)
    // append(out, length)  

    // Label
    value := new(ASTPushLiteral)
    value ^= strLit.value.(string)
    pushType(ts, .Ptr)
    // append(out, value) 
    return length, value, nil
}

// Handle setting up plus AST
resolvePlus :: proc(curAST:^[dynamic]AST, ts:^[dynamic]Type, plus:Token) -> (op:^ASTBinOp = nil, err:ErrorMsg) {
    // Requires 2 things on the stack
    expectArgs(curAST^, ts, "+", {}, plus.loc) or_return
    // Manual type check
    if len(ts) < 2 {
        return nil, fmt.tprintf("Op '+' requires 2 inputs but got %d\n", len(ts))
    }
    // TODO: Add float support
    if !hasTypes(ts, {.Int, .Int}) {
        return nil, "Invalid argument types for op '+'\n"
    }
    // Types must match, so can just drop one of type
    popType(ts)
    // Optimize out simple operations
    value := new(ASTBinOp)
    value.lhs = pop(curAST)
    value.rhs = pop(curAST)
    // TODO: Consider changing to PlusInt and PlusFloat 
    value.op = .Plus
    return value, nil
}

// Handle setting up subtraction AST
resolveDash :: proc(curAST:^[dynamic]AST, ts:^[dynamic]Type, dash:Token) -> (op:^ASTBinOp, err:ErrorMsg) {
    // Requires 2 things on the stack
    expectArgs(curAST^, ts, "-", {}, dash.loc) or_return
    // Manual type check after
    if len(ts) < 2 {
        return nil, "Op '-' requires 2 inputs"
    }
    // TODO: Add float support
    if !hasTypes(ts, {.Int, .Int}) {
        return nil, "Invalid argument types for op '-'\n"
    }
    // Types must match, so can just drop one of type
    popType(ts)
    // Optimize out simple operations
    value := new(ASTBinOp)
    value.lhs = pop(curAST)
    value.rhs = pop(curAST)
    // TODO: Consider MinusInt and MinusFloat ops
    value.op = .Minus
    // append(out, value)
    return value, nil
}

resolveLet :: proc(startLoc : util.Location, tw : ^TokWalk, vars: ^map[string]Variable) -> ErrorMsg {
    ident, ok := peek(tw)
    if !ok {
        // Reached end of input
        return util.locStr(startLoc, 
            "Keyword 'let' requires an identifier after it")
    }
    // Eat identifier
    expectNext(tw, .Ident) or_return
    varName := ident.value.(string)
    // Check if this variable exists already
    if varName in vars {
        return util.locStr(curr(tw).loc, 
            "Redeclaration of var '%s'", varName)
    }
    // Eat = after
    eq := expectNext(tw, .Eq) or_return
    nextT, ok2 := next(tw)
    if !ok2 {
        return util.locStr(eq.loc, 
            "Expected a value to set variable to after it")
    }
    // { values } syntax
    if nextT.type == .OBrace {
        return util.locStr(nextT.loc, 
            "Currently, {{ is not supported for var defs")
    }
    // let x = 1
    if nextT.type == .IntLit {
        pushLit := newIntLit(nextT.value.(int))
        vars[varName] = {
            varName,
            .Int,
            false,
            false,
            AST(pushLit),
        }                    
        return nil
    }
    // let x = 1.2
    if nextT.type == .FloatLit {

    }
    // let x = true
    if nextT.type == .BoolLit {

    }
    // let x = "abc"
    if nextT.type == .StringLit {
        nt := curr(tw)
        return util.locStr(nextT.loc, 
            "Currently, string literal vars are not supported for var defs")
    }
    // TODO: Allow setting to another variable
    nt, _ := peek(tw)
    return util.locStr(nt.loc, 
        "Expected a literal value here\n")
    // return out, "let TODO\n"
}

// Will eat types passed in
expectArgs :: proc(out : [dynamic]AST, ts:^[dynamic]Type, label:string, types:[]Type, loc:tokenizer.Location) -> util.ErrorMsg {
    if len(out) < len(types) {
        return util.locStr(loc, 
            "%s requries %d argument%s", 
            label, len(types), 
            (len(types))==1?"":"s"
        )
    }
    return expectTypes(ts, types, loc)
}

printASTHelper :: proc(ast: AST, sb:^strings.Builder, inList:=false, indent:=0) {
    // indent
    for i in 0..<indent do strings.write_byte(sb, ' ')
    switch ty in ast {
        case ^ASTPushLiteral: {
            switch lit in ty {
                case int: {
                    strings.write_int(sb, lit)
                }
                case bool: {
                    // bool is basically just an int, right?
                    strings.write_int(sb, int(lit))
                }
                case string: {
                    strings.write_byte(sb, '"')
                    strings.write_string(sb, lit)
                    strings.write_byte(sb, '"')
                }
                case f64: {
                    fmt.sbprintf(sb, "%.4f", lit)
                }
            }
            // Handle closing here because its different
            if inList do strings.write_byte(sb, ',')
            strings.write_byte(sb, '\n')
            return
        }
        case ^ASTBinOp: {
            // fmt.printf("2 %s {\n", ty.op)
            strings.write_string(sb, ASTBinOpsString[ty.op])
            strings.write_string(sb, " {\n")
            printASTHelper(ty.lhs, sb, true, indent + 1)
            printASTHelper(ty.rhs, sb, false, indent + 1)
            // Closing is done after this
        }
        case ^ASTUnaryOp: {
            strings.write_string(sb, ASTUnaryOpsString[ty.op])
            strings.write_string(sb, " {\n")           
            printASTHelper(ty.value, sb, false, indent + 1)
        }
        case ^ASTSyscall0: {
            strings.write_string(sb, "syscall {\n")
            printASTHelper(ty.call, sb, false, indent + 1)
        }
        case ^ASTSyscall1: {
            strings.write_string(sb, "syscall {\n")
            printASTHelper(ty.call, sb, true, indent + 1)
            printASTHelper(ty.arg1, sb, false, indent + 1)
        }
        case ^ASTSyscall2: {
            strings.write_string(sb, "syscall {\n")
            printASTHelper(ty.call, sb, true, indent + 1)
            printASTHelper(ty.arg1, sb, true, indent + 1)
            printASTHelper(ty.arg2, sb, false, indent + 1)
        }
        case ^ASTSyscall3: {
            strings.write_string(sb, "syscall {\n")
            printASTHelper(ty.call, sb, true, indent + 1)
            printASTHelper(ty.arg1, sb, true, indent + 1)
            printASTHelper(ty.arg2, sb, true, indent + 1)
            printASTHelper(ty.arg3, sb, false, indent + 1)
        }
        case ^ASTDrop: {
            strings.write_string(sb, "Drop\n")
        }
        case ^ASTVarRef: {
            strings.write_string(sb, "Ref \"")
            strings.write_string(sb, ty.ident)
            strings.write_string(sb, "\"\n")
            return
        }
        case ^ASTBlock: {
            strings.write_string(sb, "Block {\n")
            for as in ty.nodes {
                printASTHelper(as, sb, true, indent + 1)
            }
        }
    }
    for i in 0..<indent do strings.write_byte(sb, ' ')
    strings.write_string(sb, "}\n")
}

printASTVars :: proc(vars:map[string]Variable) {
    sb : strings.Builder
    for k, v in vars {
        fmt.printf("var %s : %s = {{\n", v.label, v.type)
        printASTHelper(v.value, &sb, false, 1)
        fmt.printf("%s}\n", strings.to_string(sb))
    }
}

printAST :: proc(ast:AST) {
    sb: strings.Builder
    printASTHelper(ast, &sb)
    fmt.printf("%s\n", strings.to_string(sb))
}