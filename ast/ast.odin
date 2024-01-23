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
    // Different than len(vars) as it accounts for 
    //  the max number of variables in any sub-block
    totalVars:int,
    // Space for variables is allocated only at the beginning of
    //  a proc
}

AST :: union {
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
    ^ASTVarRead,
    ^ASTVarWrite,
    ^ASTVarDecl,
    ^ASTProcCall,
    ^ASTProcReturn,
    ^ASTIf,
    ^ASTWhile,
    ^ASTDup,
    ^ASTRot,
    ^ASTSwap,
    ^ASTNip,
    ^ASTOver,
}

// Full program here
ASTProgram :: struct {
    procs:map[string]^Procedure,
    macros:map[string]^Macro,
    includedFiles:[dynamic]string,
    globalVars:map[string]Variable,
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
        // Root level can only have macros, procs, and includes 
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
            fmt.printf("Parsing macro '%s'\n", macroName)
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
            macro.body = resolveBlock(tw, program, {}, macro.inputs, &inputAST) or_return
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
            procc.body = resolveBlock(tw, program, {}, procc.inputs, &inputAST) or_return
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
        } else if cur.type == .Let {
            astHolder := make([dynamic]AST)
            defer delete(astHolder)
            typeHolder := make([dynamic]Type)
            defer delete(typeHolder)
            
            letDef, setVar := resolveLet(cur.loc, tw, &typeHolder, &program.globalVars, program, &astHolder, true) or_return
            // Not needed
            free(letDef)
            tw.i -= 1
        } else {
            return program, util.locStr(cur.loc, 
                "Global scope can only include macro proc, let, and import statements")
        }
    }
    hoistVarDecls(program)
    return program, nil
}

// Places a variable can be defined
NameLocs :: enum { MacroL = 1, Proc, LocalVar, GlobalVar }

// Checks if a name is already used in macros, procs or variables
nameExists :: proc(name:string, program:^ASTProgram, localVars:^map[string]Variable = nil) -> NameLocs {
    if name in program.macros do return .MacroL
    if name in program.procs do return .Proc
    if name in program.globalVars do return .GlobalVar
    if localVars != nil && name in localVars do return .LocalVar
    return nil
}

// Returns an error message if a name is already defined
nameExistsErr ::  proc(name:string, program:^ASTProgram, localVars:^map[string]Variable = nil) -> ErrorMsg {
    if name in program.macros do return fmt.tprintf(
        "Redeclaration of macro '%s'\n", name)
    if name in program.procs do return fmt.tprintf(
        "Redeclaration of proc '%s'\n", name)
    if name in program.globalVars do return fmt.tprintf(
        "Redeclaration of global var '%s'\n", name)
    if localVars != nil && name in localVars do return fmt.tprintf(
        "Redeclaration of local var '%s'\n", name)
    return nil
}

// Compares two type stacks
typesMatch :: proc(ts1, ts2:[dynamic]Type) -> bool {
    if len(ts1) != len(ts2) do return false
    for _, i in ts1 {
        if ts1[i] != ts2[i] do return false
    }
    return true
}


// Reads all the next type tokens and puts them into the given buffer
resolveTypes :: proc(tw:^TokWalk, out :^[dynamic]Type, name:string="", genAST := false) -> (output:[dynamic]AST = nil) {
    FRONT :: false
    if genAST do output = make([dynamic]AST)
    i := 0
    for type, hasType := tryNext(tw, .Type); hasType; type, hasType = tryNext(tw, .Type) {
        when FRONT {
            inject_at(out, 0, type.value.(types.Type))
        } else {
            append(out, type.value.(types.Type))
        }
        if genAST {
            input := new(ASTInputParam)
            input.type = type.value.(types.Type)
            input.index = i
            input.from = name
            when FRONT {
                inject_at(&output, 0, input)
            } else {
                append(&output, input)
            }
            i += 1
        }
    }    
    return output
}
// Grabs all tokens until a closing block is found
resolveBlock :: proc(tw:^TokWalk, program:^ASTProgram, inVars:map[string]Variable, inTypes:[dynamic]Type, inAST:^[dynamic]AST) -> (block:^ASTBlock, err:ErrorMsg) {
    block = new(ASTBlock)
    block.nodes = make([dynamic]AST)
    // Import astNodes
    if inAST != nil {
        for &a in inAST {
            append(&block.nodes, a)
        }
        // Empty the output
        clear(inAST)
    }
    block.state = {
        make(map[string]Variable),
        len(inVars)
    }
    // Clone over vars
    for k, &v in inVars {
        block.state.vars[k] = v
    }
    block.outputTypes = make([dynamic]Type)
    // Clone over types. 
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
        // ret := 
        if .Block in (resolveNextToken(tw, ts, program, vars, out) or_return) {
            return block, nil
        }
    }
    // Calculate number of vars needed
    maxVars := len(vars)
    for n in out {
        bl, isBlock := n.(^ASTBlock)
        if isBlock {
            maxVars = max(maxVars, len(bl.state.vars))
        }
    }
    block.state.totalVars = maxVars
    return block, "Reached end of input without closing block\n"
}

