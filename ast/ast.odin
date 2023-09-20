// Handles changing tokens into AST to be used for code generation
//  and also does the type checking during
package ast

import "core:fmt"
import "core:os"
import "core:strings"
import "core:slice"

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
    ^ASTInputParam,
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
    ^ASTProcCall,
}

// Full program here
ASTProgram :: struct {
    procs:map[string]^Procedure,
    macros:map[string]^Macro,
    includedFiles:[dynamic]string,
}

ASTBlock :: struct {
    nodes: [dynamic]AST,
    state: ASTState,
    // The types left after the block
    outputTypes:[dynamic]Type
}

resolveTokens :: proc(tokens:[]Token) -> (out:^ASTProgram, err:util.ErrorMsg) {
    tw : TokWalk = { tokens, 0, {} }
    program := resolveProgram(&tw) or_return
    return program, nil
}

// Parses the entire program
resolveProgram :: proc(tw:^TokWalk, includedFiles: [dynamic]string = nil) -> (program:^ASTProgram, err:ErrorMsg) {
    program = new(ASTProgram)
    ok : bool
    for cur := curr(tw); curOk(tw); cur,_ = next(tw) {
        if cur.type == .Macro {
            macro := new(Macro)
            macro.inputs  = make([dynamic]Type)
            macro.outputs = make([dynamic]Type)

            inputAST : [dynamic]AST = nil
            defer delete(inputAST)
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
            if ok do inputAST = resolveTypes(tw, &macro.inputs, macroName, true)
            // >
            _, ok = tryNext(tw, .Gt)
            if ok do resolveTypes(tw, &macro.outputs)
            // {
            cur, ok := next(tw)
            if cur.type != .OBrace do return program, util.locStr(cur.loc, 
                "Expected an '{{' to start ")
            // Eat {
            next(tw)
            macro.body = resolveBlock(tw, program, {}, macro.inputs, inputAST) or_return
            if !typesMatch(macro.body.outputTypes, macro.outputs) {
                return program, util.locStr(macro.defLoc, 
                    "Return type signature of %s did not match actual returns.\nExpected: %s\nGot: %s",
                        macroName, types.typesToString(macro.outputs), types.typesToString(macro.body.outputTypes))
            }
            program.macros[macroName] = macro
        } else if cur.type == .Proc {
            procc := new(Procedure)
            procc.inputs  = make([dynamic]Type)
            procc.outputs = make([dynamic]Type)
            
            inputAST : [dynamic]AST = nil
            defer delete(inputAST)

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
            if ok do inputAST = resolveTypes(tw, &procc.inputs, procName, true)
            // >
            _, ok = tryNext(tw, .Gt)
            if ok do resolveTypes(tw, &procc.outputs)
            // {
            cur, ok := next(tw)
            if cur.type != .OBrace do return program, util.locStr(cur.loc, 
                "Expected an '{{' to start ")
            // Eat {
            next(tw)
            procc.body = resolveBlock(tw, program, {}, procc.inputs, inputAST) or_return
            if !typesMatch(procc.body.outputTypes, procc.outputs) {
                return program, util.locStr(procc.defLoc, 
                    "Return type signature of %s did not match actual returns.\nExpected: %s\nGot: %s",
                    procName, types.typesToString(procc.outputs), types.typesToString(procc.body.outputTypes))
            }
            program.procs[procName] = procc
        } else if cur.type == .Import {
            /*
            A few formats.
            import "file.stax"

            These will be supported later
            import <corelib>
            import proc1 proc2 from "library"
            import proc1 proc2 from <corelib>
            */
            fileNameStr, ok := tryNext(tw, .StringLit)
            if ok {
                fileName := fileNameStr.value.(string)
                // Import file and either insert tokens or parsed AST
                fmt.printf("Trying to import '%s'\n", fileName)
                if slice.contains(includedFiles[:], fileName) {
                    // Already included, so ignore
                    fmt.printf("Already Included\n")
                    continue
                }
                // Check for file existance
                if !os.exists(fileName) {
                    return program, util.locStr(fileNameStr.loc, 
                        "File '%s' does not exist\n", fileName)
                }
                append(&program.includedFiles, fileName)

                newTokens := tokenizer.tokenizeFile(fileName) or_return
                tw2 : TokWalk = { newTokens[:], 0, {} }
                newProgram := resolveProgram(&tw2, program.includedFiles) or_return
                // Add new procedures
                for prNm, procc in newProgram.procs {
                    // Make sure its a fresh name
                    nameExistsErr(prNm, program) or_return
                    // Move over to current scope
                    program.procs[prNm] = procc
                }
                // Add new macros
                for macName, macro in newProgram.macros {
                    // Make sure its a fresh name
                    nameExistsErr(macName, program) or_return
                    // Move over to current scope
                    program.macros[macName] = macro
                }
            } else {
                return program, "Import not implemented\n"
            }
        } else {
            // TODO: Global vars
            return program, util.locStr(cur.loc, 
                "Global scope can only include macro and proc statements")
        }
    }
    return program, nil
}

