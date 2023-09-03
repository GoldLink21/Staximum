// Creates assembly
package generator

import "../tokenizer"
import "../ast"
import "core:os"
import "core:fmt"
import "core:strings"

// Stores the state of the ASM as its generated
ASMContext :: struct {
    // Maps string value to label name
    stringLits : map[string]string,
}

generateNasmFromAST :: proc(as : []ast.AST, outFile:string) {
    os.remove(outFile)
    fd, err := os.open(outFile, os.O_CREATE | os.O_WRONLY, 0o777)
    if err == -1 {
        fmt.assertf(false, "Error Opening output assembly")
    }
    defer os.close(fd)
    sb : strings.Builder
    strings.write_string(&sb, "   section .text\nglobal _start\n_start:\n")
    
    ctx : ASMContext = {}

    for &a in as {
        generateNasmFromASTHelp(&sb, &ctx, &a)
    }
    strings.write_string(&sb, "\n   ; Safe exit if it makes it to the end\n   mov rax, 60\n   mov rdi, 0\n   syscall\n")
    generateDataSection(&sb, &ctx)
    
    os.write_string(fd, strings.to_string(sb))
}

generateNasmFromASTHelp :: proc(sb:^strings.Builder, ctx: ^ASMContext, as: ^ast.AST) {
    using ast
    switch ty in as {
        case ^PushLiteral: {
            switch litType in ty {
                case bool, int: {
                    strings.write_string(sb, "   push ")
                    strings.write_int(sb, ty.(int))
                    strings.write_string(sb, "\n")
                }
                case string: {
                    if litType not_in ctx.stringLits {
                        // Need to generate
                        ctx.stringLits[litType] = fmt.aprintf("stringLit_%d", len(ctx.stringLits))
                    }
                    // Reference
                    pushReg(sb, ctx.stringLits[litType])
                }
            }
            
        }

        case ^BinOp:{
            astIntToRegister2(sb, ctx,
                &ty.lhs, "rax",
                &ty.rhs, "rbx")
            switch ty.op {
                case .Plus: {
                    nasm(sb, "add rax, rbx")
                }
                case .Eq: {
                    astIntToRegister2(sb, ctx,
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
            astIntToRegister2(sb, ctx,
                &ty.value, "rdi", 
                &ty.call, "rax")
            nasm(sb, "syscall")
            // pushReg(sb, "eax")
        }
        case ^ast.Syscall3: {
            generateNasmFromASTHelp(sb, ctx, &ty.arg3)
            generateNasmFromASTHelp(sb, ctx, &ty.arg2)
            generateNasmFromASTHelp(sb, ctx, &ty.arg1)
            generateNasmFromASTHelp(sb, ctx, &ty.call)
            popReg(sb, "rax")
            popReg(sb, "rdi")
            popReg(sb, "rsi")
            popReg(sb, "rdx")
            nasm(sb, "syscall")
        }
    }
}

// Gets an int onto a register from AST
astIntToRegister :: proc(sb: ^strings.Builder, ctx:^ASMContext, as: ^ast.AST, reg:string) -> bool {
    if lit1, isLit := as.(^ast.PushLiteral); isLit {
        if val1, isInt := lit1.(int); isInt {
            loadRegWithInt(sb, reg, val1)
            return true
        }
    }
    generateNasmFromASTHelp(sb, ctx, as)
    popReg(sb, reg)
    return false
}

getLitInt :: proc(as: ^ast.AST) -> (int, bool) {
    lit, isLit := as.(^ast.PushLiteral)
    if !isLit do return 0, false
    return lit.(int)
}

// Gets two ints into registers by either immediate value or generating on the stack
astIntToRegister2 :: proc(sb: ^strings.Builder, ctx:^ASMContext, ast1:^ast.AST, reg1:string, ast2: ^ast.AST, reg2:string) {
    lit1, isLit1 := getLitInt(ast1)
    lit2, isLit2 := getLitInt(ast2)
    if isLit1 {
        if isLit2 {
            // Load both immediately
            loadRegWithInt(sb, reg1, lit1)
            loadRegWithInt(sb, reg2, lit2)
        } else {
            // Generate second then pop second and load first 
            generateNasmFromASTHelp(sb, ctx, ast2)
            popReg(sb, reg2)
            loadRegWithInt(sb, reg1, lit1)
        }
    } else {
        if isLit2 {
            // Generate first then pop first and load second 
            generateNasmFromASTHelp(sb, ctx, ast1)
            popReg(sb, reg1)
            loadRegWithInt(sb, reg2, lit2)
        } else {
            // Generate both
            generateNasmFromASTHelp(sb, ctx, ast1)
            generateNasmFromASTHelp(sb, ctx, ast2)
    
            popReg(sb, reg2)
            popReg(sb, reg1)
        }
    }
}

// Adds an indented instruction with a newline
nasm :: proc(sb : ^strings.Builder, instruction : string) {
    fmt.sbprintf(sb, "   %\n", instruction)
} 
// Loads an integer into a register
loadRegWithInt :: proc(sb: ^strings.Builder, reg:string, value:int) {
    fmt.sbprintf(sb, "   mov %s, %d\n", reg, value)
}
// Loads a register with label
loadRegWithLabel :: proc(sb: ^strings.Builder, reg:string, label:string) {
    fmt.sbprintf(sb, "   mov %s, %s\n", reg, label)
}
// Loads value into a register
loadReg :: proc{loadRegWithInt, loadRegWithLabel}

// Pops value into register
popReg :: proc(sb: ^strings.Builder, reg:string) {
    fmt.sbprintf(sb, "   pop %s\n", reg)
}

// Pushes value in register
pushReg :: proc(sb: ^strings.Builder, reg:string) {
    fmt.sbprintf(sb, "   push %s\n", reg)
}

generateDataSection :: proc(sb:^strings.Builder, ctx:^ASMContext) {
    // Nothing to add
    if len(ctx.stringLits) == 0 do return
    strings.write_byte(sb, '\n')
    nasm(sb, "section .data")
    for k, v in ctx.stringLits {
        strings.write_string(sb, v)
        strings.write_string(sb, ": db \'")
        strings.write_string(sb, k)
        strings.write_string(sb, "\',10\n")
        // Should I preload their lengths too?
    }
}