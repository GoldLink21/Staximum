// Handles changing tokens into AST to be used for code generation
//  and also does the type checking during
package ast

import "core:fmt"
import "core:os"
import "core:strings"

import "../tokenizer"
import "../types"

SYS_EXIT :: 60
SYS_WRITE :: 1

ASTState :: struct {

}

AST :: union #no_nil {
    ^PushLiteral,
    ^UnaryOp,
    ^BinOp,
    ^Syscall1,
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
    .CastFloatToInt = "(Float)",
    .CastIntToFloat = "(Int)",
}
UnaryOp :: struct {
    op: UnaryOps,
    value: AST
}
PushLiteral :: union {
    int,
    bool,
    // Strings should push the label, then the length
    string,
}
Syscall1 :: struct {
    call: AST,
    value: AST,
}
// Used for SYS_WRITE
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

resolveTokens :: proc(tokens:[]tokenizer.Token) -> [dynamic]AST {
    out := make([dynamic]AST)
    variables := make(map[string]Variable)
    numDrops := 0
    for i := 0; i < len(tokens); i += 1 {
        cur := tokens[i]

        // hasNext := i < len(tokens)
        switch cur.type {
            case .IntLit: {
                value : ^PushLiteral = new(PushLiteral)
                value ^= cur.value.(int)

                pushType(.Int)
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
                expectArgs(out, "+", 2, cur.loc)
                if !applyTransIfValid(types.intrinsics[.Plus]) {
                    fmt.printf("Invalid argument types for op '+'\n")
                    os.exit(1)
                }
                // Optimize out simple operations
                value : ^BinOp = new(BinOp)
                value.lhs = pop(&out)
                value.rhs = pop(&out)
                value.op = .Plus
                append(&out, value)
            }
            case .Exit: {
                expectArgs(out, "exit", 1, cur.loc)
                expectTypes({.Int})
                value : ^Syscall1 = new(Syscall1)
                value.call = new(PushLiteral)
                value.call.(^PushLiteral) ^= SYS_EXIT
                value.value = pop(&out)
                append(&out, value)
                // append(&out, new(Drop))
            }
            case .Syscall1: {
                expectArgs(out, "syscall1", 2, cur.loc)
                expectTypes({.Int, .Any})
                pushType(.Int)
                value : ^Syscall1 = new(Syscall1)
                value.call = pop(&out)
                value.value = pop(&out)
                append(&out, value)
            }
            case .Syscall3: { 
                expectArgs(out, "syscall3", 4, cur.loc)
                expectTypes({.Int, .Any, .Any, .Any})
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
                expectArgs(out, "drop", 1, cur.loc)
                popType()
                append(&out, new(Drop))
                // numDrops += 1
            }
            case .Macro: {
                
            }
            case .Print: {
                // Should this instead become a proc?
                expectArgs(out, "print", 2, cur.loc)
                expectTypes({.String, .Int})

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
            case .If: { assert(false, "TODO") }
            case .Eq: { assert(false, "TODO") }
            case .End: { assert(false, "TODO") }
            case .Let: { assert(false, "TODO") }
            case .Bang: { assert(false, "TODO") }
            case .Dash: { assert(false, "TODO") }
            case .Ident: { assert(false, "TODO") }
            case .OParen: {
                // Check for type casting
                assert(false, "TODO")
            }
            case .CParen: { assert(false, "TODO") }
            case .FloatLit: { assert(false, "TODO") }
        }
        // Check just in case
        /*
        if len(typeStack) != len(out) - numDrops {
            fmt.printf("WARN: typestack does not match length of output stack\n")
            for type in typeStack {
                fmt.print(type)
                fmt.println()
            }
        }*/
    }
    return out
}

expectArgs :: proc(out : [dynamic]AST, label:string, numArgs:int, loc:tokenizer.Location) {
    if len(out) < numArgs {
        tokenizer.printLoc(loc)
        fmt.printf("%s requries %d argument%s\n", label, numArgs, (numArgs)==1?"":"s")
        os.exit(1)
    }
}

printASTHelper :: proc(ast: AST, sb:^strings.Builder, inList:=false, indent:=0) {
    // indent
    for i in 0..<indent do strings.write_byte(sb, ' ')
    switch ty in ast {
        case ^PushLiteral: {
            switch lit in ty {
                case int: {
                    // fmt.printf("%d\n", lit)
                    strings.write_int(sb, int(lit))
                }
                case bool: {
                    // bool is basically just an int, right?
                    strings.write_int(sb, int(lit))
                }
                case string: {
                    strings.write_string(sb, lit)
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
        case ^Syscall1: {
            strings.write_string(sb, "syscall ")
            strings.write_string(sb, " {\n")
            printASTHelper(ty.call, sb, true, indent + 1)
            printASTHelper(ty.value, sb, false, indent + 1)
            strings.write_string(sb, "}\n")
        }
        case ^Syscall3: {
            strings.write_string(sb, "syscall ")
            strings.write_string(sb, " {\n")
            printASTHelper(ty.call, sb, true, indent + 1)
            printASTHelper(ty.arg1, sb, true, indent + 1)
            printASTHelper(ty.arg2, sb, true, indent + 1)
            printASTHelper(ty.arg3, sb, false, indent + 1)
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