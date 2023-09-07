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
    // Float labels
    floatLits : map[f64]string,
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
    
    generateBSSSection(&sb, &ctx)
    os.write_string(fd, strings.to_string(sb))
}

// Takes a string value and generates a label for it if one doen't already exist
getStringLabel :: proc(ctx:^ASMContext, str:string) -> string {
    if str not_in ctx.stringLits {
        // Need to generate
        ctx.stringLits[str] = fmt.aprintf("stringLit_%d", len(ctx.stringLits))
    }
    return ctx.stringLits[str]
}
getFloatLabel :: proc(ctx:^ASMContext, flt:f64) -> string {
    if flt not_in ctx.floatLits {
        ctx.floatLits[flt] = fmt.aprintf("floatLit_%d", len(ctx.floatLits))
    }
    return ctx.floatLits[flt]
}

generateNasmFromASTHelp :: proc(sb:^strings.Builder, ctx: ^ASMContext, as: ^ast.AST) {
    using ast
    switch ty in as {
        case ^PushLiteral: {
            switch litType in ty {
                case int: {
                    fmt.sbprintf(sb, "   push %d\n", litType)
                }
                case f64: {
                    assert(false, "TODO")
                }
                case bool: {
                    fmt.sbprintf(sb, "   push %d\n", int(litType))
                }
                case string: {
                    pushReg(sb, getStringLabel(ctx, litType))
                }
            }
        }

        case ^BinOp:{
            shortcutLits(sb, ctx,
                &ty.lhs, "rax",
                &ty.rhs, "rbx")
            switch ty.op {
                case .Plus: {
                    nasm(sb, "add rax, rbx")
                }
                case .Minus: {
                    nasm(sb, "sub rax, rbx")
                }
                case .Eq: {
                    nasm(sb, "cmp rax, rbx")
                }
            }
            nasm(sb, "push rax")
        }
        case ^UnaryOp: {
            assert(false, "TODO\n")
        }
        case ^Syscall0: {
            shortcutLit(sb, ctx,
                &ty.call, "rax")
            nasm(sb, "syscall")
            pushReg(sb, "rax")
        }
        case ^Syscall1: {
            shortcutLits(sb, ctx,
                &ty.arg1, "rdi", 
                &ty.call, "rax")
            nasm(sb, "syscall")
            pushReg(sb, "rax")
        }
        case ^Syscall2: {
            // TODO: Optimize later using shortcuts
            shortcutAllLiterals(sb, ctx, 
                {&ty.call, "rax"},
                {&ty.arg1, "rdi"},
                {&ty.arg2, "rsi"})
            nasm(sb, "syscall")
            pushReg(sb, "rax")
        }
        case ^Syscall3: {
            shortcutAllLiterals(sb, ctx, 
                {&ty.call, "rax"},
                {&ty.arg1, "rdi"},
                {&ty.arg2, "rsi"},
                {&ty.arg3, "rdx"})
            nasm(sb, "syscall")
            pushReg(sb, "rax")
        }
        case ^Drop: {
            // Move the stack pointer back to ignore the value that was there
            nasm(sb, "add rsp,8")
        }
    }
}

loadRegWithLit :: proc(sb:^strings.Builder, ctx:^ASMContext, reg:string, lit:^ast.PushLiteral) {
    switch type in lit {
        case int: {
            loadRegWithInt(sb, reg, type)
        }
        case string: {
            loadRegWithLabel(sb, reg, getStringLabel(ctx, type))
        }
        case bool: {
            loadRegWithInt(sb, reg, type ? 1 : 0)
        }
        case f64: {
            fmt.sbprintf(sb, "   movsd %s, qword [%s]\n", 
                reg, getFloatLabel(ctx, type))
        }
    }
}

// Gets an int onto a register from AST
shortcutLit :: proc(sb: ^strings.Builder, ctx:^ASMContext, as: ^ast.AST, reg:string) -> bool {
    if lit1, isLit := as.(^ast.PushLiteral); isLit {
        loadRegWithLit(sb, ctx, reg, lit1)
        return true
    }
    generateNasmFromASTHelp(sb, ctx, as)
    popReg(sb, reg)
    return false
}

