// Handles changing tokens into AST to be used for code generation
//  and also does the type checking during
package ast

import "core:fmt"
import "core:os"
import "core:strings"

import "../tokenizer"
import "../types"
import "../util"

SYS_EXIT :: 60
SYS_WRITE :: 1

ASTState :: struct {
    macros:map[string]Macro,
    // vars: set[string]
}

AST :: union #no_nil {
    ^PushLiteral,
    ^UnaryOp,
    ^BinOp,
    ^Syscall0,
    ^Syscall1,
    ^Syscall2,
    ^Syscall3,
    ^Drop,
}

// Holds value to push
PushIntLit :: distinct int
Drop :: distinct rawptr
// Holds what syscall number to use
BinOp :: struct {
    op: BinOps,
    lhs, rhs: AST
}
// Different possible binary operations
BinOps :: enum {
    Plus,
    Minus,
    Eq,
}
BinOpsString : map[BinOps]string = {
    .Plus = "+",
    .Eq = "=",
}
UnaryOps :: enum {
    CastFloatToInt,
    CastIntToFloat
}
UnaryOpsString : map[UnaryOps]string = {
    .CastFloatToInt = "(Int)",
    .CastIntToFloat = "(Float)",
}
UnaryOp :: struct {
    op: UnaryOps,
    value: AST
}
PushLiteral :: union {
    int,
    bool,
    f64,
    // Strings should push the label, then the length
    string,
}
Syscall0 :: struct {
    call: AST,
}
Syscall1 :: struct {
    call: AST,
    arg1: AST,
}
Syscall2 :: struct {
    call: AST,
    arg1: AST,
    arg2: AST,
}
Syscall3 :: struct {
    call: AST,
    arg1: AST,
    arg2: AST,
    arg3: AST,
}
VarDef :: struct {
    ident : string,
    value : AST,
    // Cannot be reassigned to
    isConst : bool,
}
// Reference for a var. Can become a write or read with different ops
VarRef :: struct {
    ident: string,
    value : AST,
}

Variable :: struct {
    label:string,
    type:types.Type,
    // If written back into, then cannot optimize out
    //  and must be put into .bss
    redefined: bool,
}

Macro :: struct {

}

