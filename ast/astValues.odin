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
    Lt, Le,
    Gt, Ge
}
ASTBinOpsString : map[ASTBinOps]string = {
    .Plus = "+",
    .Eq = "=",
    .Ne = "!=",
    .Minus = "-",
    .Lt = "<",
    .Gt = ">",
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
    /* Forth uses a separate stack for floats.
        Should I figure that out? */
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
ASTProcReturn :: struct {
    type: types.Type,
    index: int,
    from: string,
}
/* Syscalls are broken up into how many arguments they have.
    This may seem bad, but with at most 7, it removes all 
    ambiguity with how many params to use for syscall*/
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
/* Not needed yet. Will implement then
ASTSyscall4 :: struct {
    call: AST,
    arg1: AST,
    arg2: AST,
    arg3: AST,
    arg4: AST,
}
ASTSyscall5 :: struct {
    call: AST,
    arg1: AST,
    arg2: AST,
    arg3: AST,
    arg4: AST,
    arg5: AST,
}
ASTSyscall6 :: struct {
    call: AST,
    arg1: AST,
    arg2: AST,
    arg3: AST,
    arg4: AST,
    arg5: AST,
    arg6: AST,
}
*/

ASTVarDecl :: struct {
    ident : string,
    // In the global scope
    isGlobal: bool,
    type: types.Type,
}
// Reference for a var. Can become a write or read with different ops
ASTVarRef :: struct {
    ident: string,
    isGlobal: bool,
}
// x 5 ! // Setting x to 5
ASTVarWrite :: struct {
    ident: string,
    value: AST,
    isGlobal: bool,
}
// x @ // gives value of x
ASTVarRead :: struct {
    ident: string,
    isGlobal: bool,
}
// Stores nargs for simplicity later
ASTProcCall :: struct {
    ident: string,
    nargs: int,
}
ASTDup  :: struct {}
ASTSwap :: struct {}
ASTRot  :: struct {}
ASTNip  :: struct {}
ASTOver :: struct {}

ASTIf :: struct {
    cond, body: AST,
    jumpType:JumpType,
    // Can be nil if no else
    elseBlock: AST,
}
ASTWhile :: struct {
    cond:[dynamic]AST, 
    body: AST,
    jumpType:JumpType,
    inputTypes: [dynamic]Type
}
// Precalculated to make generation easier
JumpType :: enum {
    Eq, Ne, 
    Lt, Gt,
    // Gte, Lte,
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

printASTList :: proc(ast:[dynamic]AST){
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
            strings.write_string(sb, "drop\n")
            return 
        }
        case ^ASTVarRef: {
            fmt.sbprintf(sb, "Ref%s \"%s\"\n", ty.isGlobal?" global":"", ty.ident)
            return
        }
        case ^ASTBlock: {
            strings.write_string(sb, "{\n")
            for as in ty.nodes {
                printASTHelper(as, sb, true, indent + 1)
            }
        }
        case ^ASTVarDecl: {
            fmt.sbprintf(sb, "let %s%s\n",ty.isGlobal?"global ":"", ty.ident)
            return
        }
        case ^ASTProcCall: {
            fmt.sbprintf(sb, "%s(%d args)\n", ty.ident, ty.nargs)
            return
        }
        case ^ASTDup: {
            fmt.sbprintf(sb, "dup\n")
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
        case ^ASTWhile: {
            strings.write_string(sb, "while (\n")
            for n in ty.cond {
                printASTHelper(n, sb, false, indent + 1)
            }
            for i in 0..<indent do strings.write_byte(sb, ' ')
            strings.write_string(sb, ") {\n")
            printASTHelper(ty.body, sb, false, indent + 1)
        }
        case ^ASTSwap: {
            fmt.sbprintf(sb, "swap\n")
            return
        }
        case ^ASTRot: {
            fmt.sbprintf(sb, "rot\n")
            return
        }
        case ^ASTNip: {
            fmt.sbprintf(sb, "nip\n")
            return
        }
        case ^ASTOver: {
            fmt.sbprintf(sb, "over\n")
            return
        }
        case ^ASTVarRead: {
            fmt.sbprintf(sb, "@ %s'%s'\n", ty.isGlobal? "global ":"", ty.ident)
            return
        }
        case ^ASTVarWrite: {
            fmt.sbprintf(sb, "! %s'%s' {{\n", ty.isGlobal?"global ":"", ty.ident)
            printASTHelper(ty.value, sb, false, indent + 1)
        }
        case ^ASTProcReturn: {
            fmt.sbprintf(sb, "return %d from '%s'\n", ty.index, ty.from)
            return
        }
    }
    for i in 0..<indent do strings.write_byte(sb, ' ')
    strings.write_string(sb, "}\n")
}


printProgram :: proc(program:^ASTProgram) {
    sb: strings.Builder

    for name, glob in program.globalVars {
        fmt.sbprintf(&sb, "let %s =", name)
        printASTHelper(glob.value, &sb, false, 1)
    }
    for k, mac in program.macros {
        fmt.sbprintf(&sb, "macro %s :", k)
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
        fmt.sbprintf(&sb, "proc %s :", n)
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

cloneASTList :: proc(ast:^[dynamic]AST) -> [dynamic]AST {
    out := make([dynamic]AST)
    for &a in ast {
        append(&out, cloneAST(&a))
    }
    return out
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
        case ^ASTVarDecl:{
            varDef := new(ASTVarDecl)
            varDef.ident = type.ident
            varDef.isGlobal = type.isGlobal
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
            varRef.isGlobal = type.isGlobal
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
            iff.jumpType = type.jumpType
            out = AST(iff)
        }
        case ^ASTWhile: {
            while := new(ASTWhile)
            while.cond = cloneASTList(&type.cond)
            while.body = cloneAST(&type.body)
            while.jumpType = type.jumpType
            out = AST(while)
        }
        case ^ASTDup: {
            out = new(ASTDup)
        }
        case ^ASTSwap: {
            out = new(ASTSwap)
        }
        case ^ASTRot: {
            out = new(ASTRot)
        }
        case ^ASTNip: {
            out = new(ASTNip)
        }
        case ^ASTOver: {
            out = new(ASTOver)
        }
        case ^ASTVarRead: {
            varRead := new(ASTVarRead)
            varRead.ident = type.ident[:]
            varRead.isGlobal = type.isGlobal
            out = varRead
        }
        case ^ASTVarWrite: {
            varWrite := new(ASTVarWrite)
            varWrite.ident = type.ident[:]
            varWrite.value = cloneAST(&type.value)
            varWrite.isGlobal = type.isGlobal
            out = varWrite
        }
        case ^ASTProcReturn: {
            procRet := new(ASTProcReturn)
            procRet.from = type.from
            procRet.type = type.type
            procRet.index = type.index
            out = AST(procRet)
        }
    }
    return out
}

astListEq :: proc(a, b:[dynamic]AST) -> bool {
    if len(a) != len(b) do return false
    for i in 0..<len(a) {
        if !astEq(a[i], b[i]) do return false
    }
    return true
}

astEq :: proc(a, b: AST) -> bool {
    switch &type in a {
        case ^ASTInputParam: {
            ip, isInputParam := b.(^ASTInputParam)
            return isInputParam &&
                type.from == ip.from &&
                type.index == ip.index &&
                type.type == ip.type
        }
        case ^ASTBinOp:{
            bo, isBinOp := b.(^ASTBinOp)
            return isBinOp &&
                type.op == bo.op &&
                astEq(type.lhs, bo.lhs) &&
                astEq(type.rhs, bo.rhs)
        }
        case ^ASTBlock:{
            bl, isBlock := b.(^ASTBlock)
            return isBlock &&
                astListEq(type.nodes, bl.nodes)
                // Could check output types, but if all inside nodes
                //  match then, they should match
        }
        case ^ASTSyscall0: {
            sc0, isSC0 := b.(^ASTSyscall0)
            return isSC0 &&
                astEq(type.call, sc0.call)

        }
        case ^ASTSyscall1:{
            sc1, isSC1 := b.(^ASTSyscall1)
            return isSC1 &&
                astEq(type.call, sc1.call) && 
                astEq(type.arg1, sc1.arg1)
        }
        case ^ASTSyscall2:{
            sc2, isSC2 := b.(^ASTSyscall2)
            return isSC2 &&
                astEq(type.call, sc2.call) && 
                astEq(type.arg1, sc2.arg1) &&
                astEq(type.arg2, sc2.arg2)

        }
        case ^ASTSyscall3:{
            sc3, isSC3 := b.(^ASTSyscall3)
            return isSC3 &&
                astEq(type.call, sc3.call) && 
                astEq(type.arg1, sc3.arg1) &&
                astEq(type.arg2, sc3.arg2) &&
                astEq(type.arg3, sc3.arg3)

        }
        case ^ASTUnaryOp:{
            uo, isUnaryOp := b.(^ASTUnaryOp)
            return isUnaryOp &&
                type.op == uo.op &&
                astEq(type.value, uo.value)
        }
        case ^ASTVarDecl:{
            vd, isVarDecl := b.(^ASTVarDecl)
            return isVarDecl &&
                type.ident == vd.ident &&
                type.isGlobal == vd.isGlobal
        }
        case ^ASTDrop:{
            d, isDrop := b.(^ASTDrop)
            return isDrop &&
                astEq(type.value, d.value)
        }
        case ^ASTPushLiteral:{
            pl, isPushLit := b.(^ASTPushLiteral)
            return isPushLit &&
                type == pl
        } 
        case ^ASTVarRef: {
            vr, isVarRef := b.(^ASTVarRef)
            return isVarRef &&
                type.isGlobal == vr.isGlobal &&
                type.ident == vr.ident
        }
        case ^ASTProcCall: {
            pc, isProcCall := b.(^ASTProcCall)
            return isProcCall &&
                type.nargs == pc.nargs &&
                type.ident == pc.ident
        }
        case ^ASTIf: {
            i, isIf := b.(^ASTIf)
            return isIf &&
                type.jumpType == i.jumpType && 
                astEq(type.cond, i.cond) &&
                astEq(type.body, i.body) &&
                astEq(type.elseBlock, i.elseBlock)
        }
        case ^ASTWhile: {
            w, isWhile := b.(^ASTWhile)
            return isWhile &&
                type.jumpType == w.jumpType &&
                astListEq(type.cond, w.cond) &&
                astEq(type.body, w.body)
        }
        case ^ASTDup: {
            _, isDup := b.(^ASTDup)
            return isDup
        }
        case ^ASTSwap: {
            _, isSwap := b.(^ASTSwap)
            return isSwap
        }
        case ^ASTRot: {
            _, isRot := b.(^ASTRot)
            return isRot
        }
        case ^ASTNip: {
            _, isNip := b.(^ASTNip)
            return isNip
        }
        case ^ASTOver: {
            _, isOver := b.(^ASTOver)
            return isOver
        }
        case ^ASTVarRead: {
            vr, isRead := b.(^ASTVarRead)
            return isRead &&
                type.ident == vr.ident &&
                type.isGlobal == vr.isGlobal
        }
        case ^ASTVarWrite: {
            vw, isWrite := b.(^ASTVarWrite)
            return isWrite && 
                type.ident == vw.ident && 
                type.isGlobal != vw.isGlobal &&
                astEq(type.value, vw.value)
        }
        case ^ASTProcReturn: {
            pr, isProcRet := b.(^ASTProcReturn)
            return isProcRet &&
                type.from == pr.from &&
                type.index == pr.index &&
                type.type == pr.type 
        }
        case nil: {
            return b == nil
        }
    }
    panic("Checking AST equality did not catch all types\n")
}