// Places a variable can be defined
NameLocs :: enum {
    Macro, Proc, Var
}

nameExists :: proc(name:string, program:^ASTProgram) -> NameLocs {
    if name in program.macros do return .Macro
    if name in program.procs do return .Proc
    return nil
}

nameExistsErr ::  proc(name:string, program:^ASTProgram) -> ErrorMsg {
    if name in program.macros do return fmt.tprintf(
        "Redeclaration of macro '%s'\n", name)
    if name in program.procs do return fmt.tprintf(
        "Redeclaration of proc '%s'\n", name)
    return nil
}

typesMatch :: proc(ts1, ts2:[dynamic]Type) -> bool {
    if len(ts1) != len(ts2) do return false
    for _, i in ts1 {
        if ts1[i] != ts2[i] do return false
    }
    return true
}


// Reads all the next type tokens and puts them into the given buffer
resolveTypes :: proc(tw:^TokWalk, out :^[dynamic]Type, name:string="", genAST := false) -> (output:[dynamic]AST = nil) {
    if genAST do output = make([dynamic]AST)
    i := 0
    for type, hasType := tryNext(tw, .Type); hasType; type, hasType = tryNext(tw, .Type) {
        append(out, type.value.(types.Type))
        if genAST {
            input := new(ASTInputParam)
            input.type = type.value.(types.Type)
            input.index = i
            input.from = name
            append(&output, input)
            i += 1
        }
    }
    return output
}