resolveTokens :: proc(tokens:[]tokenizer.Token) -> (out:[dynamic]AST, err:util.ErrorMsg) {
    out = make([dynamic]AST)
    variables := make(map[string]Variable)
    tw : TokWalk = { tokens, 0 }
    for cur := curr(&tw); curOk(&tw); cur,_ = next(&tw) {
        switch cur.type {
            case .Error: {
                return out, "Error Token found\n"
            }
            case .IntLit: {
                value : ^PushLiteral = new(PushLiteral)
                value ^= cur.value.(int)

                pushType(.Int)
                append(&out, value)
            }
            case .FloatLit: { 
                value : ^PushLiteral = new(PushLiteral)
                value ^= cur.value.(f64)
                
                pushType(.Float)
                append(&out, value)
            }
            case .StringLit: { 
                // Length
                length : ^PushLiteral = new(PushLiteral)
                length ^= len(cur.value.(string))
                pushType(.Int)
                append(&out, length)  

                // Label
                value : ^PushLiteral = new(PushLiteral)
                value ^= cur.value.(string)
                pushType(.String)
                append(&out, value)  
            }
            case .BoolLit: {
                value : ^PushLiteral = new(PushLiteral)
                value ^= cur.value.(bool)
                pushType(.Bool)
                append(&out, value)
            }
            case .Plus: {
                // Requires 2 things on the stack
                expectArgs(out, "+", {}, cur.loc) or_return
                // Manual type check
                if len(typeStack) < 2 {
                    return out, "Op '+' requires 2 inputs"
                }
                // TODO: Add float support
                if !hasTypes({.Int, .Int}) {
                    return out, "Invalid argument types for op '+'\n"
                }
                // Types must match, so can just drop one of type
                popType()
                // Optimize out simple operations
                value : ^BinOp = new(BinOp)
                value.lhs = pop(&out)
                value.rhs = pop(&out)
                // TODO: Consider changing to PlusInt and PlusFloat 
                value.op = .Plus
                append(&out, value)
            }
            case .Dash: { 
                // Requires 2 things on the stack
                expectArgs(out, "-", {}, cur.loc) or_return
                // Manual type check after
                if len(typeStack) < 2 {
                    return out, "Op '-' requires 2 inputs"
                }
                // TODO: Add float support
                if !hasTypes({.Int, .Int}) {
                    return out, "Invalid argument types for op '-'\n"
                }
                // Types must match, so can just drop one of type
                popType()
                // Optimize out simple operations
                value : ^BinOp = new(BinOp)
                value.lhs = pop(&out)
                value.rhs = pop(&out)
                // TODO: Consider MinusInt and MinusFloat ops
                value.op = .Minus
                append(&out, value)
            }
            case .Exit: {
                expectArgs(out, "exit", 
                    {.Int}, cur.loc) or_return
                // Break even
                // popType()
                // pushType(.Int)

                value : ^Syscall1 = new(Syscall1)
                value.call = new(PushLiteral)
                value.call.(^PushLiteral) ^= SYS_EXIT
                value.arg1 = pop(&out)
                append(&out, value)
                // Consider dropping after exit calls cause value will never be used
                // append(&out, new(Drop))
            }
            case .Syscall0: {
                expectArgs(out, "syscall0", 
                    {.Int}, cur.loc) or_return
                pushType(.Int)
                value : ^Syscall0 = new(Syscall0)
                value.call = pop(&out)
                append(&out, value)
            }
            case .Syscall1: {
                expectArgs(out, "syscall1", 
                    {.Int, .Any}, cur.loc) or_return
                pushType(.Int)
                value : ^Syscall1 = new(Syscall1)
                value.call = pop(&out)
                value.arg1 = pop(&out)
                append(&out, value)
            }
            case .Syscall2: {
                expectArgs(out, "syscall2", 
                    {.Int, .Any, .Any}, cur.loc) or_return
                pushType(.Int)
                value := new(Syscall2)
                value.call = pop(&out)
                value.arg1 = pop(&out)
                value.arg2 = pop(&out)
                append(&out, value)
            }
            case .Syscall3: { 
                expectArgs(out, "syscall3", 
                    {.Int, .Any, .Any, .Any}, cur.loc) or_return
                pushType(.Int)
                value := new(Syscall3)
                value.call = pop(&out)
                value.arg1 = pop(&out)
                value.arg2 = pop(&out)
                value.arg3 = pop(&out)
                append(&out, value)
                // assert(false, "TODO") 
            }
            case .Drop: {
                expectArgs(out, "drop", {}, cur.loc) or_return
                popType()
                append(&out, new(Drop))
            }
            case .Macro: {
                return out, "TODO"
            }
            case .Puts: {
                // Should this instead become a proc?
                expectArgs(out, "puts", 
                    {.String, .Int}, cur.loc) or_return

                value : ^Syscall3 = new(Syscall3)
                value.call = new(PushLiteral)
                value.call.(^PushLiteral) ^= SYS_WRITE
                // stdout
                value.arg1 = new(PushLiteral)
                value.arg1.(^PushLiteral) ^= 1

                value.arg2 = pop(&out)
                value.arg3 = pop(&out)
                append(&out, value)
            }
            case .Gt: { 
                return out, "> AST TODO\n"
            }
            case .If: { 
                return out, "< AST TODO\n"
            }
            case .Eq: {
                return out, "= AST TODO\n"
            }
            case .End: { 
                return out, "end AST TODO\n"
            }
            case .Let: { 
                return out, "let AST TODO\n"
            }
            case .Bang: { 
                return out, "! AST TODO\n"
            }
            case .Type: { 
                return out, "(type) AST TODO\n"
            }
            case .Colon: { 
                return out, ": AST TODO\n"
            }
            case .Ident: { 
                return out, "Rand Ident AST TODO\n"
            }
            case .OParen: {
                // Check for type casting
                if n, ok := peek(&tw); ok && n.type == .Type {
                    typeToken, _ := next(&tw)
                    typeValue := typeToken.value.(types.Type)
                    expectNext(&tw, .CParen)
                    // Allow only casting from int to float and float to int for now

                    // Ignore if casting to the same type
                    if peekType() == typeValue do continue
                    if peekType() == .Int && typeValue == .Float {
                        popType()
                        pushType(.Float)
                        unop := new(UnaryOp)
                        unop.op = .CastIntToFloat
                        unop.value = pop(&out)
                        append(&out, unop)
                        continue
                    } else if peekType() == .Float && typeValue == .Int {
                        popType()
                        pushType(.Int)
                        unop := new(UnaryOp)
                        unop.op = .CastFloatToInt
                        unop.value = pop(&out)
                        append(&out, unop)
                        continue
                    }
                    return out, "Cannot currently cast to and from anything except int and float"
                }
                return out, "Invalid character after ("
            }
            case .CParen: { 
                return out, ") AST TODO\n"
            }
            case .OBrace: {
                return out, "{ AST TODO\n"
            }
            case .CBrace: {
                return out, "} AST TODO\n"
            }
        }
    }
    return out, nil
}

