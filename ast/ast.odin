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
    ^ASTVarDef,
}

// Full program here
//  TODO: Switch resolveTokens to return this
ASTProgram :: struct {
    main:^ASTBlock,
    procs:map[string]^Procedure,
    macros:map[string]^Macro,
}

ASTBlock :: struct {
    nodes: [dynamic]AST,
    state: ASTState,
    // The types left after the block
    outputTypes:[dynamic]Type
}

// TODO: Switch to return ASTProgram
resolveTokens :: proc(tokens:[]Token) -> (out:^ASTProgram, err:util.ErrorMsg) {
    tw : TokWalk = { tokens, 0, {} }
    program := resolveProgram(&tw) or_return
    return program, nil
}

// Parses the entire program
resolveProgram :: proc(tw:^TokWalk) -> (program:^ASTProgram, err:ErrorMsg) {
    program = new(ASTProgram)
    ok : bool
    for cur := curr(tw); curOk(tw); cur,_ = next(tw) {
        if cur.type == .Macro {
            macro := new(Macro)
            macro.inputs  = make([dynamic]Type)
            macro.outputs = make([dynamic]Type)
            
            // Eat 'macro'
            cur, ok = next(tw)
            if !ok { return program, "Expected Identifier\n" }
            macroName := cur.value.(string)
            macro.defLoc = cur.loc
            if macroName in program.macros {
                return program, util.locStr(cur.loc, 
                    "Redeclaration of macro")
            }
            if macroName in program.procs {
                return program, util.locStr(cur.loc, 
                    "Redeclaration of proc")
            }
            if macroName == "main" {
                return program, util.locStr(macro.defLoc, 
                    "Cannot name a macro 'main'. Reserved for the entry point")
            }
            // :
            _, ok  = tryNext(tw, .Colon)
            if ok do resolveTypes(tw, &macro.inputs)
            // >
            _, ok = tryNext(tw, .Gt)
            if ok do resolveTypes(tw, &macro.outputs)
            // {
            cur, ok := next(tw)
            if cur.type != .OBrace do return program, util.locStr(cur.loc, 
                "Expected an '{{' to start ")
            // Eat {
            next(tw)
            macro.body = resolveBlock(tw, program, {}) or_return
            /*
            if len(macro.body.outputTypes) != len(macro.outputs) {
                return program, util.locStr(macro.defLoc, 
                    "Got the incorrect amount of return value than expected for macro %s",
                    macroName)
            }*/
            program.macros[macroName] = macro
        } else if cur.type == .Proc {
            procc := new(Procedure)
            procc.inputs  = make([dynamic]Type)
            procc.outputs = make([dynamic]Type)
            
            // Eat 'macro'
            cur, ok = next(tw)
            if !ok { return program, "Expected Identifier\n" }
            procName := cur.value.(string)
            procc.defLoc = cur.loc
            if procName in program.macros {
                return program, util.locStr(cur.loc, 
                    "Redeclaration of macro")
            }
            if procName in program.procs {
                return program, util.locStr(cur.loc, 
                    "Redeclaration of proc")
            }
            // :
            _, ok  = tryNext(tw, .Colon)
            if ok do resolveTypes(tw, &procc.inputs)
            // >
            _, ok = tryNext(tw, .Gt)
            if ok do resolveTypes(tw, &procc.outputs)
            // {
            cur, ok := next(tw)
            if cur.type != .OBrace do return program, util.locStr(cur.loc, 
                "Expected an '{{' to start ")
            // Eat {
            next(tw)
            procc.body = resolveBlock(tw, program, {}) or_return
            program.procs[procName] = procc
        } else {
            return program, util.locStr(cur.loc, 
                "Global scope can only include macro and proc statements")
        }
    }
    return program, nil
}

// Reads all the next type tokens and puts them into the given buffer
resolveTypes :: proc(tw:^TokWalk, out :^[dynamic]Type) {
    for type, hasType := tryNext(tw, .Type); hasType; type, hasType = tryNext(tw, .Type) {
        append(out, type.value.(types.Type))
    }
}

resolveBlock :: proc(tw:^TokWalk, program:^ASTProgram, inVars:map[string]Variable) -> (block:^ASTBlock, err:ErrorMsg) {
    block = new(ASTBlock)
    block.nodes = make([dynamic]AST)
    block.state = {
        make(map[string]Variable)
    }
    for k, &v in inVars {
        block.state.vars[k] = v
    }
    block.outputTypes = make([dynamic]Type)
    // Type stack
    ts := &block.outputTypes
    out := &block.nodes
    vars := &block.state.vars
    for curOk(tw) {
        if resolveNextToken(tw, ts, program, vars, out) or_return  {
            return block, nil
        }
    }
    return block, "Reached end of input without closing block\n"
}