// Tells if certain keywords were encountered in resolving tokens
BreakCodes :: bit_set[enum {
    Block,
    If,
}]

resolveNextToken :: proc(tw:^TokWalk, ts:^[dynamic]Type, program:^ASTProgram, vars:^map[string]Variable, curAST:^[dynamic]AST) -> (exitBlock : BreakCodes = {}, err:ErrorMsg=nil){
    if !curOk(tw) do return {}, "Expected next token, but had nothing"
    cur := curr(tw)
    switch cur.type {
        case .Error: {
            return {}, util.locStr(cur.loc, 
                "Error Token found\n")
        }
        case .IntLit: {
            append(curAST, resolveIntLit(ts, cur) or_return)
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
        case .CString: {
            cStr := resolveCString(ts, cur) or_return
            append(curAST, cStr)
        }
        case .BoolLit: {
            value := new(ASTPushLiteral)
            value ^= cur.value.(bool)
            pushType(ts, .Bool)
            append(curAST, value)
        }
        case .Plus: {
            plus := resolveBinOp(curAST, ts, cur, "+", .Plus, {.Int, .Int}, .Int) or_return
            append(curAST, plus)
        }
        case .Dash: {
            dash := resolveBinOp(curAST, ts, cur, "-", .Minus, {.Int, .Int}, .Int) or_return
            append(curAST, dash)
        }
        case .Eq: {
            eq := resolveBinOp(curAST, ts, cur, "=", .Eq, {.Int, .Int}, .Bool) or_return
            append(curAST, eq)
        }
        case .Gt: { 
            gt := resolveBinOp(curAST, ts, cur, ">", .Gt, {.Int, .Int}, .Bool) or_return
            append(curAST, gt)
        }
        case .Ge: {
            ge := resolveBinOp(curAST, ts, cur, ">=", .Ge, {.Int, .Int}, .Bool) or_return
            append(curAST, ge)
        }
        case .Lt: { 
            lt := resolveBinOp(curAST, ts, cur, "<", .Lt, {.Int, .Int}, .Bool) or_return
            append(curAST, lt)
        }
        case .Le: {
            le := resolveBinOp(curAST, ts, cur, "<=", .Le, {.Int, .Int}, .Bool) or_return
            append(curAST, le)
        }
        case .Ne: {
            eq := resolveBinOp(curAST, ts, cur, "!=", .Ne, {.Int, .Int}, .Bool) or_return
            append(curAST, eq)
        }
        case .Exit: {
            expectArgs(curAST^, ts, "exit", 
                {.Int}, cur.loc) or_return
            // Exit gets auto dropped

            value := new(ASTSyscall1)
            value.call = new(ASTPushLiteral)
            value.call.(^ASTPushLiteral) ^= SYS_EXIT
            value.arg1 = popNoDrop(curAST)

            drop := new(ASTDrop)
            drop.value = value
            append(curAST, drop)
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
            return {}, util.locStr(cur.loc, 
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
        case .If: { 
            // Parse Tokens until you get {
            iff := new(ASTIf)
            iff.elseBlock = nil
            next(tw)
            iff.cond = resolveIfCond(tw, ts, program, vars, curAST) or_return
            // Set up what the jump type for the if is
            #partial switch condType in iff.cond {
                case ^ASTBinOp: {
                    #partial switch condType.op {
                        // Plus, Minus, Eq, Ne, Lt,Gt 
                        case .Eq: iff.jumpType = .Eq
                        case .Ne: iff.jumpType = .Ne
                        case .Lt: iff.jumpType = .Lt
                        case .Gt: iff.jumpType = .Gt
                        case: return {}, 
                            "Invalid binary expression for if statement"
                    }
                }
                case ^ASTPushLiteral:{
                    // Should always be of type bool
                    b := condType.(bool)
                    iff.jumpType = .Eq
                }
                case:{
                    return {}, "Invalid type for ending if statement\n"
                }
            }
            resolveNextToken(tw, ts, program, vars, curAST) or_return
            iff.body = pop(curAST)
            append(curAST, iff)
            // Check for else
            if curr(tw).type == .Else {
                // Eat 'else'
                next(tw)
                resolveNextToken(tw, ts, program, vars, curAST) or_return
                iff.elseBlock = pop(curAST)
            } else {
                // Return types must even out
            }
            return {}, nil
        }
        case .While: {
            fmt.printf("Startig while\n")
            while := new(ASTWhile)
            while.inputTypes = types.cloneTypeStack(ts^)
            fmt.printf("  Expected: ")
            types.printTypes(while.inputTypes)
            fmt.println()
            next(tw)
            while.cond = resolveWhileCond(tw, ts, program, vars) or_return
            // Expect a boolean on top
            expectTypes(ts, {.Bool}, "while", cur.loc) or_return
            // Setting jump type
            #partial switch condType in while.cond[len(while.cond) - 1] {
                case ^ASTBinOp: {
                    // Types should be flipped. Jump to end afterwards
                    #partial switch condType.op {
                        // Plus, Minus, Eq, Ne, Lt,Gt 
                        case .Eq: while.jumpType = .Eq
                        case .Ne: while.jumpType = .Ne
                        case .Lt: while.jumpType = .Lt
                        case .Gt: while.jumpType = .Gt
                        case: return {}, 
                            "Invalid binary expression for if statement"
                    }
                }
                case ^ASTPushLiteral:{
                    // Should always be of type bool
                    b := condType.(bool)
                    while.jumpType = .Eq
                }
                case:{
                    return {}, "Invalid type for ending if statement\n"
                }
            }
            // popType(ts)
            fmt.printf("  Has in cond: ")
            types.printTypes(while.inputTypes)
            fmt.println()

            // Need to pass in new input types again to body
            newIn := generateInputsFromTypes(ts^)
            // Get the body
            // Must have block
            if curr(tw).type != .OBrace {
                return nil, "`while ... then` expects a block to follow it\n"
            }
            next(tw)
            bl := resolveBlock(tw, program, vars^, ts^, &newIn) or_return
            //resolveNextToken(tw, ts, program, vars, &newIn) or_return 
            clear(ts)
            delete(newIn)

            while.body = bl

            fmt.printf("  Got from body: ")
            types.printTypes(ts^)
            fmt.println()

            // New output types are the output from the while block
            

            if !typesMatch(while.inputTypes, bl.outputTypes) {
                return {}, util.locStr(cur.loc, 
                    "While output types should be the same as the input types")
            }
            clear(ts)
            for t in bl.outputTypes {
                append(ts, t)
            }
            append(curAST, while)
        }
        case .Let: { 
            letDef, setVar := resolveLet(cur.loc, tw, ts, vars, program, curAST) or_return
            append(curAST, letDef)
            if setVar != nil {
                append(curAST, setVar)
            }
            // Don't increment after
            return
        }
        case .Bang: {
            // Variable write
            // x 10 ! // writes 10 to x
            if len(ts) < 2 {
                return {}, util.locStr(cur.loc, 
                    "Writing to variable requires 2 elements on stack")
            }
            value := popNoDrop(curAST)
            // Variable reference
            top := popNoDrop(curAST)
            ref, isRef := top.(^ASTVarRef)

            valueType, _ := popType(ts)
            refType,   _ := popType(ts)
            if refType != .Ptr || !isRef {
                return {}, util.locStr(cur.loc,
                    "Cannot write to a non variable\n")
            }
            // Check if the name is defined
            nameLoc := nameExists(ref.ident, program, vars)
            if nameLoc == nil {
                return {}, util.locStr(cur.loc, 
                    "Cannot write to undefined ident '%s'", ref.ident)
            }
            // Setup AST
            varWrite := new(ASTVarWrite)
            varWrite.ident = ref.ident
            varWrite.value = value
            
            // Make sure 
            varType : Type
            if nameLoc == .GlobalVar {
                varWrite.isGlobal = true
                varType = program.globalVars[ref.ident].type
            } else if nameLoc == .LocalVar {
                varWrite.isGlobal = false
                varType = vars[ref.ident].type
            } else {
                // Err
                free(varWrite)
                return {}, util.locStr(cur.loc, 
                    "Cannot write to non variable ident '%s'", ref.ident)
            }
            // Make sure you are writing the right type
            if varType != valueType {
                return {}, util.locStr(cur.loc, 
                    "Cannot write type '%s' to '%s' with type '%s'", 
                    types.TypeToString[valueType], 
                    ref.ident, 
                    types.TypeToString[varType])
            }
            append(curAST, varWrite)
        }
        case .Type: { 
            return {}, "(type) AST TODO"
        }
        case .Colon: { 
            return {}, ": AST TODO"
        }
        case .Ident: {
            // raw ident should give the value from variable
            varName := cur.value.(string)
            loc := nameExists(varName, program, vars)
            if loc == nil {
                fmt.printf("%s is macro: %s\n",varName, varName in program.macros ? "true" : "false")
                return nil, util.locStr(cur.loc, 
                    "Unknown identifier of '%s'", varName)
            }
            if loc == .LocalVar {
                // Variable
                varRef := new(ASTVarRef)
                varRef.isGlobal = false
                varRef.ident = varName
                pushType(ts, .Ptr)
                (&vars[varName]).used = true
                append(curAST, varRef)
            } else if loc == .MacroL {
                // Macro
                mac : ^Macro = program.macros[varName]
                // Check input types
                expectTypes(ts, mac.inputs[:], "macro inputs", cur.loc) or_return
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
            } else if loc == .Proc {
                // Procedure
                // Need to pop args into appropriate registers
                call := new(ASTProcCall)
                call.ident = varName
                call.nargs = len(program.procs[varName].inputs)
                procc := program.procs[varName]
                expectArgs(curAST^, ts, varName, procc.inputs[:], cur.loc) or_return
                for t := 0; t < len(procc.outputs); t += 1 {
                    // Add in placeholder ASTNodes for the types
                    procRet := new(ASTProcReturn)
                    procRet.type = procc.outputs[t]
                    procRet.from = varName
                    procRet.index = t
                    append(curAST, procRet)
                    append(ts, procc.outputs[t])
                }
                append(curAST, call)
            } else if loc == .GlobalVar {
                // Global Variable
                varRef := new(ASTVarRef)
                varRef.isGlobal = true
                varRef.ident = varName[:]
                pushType(ts, .Ptr)
                (&program.globalVars[varName]).used = true
                append(curAST, varRef)
            } else {
                return {}, util.locStr(cur.loc, 
                    "Unknown token of '%s'", varName)    
            }
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
                return {}, "Cannot currently cast to and from anything except int and float"
            }
            return {}, "Invalid character after ("
        }
        case .CParen: { 
            return {}, ") AST TODO"
        }
        case .OBrace: {
            next(tw)
            block := resolveBlock(tw, program, vars^, ts^, curAST) or_return
            // Make sure the block is not empty
            if len(block.nodes) > 0 {
                for t in block.outputTypes {
                    pushType(ts, t)
                }
                append(curAST, block)
            }
        }
        case .Then: {
            // Eat `then`
            next(tw)
            return {.If}, nil
        }
        case .Else: {
            return {}, "Cannot have an else without an if statement\n"
        }
        case .CBrace: {
            return {.Block}, nil
        }
        case .Proc: {
            return {}, "Cannot have a proc outside the global scope\n"
        }
        case .Import: {
            return {}, "Cannot `import` outside of global scope"
        }
        case .At: {
            // Var read
            // x @ // gives value of x
            last := popNoDrop(curAST)
            expectTypes(ts, {.Ptr}, "var read",cur.loc) or_return
            varRef, isVarRef := last.(^ASTVarRef)
            if isVarRef {
                // Handle reading the data
                varRead := new(ASTVarRead)
                varRead.ident = varRef.ident
                varRead.isGlobal = varRef.isGlobal
                if varRef.isGlobal {
                    pushType(ts, program.globalVars[varRef.ident].type)
                } else {
                    pushType(ts, vars[varRef.ident].type)
                }
                free(varRef)
                append(curAST, varRead)
            } else {
                //return {}, util.locStr(cur.loc, 
                //    "Operator @ must follow a variable reference")
                pushType(ts, .Any)
                varRead := new(ASTVarRead)
                varRead.ident = ""
                varRead.isGlobal = false
                append(curAST, varRead)
            }
        }
        case .Dup: {
            if len(ts) == 0 {
                return {}, util.locStr(cur.loc,
                    "Dup requires at least one value on the stack")
            }
            // Copy top value of stack 
            append(ts, ts[len(ts)-1])
            append(curAST, new(ASTDup))
        }
        case .Nip: {
            if len(ts) < 2 {
                return {}, util.locStr(cur.loc,
                    "Nip requires at least two values on the stack")
            }
            top := pop(ts)
            pop(ts)
            append(ts, top)
            append(curAST, new(ASTNip))
        }
        case .Rot: {
            if len(ts) < 3 {
                return {}, util.locStr(cur.loc,
                    "Rot requires at least three values on the stack")
            }
            top := pop(ts)
            mid := pop(ts)
            bot := pop(ts)
            append(ts, mid)
            append(ts, bot)
            append(ts, top)
            append(curAST, new(ASTRot))
        }
        case .Over: {
            if len(ts) < 2 {
                return {}, util.locStr(cur.loc,
                    "Over requires at least two values on the stack")
            }
            // Copy top value of stack 
            append(ts, ts[len(ts)-2])
            append(curAST, new(ASTOver))
        }
        case .Swap: {
            if len(ts) < 2 {
                return {}, util.locStr(cur.loc,
                    "Swap requires at least two values on the stack")
            }
            // Copy top value of stack 
            top := pop(ts)
            mid := pop(ts)
            append(ts, mid)
            append(ts, top)
            append(curAST, new(ASTSwap))
        }
        case .Cast: {
            newType := cur.value.(types.Type)
            popType(ts)
            pushType(ts, newType)
        }
        case .QQQ: {
            // Stop parsing and output current type stack
            fmt.printf("INFO: type stack bottom ")
            types.printTypes(ts^)
            fmt.printf(" top\nQuiting Execution\n")
            os.exit(1)
        }
        case .OBracket: {
            return nil, "TODO: Obracket"
        }
        case .CBracket: {
            return nil, "Close bracket cannot occur before an open one"
        }
    }
    next(tw)
    return {}, nil
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
        case ^ASTVarDecl:{
            // Nothing to do
        }
        case ^ASTDrop:{
            replaceInputsWithVals(&type.value, name, curAST, numInputs)
        }
        case ^ASTIf: {
            replaceInputsWithVals(&type.cond, name, curAST, numInputs)
            replaceInputsWithVals(&type.body, name, curAST, numInputs)
        }
        case ^ASTWhile: {
            for &v in type.cond {
                replaceInputsWithVals(&v, name, curAST, numInputs)
            }
            replaceInputsWithVals(&type.body, name, curAST, numInputs)
        }
        case ^ASTVarRead: {}
        case ^ASTVarWrite: {}
        // No traversal
        case ^ASTPushLiteral, ^ASTVarRef, ^ASTProcCall, ^ASTProcReturn: {}
        case ^ASTNip, ^ASTOver, ^ASTRot, ^ASTSwap, ^ASTDup: {}


    }
    if isRoot {
        // Pop off number of args from input AST
        for i in 0..<numInputs {
            pop(curAST)
        }
    }
}