resolveBlock :: proc(tw:^TokWalk, program:^ASTProgram, inVars:map[string]Variable, inTypes:[dynamic]Type, inAST:[dynamic]AST) -> (block:^ASTBlock, err:ErrorMsg) {
    block = new(ASTBlock)
    block.nodes = make([dynamic]AST)
    // Import astNodes
    if inAST != nil {
        for a in inAST {
            append(&block.nodes, a)
        }
    }
    block.state = {
        make(map[string]Variable)
    }
    for k, &v in inVars {
        block.state.vars[k] = v
    }
    block.outputTypes = make([dynamic]Type)
    if inTypes != nil {
        for it in inTypes {
            append(&block.outputTypes, it)
        }
    }
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
            pushType(ts, .Int)

            value := new(ASTSyscall1)
            value.call = new(ASTPushLiteral)
            value.call.(^ASTPushLiteral) ^= SYS_EXIT
            value.arg1 = popNoDrop(curAST)
            append(curAST, value)
            // Consider dropping after exit calls cause value will never be used
            // append(&out, new(Drop))
        }
        case .Syscall0: {
            expectArgs(curAST^, ts, "syscall0", 
                {.Int}, cur.loc) or_return
            pushType(ts, .Int)
            value := new(ASTSyscall0)
            value.call = popNoDrop(curAST)
            append(curAST, value)
        }
        case .Syscall1: {
            expectArgs(curAST^, ts, "syscall1", 
                {.Int, .Any}, cur.loc) or_return
            pushType(ts, .Int)
            value := new(ASTSyscall1)
            value.call = popNoDrop(curAST)
            value.arg1 = popNoDrop(curAST)
            append(curAST, value)
        }
        case .Syscall2: {
            expectArgs(curAST^, ts, "syscall2", 
                {.Int, .Any, .Any}, cur.loc) or_return
            pushType(ts, .Int)
            value := new(ASTSyscall2)
            value.call = popNoDrop(curAST)
            value.arg1 = popNoDrop(curAST)
            value.arg2 = popNoDrop(curAST)
            append(curAST, value)
        }
        case .Syscall3: { 
            expectArgs(curAST^, ts, "syscall3", 
                {.Int, .Any, .Any, .Any}, cur.loc) or_return
            pushType(ts, .Int)
            value := new(ASTSyscall3)
            value.call = popNoDrop(curAST)
            value.arg1 = popNoDrop(curAST)
            value.arg2 = popNoDrop(curAST)
            value.arg3 = popNoDrop(curAST)
            append(curAST, value)
        }
        case .Drop: {
            expectArgs(curAST^, ts, "drop", {.Any}, cur.loc) or_return
            drop := new(ASTDrop)
            // Grab last item that wasn't a drop
            drop.value = popNoDrop(curAST)
            append(curAST, drop)
        }
        case .Macro: {
            return false, util.locStr(cur.loc, 
                "Macro is not supported outside global scope")
        }
        case .Puts: {
            // Should this instead become a proc?
            expectArgs(curAST^, ts, "puts", 
                {.Ptr, .Int}, cur.loc) or_return
            pushType(ts, .Int)

            value := new(ASTSyscall3)
            value.call = new(ASTPushLiteral)
            value.call.(^ASTPushLiteral) ^= SYS_WRITE
            // stdout
            value.arg1 = new(ASTPushLiteral)
            value.arg1.(^ASTPushLiteral) ^= 1

            value.arg2 = popNoDrop(curAST)
            value.arg3 = popNoDrop(curAST)
            append(curAST, value)
        }
        case .Gt: { 
            return false, "> AST TODO"
        }
        case .Lt: { 
            return false, "< AST TODO"
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
                newBody := AST(mac.body)
                newBody = cloneAST(&newBody)
                replaceInputsWithVals(&newBody, varName, curAST, len(mac.inputs), true) 
                for n in newBody.(^ASTBlock).nodes {
                    append(curAST, n)
                }
                free(newBody.(^ASTBlock))
                // Place output types
                for out in mac.outputs {
                    append(ts, out)
                }
                next(tw)
                return false, nil
            } else if varName in program.procs {
                // Procedure
                // Need to pop args into appropriate registers
                call := new(ASTProcCall)
                call.ident = varName
                call.nargs = len(program.procs[varName].inputs)
                append(curAST, call)
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
                // Cast Int to float
                if peekType(ts) == .Int && typeValue == .Float {
                    popType(ts)
                    pushType(ts, .Float)
                    unop := new(ASTUnaryOp)
                    unop.op = .CastIntToFloat
                    unop.value = popNoDrop(curAST)
                    append(curAST, unop)
                    next(tw)
                    return
                }
                if peekType(ts) == .Float && typeValue == .Int {
                    popType(ts)
                    pushType(ts, .Int)
                    unop := new(ASTUnaryOp)
                    unop.op = .CastFloatToInt
                    unop.value = popNoDrop(curAST)
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
            block := resolveBlock(tw, program, vars^, nil, nil) or_return
            // Make sure the block is not empty
            if len(block.nodes) > 0 {
                for t in block.outputTypes {
                    pushType(ts, t)
                }
                append(curAST, block)
            }
        }
        case .CBrace: {
            return true, nil
        }
        case .Proc: {
            return false, "Cannot have a proc outside the global scope\n"
        }
        case .Import: {
            return false, "Cannot `import` outside of global scope"
        }
    }
    next(tw)
    return false, nil
}

// Grabs next element that isn't a drop
popNoDrop :: proc(curAST:^[dynamic]AST) -> AST {
    for i := len(curAST) - 1; i >= 0; i -= 1 {
        node, isDrop := curAST[i].(^ASTDrop)
        if !isDrop {
            returnElem := curAST[i]
            // Remove then return
            ordered_remove(curAST, i)
            return returnElem
        }
    }
    panic("Check your lengths\n")
}

printASTList :: proc(ast:^[dynamic]AST){
    sb : strings.Builder
    for a in ast {
        printASTHelper(a, &sb)
    }
    fmt.printf("%s\n", strings.to_string(sb))
}

