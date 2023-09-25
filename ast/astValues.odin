package ast

import "core:strings"
import "core:fmt"
import "../types"
import "../util"

// Holds value to push
ASTDrop :: struct {
    value: AST
}
// Holds what syscall number to use
ASTBinOp :: struct {
    op: ASTBinOps,
    lhs, rhs: AST
}
// Different possible binary operations
ASTBinOps :: enum {
    Plus,
    Minus,
    Eq, Ne,
    Lt,
    Gt
}
ASTBinOpsString : map[ASTBinOps]string = {
    .Plus = "+",
    .Eq = "=",
}
ASTUnaryOps :: enum {
    CastFloatToInt,
    CastIntToFloat,
    // Drop,
}
ASTUnaryOpsString : map[ASTUnaryOps]string = {
    .CastFloatToInt = "(Int)",
    .CastIntToFloat = "(Float)",
}
ASTUnaryOp :: struct {
    op: ASTUnaryOps,
    value: AST
}
ASTPushLiteral :: union {
    int,
    bool,
    f64,
    // Strings should push the label, then the length
    string,
}
ASTInputParam :: struct {
    type:types.Type,
    // Which argument this is
    index:int,
    from:string,
}
ASTSyscall0 :: struct {
    call: AST,
}
ASTSyscall1 :: struct {
    call: AST,
    arg1: AST,
}
ASTSyscall2 :: struct {
    call: AST,
    arg1: AST,
    arg2: AST,
}
ASTSyscall3 :: struct {
    call: AST,
    arg1: AST,
    arg2: AST,
    arg3: AST,
}
ASTVarDef :: struct {
    ident : string,
    value : AST,
    // Cannot be reassigned to
    isConst : bool,
}
// Reference for a var. Can become a write or read with different ops
ASTVarRef :: struct {
    ident: string,
}
ASTProcCall :: struct {
    ident: string,
    nargs: int,
}
ASTIf :: struct {
    cond, body: AST,
    jumpType:JumpType,
    elseBlock: AST,
}
JumpType :: enum {
    Eq, Ne, 
    Lt, Gt,
}

Variable :: struct {
    label:string,
    type:types.Type,
    // If not written back into then can optimize 
    updated: bool,
    // Tells if the value gets read
    used: bool,
    // Used for tracking for optimizing out
    value:AST,
}

// In place replacement when calling
Macro :: struct {
    inputs:[dynamic]Type,
    outputs:[dynamic]Type,
    body:^ASTBlock,
    defLoc: util.Location
}

// Procedures are generated differently than macros
Procedure :: struct {
    body:^ASTBlock,
    inputs:[dynamic]Type,
    outputs:[dynamic]Type,
    defLoc: util.Location
}

newIntLit :: proc(val:int) -> (^ASTPushLiteral) {
    ret := new(ASTPushLiteral)
    ret ^= val
    return ret
}
// Printing

printAST :: proc(ast:AST) {
    sb : strings.Builder
    printASTHelper(ast, &sb)
    fmt.printf("%s\n", strings.to_string(sb))
}