// Used for while loops to allow AST gen
generateInputsFromTypes :: proc(ts:[dynamic]Type) -> [dynamic]AST {
    out := make([dynamic]AST)
    // assert(out != nil)
    for t in ts {
        ip := new(ASTInputParam)
        ip.from = "while"
        ip.type = t
        ipAST : AST = ip
        append(&out, ipAST) 
    }
    return out
}

resolveIfCond :: proc(tw:^TokWalk, ts:^[dynamic]Type, program:^ASTProgram, vars:^map[string]Variable, curAST:^[dynamic]AST) -> (block:AST, err:ErrorMsg) {
    // Go until you are told to end the if
    for !(.If in (resolveNextToken(tw, ts, program, vars, curAST) or_return)){

    }
    // Check last type to be a boolean, or else bad
    if ts[len(ts) - 1] != .Bool {
        return {}, "Expeced a boolean expression for if statement\n"
    }
    popType(ts)
    return popNoDrop(curAST), nil
}

resolveWhileCond :: proc(tw:^TokWalk, ts:^[dynamic]Type, program:^ASTProgram, vars:^map[string]Variable) -> (out:[dynamic]AST, err:ErrorMsg) {
    newAST := make([dynamic]AST)
    // Setup pseudo inputs which generate nothing
    // TODO: Does this need to be here
    /*
    for t in ts {
        fmt.printf("Generating input of %s\n", types.TypeToString[t])

        input := new(ASTInputParam)
        input.from = ""
        input.type = t
        input.index = -1
        append(&newAST, input)
    }*/
    for !(.If in (resolveNextToken(tw, ts, program, vars, &newAST) or_return)){}
    // Go until you need to escape
    return newAST, nil
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

resolveCString :: proc(ts:^[dynamic]Type, cStr:Token) -> (^ASTPushLiteral, ErrorMsg) {
    value := new(ASTPushLiteral)
    value ^= cStr.value.(string)
    pushType(ts, .Ptr)
    return value, nil
}

resolveBinOp :: proc(curAST:^[dynamic]AST, ts:^[dynamic]Type, tok:Token, opName:string, opType:ASTBinOps, inTypes:[]Type, outType:Type) -> (op:^ASTBinOp, err:ErrorMsg) {
    // Requires 2 things on the stack
    // expectTypes(ts, inTypes, opName, tok.loc) or_return
    expectArgs(curAST^, ts, opName, inTypes, tok.loc) or_return
    pushType(ts, outType)
    value := new(ASTBinOp)
    value.rhs = pop(curAST)
    value.lhs = pop(curAST)
    value.op = opType
    return value, nil
}
resolveLet :: proc(startLoc : util.Location, tw : ^TokWalk, 
    ts:^[dynamic]Type, vars: ^map[string]Variable, 
    program:^ASTProgram, curAST:^[dynamic]AST, isGlobal:=false) -> 
        (var:^ASTVarDecl=nil,setter:^ASTVarWrite=nil, err:ErrorMsg) {

    /*
    Formats
    let <ident> : <type> // Initialize but not set
    let <ident> = <AST> // if block, must have 1 return
    let <ident> : <type> = <AST>
    */
    // Eat identifier
    ident := expectNext(tw, .Ident) or_return
    varName := ident.value.(string)
    // Check if this variable exists already
    nameExistsErr(varName, program, vars) or_return
    // Type given by : <type> syntax
    expectedType : Type
    // Check for : <type>
    if _, hasColon := tryNext(tw, .Colon); hasColon {
        // Needs to be <type>
        typeToken := expectNext(tw, .Type) or_return
        expectedType = typeToken.value.(types.Type)
    }
    // Handle =
    if eq, ok := tryNext(tw, .Eq); ok {
        // Skip past =
        next(tw)
        resolveNextToken(tw, ts, program, vars, curAST) or_return

        value := popNoDrop(curAST)
        block, isBlock := value.(^ASTBlock)
        if isBlock {
            // Make sure there was only one output type
            if len(block.outputTypes) != 1 {
                return nil,nil, util.locStr(eq.loc, 
                    "Setting variables to a block requires one output type")
            }
            retType, _ := popType(ts)
            if expectedType != nil && expectedType != retType {
                return nil, nil, util.locStr(eq.loc, 
                    "Expected type of '%s' does not match actual of '%s'",
                    types.TypeToString[expectedType], 
                    types.TypeToString[retType])
            }
            expectedType = retType
        } else {
            if len(ts) == 0 do return nil, nil, 
                util.locStr(eq.loc, "Did not have extra type to return")
            type, _ := popType(ts)
            if expectedType != nil && expectedType != type {
                return nil, nil, util.locStr(eq.loc, 
                    "Expected type of '%s' does not match actual of '%s'",
                    types.TypeToString[expectedType], 
                    types.TypeToString[type])
            }
            expectedType = type
        }
        setter = new(ASTVarWrite)
        setter.ident = varName
        setter.value = value
    } else if expectedType == nil {
        // Requires : <type>
        return nil, nil, util.locStr(ident.loc, 
            "Variable declarations without initialization requires a type annotation")
    } else {
        // Skip past <type> from :
        next(tw)
    }
    var = new(ASTVarDecl)
    var.ident = varName
    var.type = expectedType
    if isGlobal {
        program.globalVars[varName] = {
            // varName,
            fmt.aprintf("global_%s", varName),
            expectedType,
            false,
            false,
            (setter != nil) ? setter.value : nil,
        }
    } else {
        vars[varName] = {
            varName,
            expectedType,
            false,
            false,
            (setter != nil) ? setter.value : nil,
        }
    }
    var.isGlobal = isGlobal
    return var, setter, nil
}

// Will eat types passed in
expectArgs :: proc(out : [dynamic]AST, ts:^[dynamic]Type, label:string, types:[]Type, loc:tokenizer.Location) -> util.ErrorMsg {
    /* // This part isn't valid considering proc calls or block scopes
    if len(out) < len(types) {
        return util.locStr(loc, 
            "%s requires %d argument%s", 
            label, len(types), 
            (len(types))==1?"":"s"
        )
    }*/
    return expectTypes(ts, types, label, loc)
}