// Used for macros
replaceInputsWithVals :: proc(block:^AST, name:string, curAST:^[dynamic]AST, numInputs:int, isRoot:=false){
    if numInputs == 0 do return
    switch &type in block^ {
        case ^ASTInputParam: {
            if type.from != name do return
            // Replace with stuff from curAST
            block ^= curAST[len(curAST) - numInputs + type.index]
        }
        case ^ASTBinOp:{
            replaceInputsWithVals(&type.lhs, name, curAST, numInputs)
            replaceInputsWithVals(&type.rhs, name, curAST, numInputs)
        }
        case ^ASTBlock:{
            for &node in type.nodes {
                replaceInputsWithVals(&node, name, curAST, numInputs)
            }
        }
        case ^ASTSyscall0: {
            replaceInputsWithVals(&type.call, name, curAST, numInputs)
        }
        case ^ASTSyscall1:{
            replaceInputsWithVals(&type.call, name, curAST, numInputs)
            replaceInputsWithVals(&type.arg1, name, curAST, numInputs)
        }
        case ^ASTSyscall2:{
            replaceInputsWithVals(&type.call, name, curAST, numInputs)
            replaceInputsWithVals(&type.arg1, name, curAST, numInputs)
            replaceInputsWithVals(&type.arg2, name, curAST, numInputs)
        }
        case ^ASTSyscall3:{
            replaceInputsWithVals(&type.call, name, curAST, numInputs)
            replaceInputsWithVals(&type.arg1, name, curAST, numInputs)
            replaceInputsWithVals(&type.arg2, name, curAST, numInputs)
            replaceInputsWithVals(&type.arg3, name, curAST, numInputs)
        }
        case ^ASTUnaryOp:{
            replaceInputsWithVals(&type.value, name, curAST, numInputs)
        }
        case ^ASTVarDef:{
            replaceInputsWithVals(&type.value, name, curAST, numInputs)
        }
        case ^ASTDrop:{
            replaceInputsWithVals(&type.value, name, curAST, numInputs)
        }
        // No traversal
        case ^ASTPushLiteral, ^ASTVarRef, ^ASTProcCall: {}

    }
    if isRoot {
        // Pop off number of args from input AST
        for i in 0..<numInputs {
            pop(curAST)
        }
    }
}

resolveIntLit :: proc(ts:^[dynamic]Type, intLit:Token) -> (^ASTPushLiteral, util.ErrorMsg) {
    if intLit.type != .IntLit do return nil, util.locStr(intLit.loc,
        "Invalid token type for an Int Lit")
    value := newIntLit(intLit.value.(int))
    pushType(ts, .Int)
    return value, nil
}

// Handle setting up "string lit" AST. Pushes types onto type stack
resolveStringLit :: proc(ts:^[dynamic]Type, strLit:Token) -> (^ASTPushLiteral, ^ASTPushLiteral, ErrorMsg) {
    // Length
    length := new(ASTPushLiteral)
    length ^= len(strLit.value.(string))
    pushType(ts, .Int)

    // Label
    value := new(ASTPushLiteral)
    value ^= strLit.value.(string)
    pushType(ts, .Ptr)
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
    /*
    Formats
    let <ident> = {<Block with 1 return>}
    let <ident> = <AST>

    */
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
    // TODO: Check if name exists in procedures and macros
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
        block := resolveBlock(tw, program, vars^, nil, nil) or_return
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
                    // Escape characters
                    for c in lit {
                        if c == '\n' {
                            strings.write_string(sb, "\\n")
                        } else if c == '\r' {
                            strings.write_string(sb, "\\r")
                        } else if c == '\t' {
                            strings.write_string(sb, "\\t")
                        } else if c == '"' {
                            strings.write_string(sb, "\\\"")
                        } else if c == 0 {
                            strings.write_string(sb, "\\0")
                        } else {
                            strings.write_byte(sb, u8(c))
                        }
                    }
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
        case ^ASTInputParam: {
            fmt.sbprintf(sb, "Input%d from %s '%s'\n", ty.index, ty.from, ty.type)
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
            /*
            // Remove last spaces
            for i in 0..<indent do strings.pop_byte(sb)
            printASTHelper(ty.value, sb, true, indent)
            for i in 0..<indent do strings.write_byte(sb, ' ')
            strings.write_string(sb, "Drop\n")
            return 
            */
            strings.write_string(sb, "drop {\n")
            printASTHelper(ty.value, sb, true, indent + 1)

        }
        case ^ASTVarRef: {
            fmt.sbprintf(sb, "Ref \"%s\"\n", ty.ident)
            return
        }
        case ^ASTBlock: {
            strings.write_string(sb, "{\n")
            for as in ty.nodes {
                printASTHelper(as, sb, true, indent + 1)
            }
        }
        case ^ASTVarDef: {
            fmt.sbprintf(sb, "let %s =", ty.ident)
            // Same indent because we want it to be indented 1 level in block
            printASTHelper(ty.value, sb, false, indent)
            // No closing }
            return
        }
        case ^ASTProcCall: {
            fmt.sbprintf(sb, "%s(%d args)\n", ty.ident, ty.nargs)
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