// Gets two ints into registers by either immediate value or generating on the stack
shortcutLits :: proc(sb: ^strings.Builder, ctx:^ASMContext, ast1:^ast.AST, reg1:string, ast2: ^ast.AST, reg2:string) {
    lit1, isLit1 := ast1.(^ast.PushLiteral)
    lit2, isLit2 := ast2.(^ast.PushLiteral)
    if isLit1 {
        if isLit2 {
            // Load both immediately
            loadRegWithLit(sb, ctx, reg1, lit1)
            loadRegWithLit(sb, ctx, reg2, lit2)
        } else {
            // Generate second then pop second and load first 
            generateNasmFromASTHelp(sb, ctx, ast2)
            popReg(sb, reg2)
            loadRegWithLit(sb, ctx, reg1, lit1)
        }
    } else {
        if isLit2 {
            // Generate first then pop first and load second 
            generateNasmFromASTHelp(sb, ctx, ast1)
            popReg(sb, reg1)
            loadRegWithLit(sb, ctx, reg2, lit2)
        } else {
            // Generate both
            generateNasmFromASTHelp(sb, ctx, ast1)
            generateNasmFromASTHelp(sb, ctx, ast2)
    
            popReg(sb, reg2)
            popReg(sb, reg1)
        }
    }
}

// Loads many registers with immediate values if possible
shortcutAllLiterals :: proc(sb:^strings.Builder, ctx:^ASMContext, rest:..struct{ast:^ast.AST,reg:string}) {
    // Values that can be loaded directly are done after
    indiciesForLoad := make([dynamic]int)
    defer delete(indiciesForLoad)
    for asReg, i in rest {
        _, isLiteral := asReg.ast.(^ast.PushLiteral)
        if isLiteral {
            // Watch ones that can be immediately loaded after
            append(&indiciesForLoad, i)
        } else {
            // Pushes values that aren't immediately literals
            generateNasmFromASTHelp(sb, ctx, asReg.ast)
        }
    }
    loadIndex := 0
    for i in 0..<len(rest) {
        // In bounds and needs indexing
        if loadIndex < len(indiciesForLoad) && indiciesForLoad[loadIndex] == i {
            // Should be safe to do
            lit := rest[i].ast.(^ast.PushLiteral)
            loadRegWithLit(sb, ctx, rest[i].reg, lit)
            loadIndex += 1
        } else {
            popReg(sb, rest[i].reg)
        }
    }

}

// Adds an indented instruction with a newline
nasm :: proc(sb : ^strings.Builder, instruction : string) {
    fmt.sbprintf(sb, "   %s\n", instruction)
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
popReg :: proc(sb: ^strings.Builder, reg:string, isFloat := false) {
    if isFloat {
        assert(false, "TODO")
    }
    fmt.sbprintf(sb, "   pop %s\n", reg)
}

// Pushes value in register
pushReg :: proc(sb: ^strings.Builder, reg:string, isFloat := false) {
    if isFloat {
        assert(false, "TODO")
    }
    /*
        sub rsp,0x10 // 0x10 = 16 of course.
        // And then we just dump our SSE register onto the stack.
        movdqu [rsp],xmm0
        // Do what needs to be done with xmm0...
        movdqu xmm0,[rsp]
        add rsp,0x10
    */
    fmt.sbprintf(sb, "   push %s\n", reg)
}

generateDataSection :: proc(sb:^strings.Builder, ctx:^ASMContext) {
    // Nothing to add
    if len(ctx.stringLits) == 0 do return
    strings.write_byte(sb, '\n')
    nasm(sb, "section .data")
    for k, v in ctx.stringLits {
        strings.write_string(sb, v)
        strings.write_string(sb, ": db ")
        escapeStringToNASM(sb, k)
        strings.write_byte(sb, '\n')
        // strings.write_string(sb, k)
        // strings.write_string(sb, "\',10\n")
        // Should I preload their lengths too?
    }
}

generateBSSSection :: proc(sb:^strings.Builder, ctx:^ASMContext) {
    
}

// Turns string  literal into what the nasm asm expects
escapeStringToNASM :: proc(sb:^strings.Builder,value:string) {
    lastEscaped := false
    for c,i in value {
        if lastEscaped do strings.write_byte(sb, ',')
        switch c {
            case '\r', '\n', '\t', 0, '\'', '\\': {
                if !lastEscaped && i != 0 {
                    // Need to close previous string
                    strings.write_string(sb, "',")
                }
                strings.write_int(sb, int(c))
                lastEscaped = true
            }
            case: {
                if lastEscaped || i == 0 {
                    strings.write_byte(sb, '\'')
                    lastEscaped = false
                }
                strings.write_byte(sb, u8(c))
            }
        }
    }
}