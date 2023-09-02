// Creates assembly
package generator

import "../tokenizer"
import "../ast"
import "core:os"
import "core:fmt"
import "core:strings"


generateNasmFromAST :: proc(as : []ast.AST, outFile:string) {
    os.remove(outFile)
    fd, err := os.open(outFile, os.O_CREATE | os.O_WRONLY, 0o777)
    if err == -1 {
        fmt.assertf(false, "Error Opening output assembly")
    }
    defer os.close(fd)
    sb : strings.Builder
    strings.write_string(&sb, "global _start\n_start:\n")
    
    for &a in as {
        generateNasmFromASTHelp(&sb, &a)
    }
    strings.write_string(&sb, "\n   ; Safe exit if it makes it to the end\n   mov rax, 60\n   mov rdi, 0\n   syscall\n")
    os.write_string(fd, strings.to_string(sb))
}

generateNasmFromASTHelp :: proc(sb:^strings.Builder, as: ^ast.AST) {
    using ast
    switch ty in as {
        case ^PushLiteral: {
            strings.write_string(sb, "   push ")
            strings.write_int(sb, ty.(int))
            strings.write_string(sb, "\n")
        }

        case ^BinOp:{
            astIntToRegister2(sb, 
                &ty.lhs, "rax",
                &ty.rhs, "rbx")
            switch ty.op {
                case .Plus: {
                    nasm(sb, "add rax, rbx")
                }
                case .Eq: {
                    astIntToRegister2(sb, 
                        &ty.lhs, "eax",
                        &ty.rhs, "ebx")
                    nasm(sb, "cmp eax, ebx")
                }
            }
            nasm(sb, "push rax")
        }
        case ^UnaryOp: {
            assert(false, "TODO\n")
        }
        case ^Syscall1: {
            astIntToRegister2(sb, 
                &ty.value, "rdi", 
                &ty.call, "rax")
            nasm(sb, "syscall")
            // pushReg(sb, "eax")
        }
    }
}

// Gets an int onto a register from AST
astIntToRegister :: proc(sb: ^strings.Builder, as: ^ast.AST, reg:string) -> bool {
    if lit1, isLit := as.(^ast.PushLiteral); isLit {
        if val1, isInt := lit1.(int); isInt {
            loadRegWithInt(sb, reg, val1)
            return true
        }
    }
    generateNasmFromASTHelp(sb, as)
    popReg(sb, reg)
    return false
}

getLitInt :: proc(as: ^ast.AST) -> (int, bool) {
    lit, isLit := as.(^ast.PushLiteral)
    if !isLit do return 0, false
    return lit.(int)
}

// Gets two ints into registers by either immediate value or generating on the stack
astIntToRegister2 :: proc(sb: ^strings.Builder, ast1:^ast.AST, reg1:string, ast2: ^ast.AST, reg2:string) {
    lit1, isLit1 := getLitInt(ast1)
    lit2, isLit2 := getLitInt(ast2)
    if isLit1 {
        if isLit2 {
            // Load both immediately
            loadRegWithInt(sb, reg1, lit1)
            loadRegWithInt(sb, reg2, lit2)
        } else {
            // Generate second then pop second and load first 
            generateNasmFromASTHelp(sb, ast2)
            popReg(sb, reg2)
            loadRegWithInt(sb, reg1, lit1)
        }
    } else {
        if isLit2 {
            // Generate first then pop first and load second 
            generateNasmFromASTHelp(sb, ast1)
            popReg(sb, reg1)
            loadRegWithInt(sb, reg2, lit2)
        } else {
            // Generate both
            generateNasmFromASTHelp(sb, ast1)
            generateNasmFromASTHelp(sb, ast2)
    
            popReg(sb, reg2)
            popReg(sb, reg1)
        }
    }
}

nasm :: proc(sb : ^strings.Builder, instruction : string) {
    strings.write_string(sb, "   ")
    strings.write_string(sb, instruction)
    strings.write_byte(sb, '\n')
} 

loadRegWithInt :: proc(sb: ^strings.Builder, reg:string, value:int) {
    strings.write_string(sb, "   mov ")
    strings.write_string(sb, reg)
    strings.write_string(sb, ", ")
    strings.write_int(sb, value)
    strings.write_string(sb, "\n")
}

popReg :: proc(sb: ^strings.Builder, reg:string) {
    strings.write_string(sb, "   pop ")
    strings.write_string(sb, reg)
    strings.write_string(sb, "\n")
}

pushReg :: proc(sb: ^strings.Builder, reg:string) {
    strings.write_string(sb, "   push ")
    strings.write_string(sb, reg)
    strings.write_string(sb, "\n")
}

pushInt :: proc(sb: ^strings.Builder, val:int) {

}