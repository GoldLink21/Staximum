package ast

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
    Eq,
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
    }
    return out
}