printASTList :: proc(ast:^[dynamic]AST){
    sb : strings.Builder
    for a in ast {
        printASTHelper(a, &sb)
    }
    fmt.printf("%s\n", strings.to_string(sb))
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
                    if lit {
                        strings.write_string(sb, "true")
                    } else {
                        strings.write_string(sb, "false")
                    }
                }
                case string: {
                    strings.write_string(sb, util.escapeString(lit))
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
            
            // Remove last spaces
            for i in 0..<indent do strings.pop_byte(sb)
            printASTHelper(ty.value, sb, true, indent)
            for i in 0..<indent do strings.write_byte(sb, ' ')
            strings.write_string(sb, "Drop\n")
            return 
            
            // strings.write_string(sb, "drop {\n")
            // printASTHelper(ty.value, sb, true, indent + 1)

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
        case ^ASTIf: {
            strings.write_string(sb, "if (\n")
            printASTHelper(ty.cond, sb, false, indent + 1)
            for i in 0..<indent do strings.write_byte(sb, ' ')
            strings.write_string(sb, ") {\n")
            printASTHelper(ty.body, sb, false, indent + 1)
            if ty.elseBlock != nil {
                for i in 0..<indent do strings.write_byte(sb, ' ')
                fmt.sbprintf(sb, "} else {{\n")
                printASTHelper(ty.elseBlock, sb, false, indent + 1)
            }
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

// Used for macros
cloneAST :: proc(ast:^AST) -> AST{
    out : AST = {}
    switch &type in ast^ {
        case ^ASTInputParam: {
            inputParam := new(ASTInputParam)
            inputParam.from = type.from
            inputParam.type = type.type
            inputParam.index = type.index
            out = AST(inputParam)
        }
        case ^ASTBinOp:{
            binOp := new(ASTBinOp)
            binOp.op = type.op
            binOp.rhs = cloneAST(&type.rhs)
            binOp.lhs = cloneAST(&type.lhs)
            out = AST(binOp)
        }
        case ^ASTBlock:{
            block := new(ASTBlock)
            block.nodes = make([dynamic]AST)
            block.outputTypes = make([dynamic]Type)
            for &node in type.nodes {
                append(&block.nodes, cloneAST(&node))
            }
            for ty in type.outputTypes {
                append(&block.outputTypes, ty)
            }
            block.state.vars = make(map[string]Variable)
            for k,&v in type.state.vars {
                block.state.vars[k] = {
                    v.label, v.type,
                    v.updated, v.used,
                    cloneAST(&v.value)
                }
            }
            out = AST(block)
        }
        case ^ASTSyscall0: {
            syscall0 := new(ASTSyscall0)
            syscall0.call = cloneAST(&type.call)
            out = AST(syscall0)
        }
        case ^ASTSyscall1:{
            syscall1 := new(ASTSyscall1)
            syscall1.call = cloneAST(&type.call)
            syscall1.arg1 = cloneAST(&type.arg1)
            out = AST(syscall1)
        }
        case ^ASTSyscall2:{
            syscall2 := new(ASTSyscall2)
            syscall2.call = cloneAST(&type.call)
            syscall2.arg1 = cloneAST(&type.arg1)
            syscall2.arg2 = cloneAST(&type.arg2)
            out = AST(syscall2)
        }
        case ^ASTSyscall3:{
            syscall3 := new(ASTSyscall3)
            syscall3.call = cloneAST(&type.call)
            syscall3.arg1 = cloneAST(&type.arg1)
            syscall3.arg2 = cloneAST(&type.arg2)
            syscall3.arg3 = cloneAST(&type.arg3)
            out = AST(syscall3)
        }
        case ^ASTUnaryOp:{
            unOp := new(ASTUnaryOp)
            unOp.op = type.op
            unOp.value = cloneAST(&type.value)
            out = AST(unOp)
        }
        case ^ASTVarDef:{
            varDef := new(ASTVarDef)
            varDef.ident = type.ident
            varDef.isConst = type.isConst
            varDef.value = cloneAST(&type.value)
            out = AST(varDef)
        }
        case ^ASTDrop:{
            drop := new(ASTDrop)
            drop.value = cloneAST(&type.value)
            out = AST(drop)
        }
        case ^ASTPushLiteral:{
            pushLit := new(ASTPushLiteral)
            pushLit ^= type^
            out = AST(pushLit)
        } 
        case ^ASTVarRef: {
            varRef := new(ASTVarRef)
            varRef.ident = type.ident
            out = AST(varRef)
        }
        case ^ASTProcCall: {
            procCall := new(ASTProcCall)
            procCall.ident = type.ident
            procCall.nargs = type.nargs
            out = AST(procCall)
        }
        case ^ASTIf: {
            iff := new(ASTIf)
            iff.cond = cloneAST(&type.cond)
            iff.body = cloneAST(&type.body)
            iff.elseBlock = cloneAST(&type.elseBlock)
            out = AST(iff)
        }
    }
    return out
}