// Will eat types passed in
expectArgs :: proc(out : [dynamic]AST, label:string, types:[]Type, loc:tokenizer.Location) -> util.ErrorMsg {
    if len(out) < len(types) {
        return util.locStr(loc, 
            "%s requries %d argument%s", 
            label, len(types), 
            (len(types))==1?"":"s"
        )
    }
    return expectTypes(types, loc)
}

printASTHelper :: proc(ast: AST, sb:^strings.Builder, inList:=false, indent:=0) {
    // indent
    for i in 0..<indent do strings.write_byte(sb, ' ')
    switch ty in ast {
        case ^PushLiteral: {
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
            if inList do strings.write_byte(sb, ',')
            strings.write_byte(sb, '\n')
        }
        case ^BinOp: {
            // fmt.printf("2 %s {\n", ty.op)
            strings.write_string(sb, BinOpsString[ty.op])
            strings.write_string(sb, " {\n")
            printASTHelper(ty.lhs, sb, true, indent + 1)
            printASTHelper(ty.rhs, sb, false, indent + 1)
            for i in 0..<indent do strings.write_byte(sb, ' ')
            strings.write_string(sb, "}\n")
        }
        case ^UnaryOp: {
            strings.write_string(sb, UnaryOpsString[ty.op])
            strings.write_string(sb, " {\n")           
            printASTHelper(ty.value, sb, false, indent + 1)
            for i in 0..<indent do strings.write_byte(sb, ' ')
            strings.write_string(sb, "}\n")
        }
        case ^Syscall0: {
            strings.write_string(sb, "syscall {\n")
            printASTHelper(ty.call, sb, false, indent + 1)
            for i in 0..<indent do strings.write_byte(sb, ' ')
            strings.write_string(sb, "}\n")

        }
        case ^Syscall1: {
            strings.write_string(sb, "syscall {\n")
            printASTHelper(ty.call, sb, true, indent + 1)
            printASTHelper(ty.arg1, sb, false, indent + 1)
            for i in 0..<indent do strings.write_byte(sb, ' ')
            strings.write_string(sb, "}\n")
        }
        case ^Syscall2: {
            strings.write_string(sb, "syscall {\n")
            printASTHelper(ty.call, sb, true, indent + 1)
            printASTHelper(ty.arg1, sb, true, indent + 1)
            printASTHelper(ty.arg2, sb, false, indent + 1)
            for i in 0..<indent do strings.write_byte(sb, ' ')
            strings.write_string(sb, "}\n")
        }
        case ^Syscall3: {
            strings.write_string(sb, "syscall {\n")
            printASTHelper(ty.call, sb, true, indent + 1)
            printASTHelper(ty.arg1, sb, true, indent + 1)
            printASTHelper(ty.arg2, sb, true, indent + 1)
            printASTHelper(ty.arg3, sb, false, indent + 1)
            for i in 0..<indent do strings.write_byte(sb, ' ')
            strings.write_string(sb, "}\n")
        }
        case ^Drop: {
            strings.write_string(sb, "Drop\n")
        }
    }
}

printAST :: proc(ast:[]AST) {
    sb: strings.Builder
    for a in ast {
        printASTHelper(a, &sb)
    }
    fmt.printf("%s\n", strings.to_string(sb))
}