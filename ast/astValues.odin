package ast

import "../types"

// Holds value to push
ASTDrop :: distinct rawptr
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
    CastIntToFloat
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

Macro :: struct {
    inputs:[]Type,
    outputs:[]Type,
    ast:[]AST
}

newIntLit :: proc(val:int) -> (^ASTPushLiteral) {
    ret := new(ASTPushLiteral)
    ret ^= val
    return ret
}