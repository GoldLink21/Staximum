// Handles changing tokens into AST to be used for code generation
package ast

import "core:fmt"
import "core:os"
import "core:strings"

import "../tokenizer"
import "../types"

SYS_EXIT :: 60

AST :: union #no_nil {
    ^PushLiteral,
    ^UnaryOp,
    ^BinOp,
    ^Syscall1,
}

// Holds value to push
PushIntLit :: distinct int
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

UnaryOp :: struct {
    op: string,
    value: AST
}
PushLiteral :: union {
    int,
    bool,
}
Syscall1 :: struct {
    call: AST,
    value: AST
}


resolveTokens :: proc(tokens:[]tokenizer.Token) -> [dynamic]AST {
    out : [dynamic]AST = make([dynamic]AST)
    for i := 0; i < len(tokens); i += 1 {
        cur := tokens[i]

        // hasNext := i < len(tokens)
        switch cur.type {
            case .IntLit: {
                value : ^PushLiteral = new(PushLiteral)
                value ^= cur.value.(int)

                types.pushType(.Int)
                append(&out, value)
            }
            case .Plus: {
                // Requires 2 things on the stack
                expectArgs(out, "+", 2, cur.loc)
                if !types.applyTransIfValid(types.intrinsics[.Plus]) {
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
                value : ^Syscall1 = new(Syscall1)
                value.call = new(PushLiteral)
                value.call.(^PushLiteral) ^= SYS_EXIT
                value.value = pop(&out)
                append(&out, value)
            }
            case .Syscall1: {
                expectArgs(out, "syscall1", 2, cur.loc)
                value : ^Syscall1 = new(Syscall1)
                value.call = pop(&out)
                value.value = pop(&out)
                append(&out, value)
            }
            case .Dash:  { assert(false, "TODO") }
            case .Ident: { assert(false, "TODO") }
            case .Let:   { assert(false, "TODO") }
            case .StringLit: { /*assert(false, "TODO")*/ }
            case .If:    { assert(false, "TODO") }
            case .Eq:    {
                // Make comparison
            }
            case .BoolLit: {
                value : ^PushLiteral = new(PushLiteral)
                value ^= cur.value.(bool)
                types.pushType(.Bool)
                append(&out, value)
            }
            case .FloatLit: { assert(false, "TODO") }
        }
        // Check just in case
        if len(types.typeStack) != len(out) {
            fmt.printf("WARN: typestack does not match length of output stack")
        }
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
            // fmt.printf("1 %s {{\n", ty.op)
            strings.write_string(sb, ty.op)
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
    }
}

printAST :: proc(ast:[]AST) {
    sb: strings.Builder
    for a in ast {
        printASTHelper(a, &sb)
    }
    fmt.printf("%s\n", strings.to_string(sb))
}