resolveNextToken :: proc(tw:^TokWalk, ts:^[dynamic]Type, program:^ASTProgram, vars:^map[string]Variable, curAST:^[dynamic]AST) -> (exitBlock := false, err:ErrorMsg=nil){
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
            // macro := resolveMacro(tw) or_return
            
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
            letDef := resolveLet(cur.loc, tw, vars, program) or_return
            append(curAST, letDef)
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
            if varName in vars {
                // Variable
                varRef := new(ASTVarRef)
                varRef.ident = varName
                pushType(ts, vars[varName].type)
                (&vars[varName]).used = true
                append(curAST, varRef)
                return false, nil
            } else if varName in program.macros {
                // Macro
                mac : ^Macro = program.macros[varName]
                // Check input types
                expectTypes(ts, mac.inputs[:], cur.loc) or_return
                // Replace with body
                append(curAST, mac.body)
                // Place output types
                for out in mac.outputs {
                    append(ts, out)
                }
                next(tw)
                return false, nil
            } else if varName in program.procs {
                // Procedure
            }
            return false, util.locStr(cur.loc, 
                "Unknown token of '%s'", varName)
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
            block := resolveBlock(tw, program, vars^) or_return
            // Make sure the block is not empty
            if len(block.nodes) > 0 {
                append(curAST, block)
            }
        }
        case .CBrace: {
            return true, nil
        }
        case .Proc: {
            return false, "Cannot have a proc outside the global scope\n"
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

resolveLet :: proc(startLoc : util.Location, tw : ^TokWalk, vars: ^map[string]Variable, program:^ASTProgram) -> (var:^ASTVarDef=nil,err:ErrorMsg) {
    ident, ok := peek(tw)
    if !ok {
        // Reached end of input
        return nil, util.locStr(startLoc, 
            "Keyword 'let' requires an identifier after it")
    }
    // Eat identifier
    expectNext(tw, .Ident) or_return
    varName := ident.value.(string)
    // Check if this variable exists already
    if varName in vars {
        return nil, util.locStr(curr(tw).loc, 
            "Redeclaration of var '%s'", varName)
    }
    // Eat = after
    eq := expectNext(tw, .Eq) or_return
    nextT, ok2 := next(tw)
    if !ok2 {
        return nil, util.locStr(eq.loc, 
            "Expected a value to set variable to after it")
    }
    // { values } syntax
    if nextT.type == .OBrace {
        // Eat {
        next(tw)
        block := resolveBlock(tw, program, vars^) or_return
        if len(block.outputTypes) != 1 {
            return nil, util.locStr(nextT.loc, 
                "Setting variables to a block requires one output type")
        }
        vars[varName] = {
            varName,
            .Int,
            false,
            false,
            block,
        }
        varDef := new(ASTVarDef)
        varDef.ident = varName
        varDef.value = block
        return varDef, nil
    }
    /*
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
    */
    return nil, util.locStr(nextT.loc, 
        "Expected a block value here\n")
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
            strings.write_string(sb, "{\n")
            for as in ty.nodes {
                printASTHelper(as, sb, true, indent + 1)
            }
        }
        case ^ASTVarDef: {
            strings.write_string(sb, "let ")
            strings.write_string(sb, ty.ident)
            strings.write_string(sb, " =")
            // Same indent because we want it to be indented 1 level in block
            printASTHelper(ty.value, sb, false, indent)
            // No closing }
            return
        }
    }
    for i in 0..<indent do strings.write_byte(sb, ' ')
    strings.write_string(sb, "}\n")
}


printProgram :: proc(program:^ASTProgram) {
    sb: strings.Builder
    for k, mac in program.macros {
        strings.write_string(&sb, "macro ")
        strings.write_string(&sb, k)
        strings.write_string(&sb, " :")
        for i in mac.inputs {
            strings.write_string(&sb, types.TypeToString[i])
            strings.write_byte(&sb, ' ')
        }
        strings.write_string(&sb, "> ")
        for o in mac.outputs {
            strings.write_string(&sb, types.TypeToString[o])
            strings.write_byte(&sb, ' ')
        }
        printASTHelper(AST(mac.body), &sb, false, 0)
    }
    for n,pr in program.procs {
        strings.write_string(&sb, "proc ")
        strings.write_string(&sb, n)
        strings.write_string(&sb, " :")
        for i in pr.inputs {
            strings.write_string(&sb, types.TypeToString[i])
            strings.write_byte(&sb, ' ')
        }
        strings.write_string(&sb, "> ")
        for o in pr.outputs {
            strings.write_string(&sb, types.TypeToString[o])
            strings.write_byte(&sb, ' ')
        }
        printASTHelper(AST(pr.body), &sb, false, 0)
    }
    fmt.printf("%s\n", strings.to_string(sb))
}