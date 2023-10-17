// Creates assembly
package generator

import "../tokenizer"
import "../ast"
import "../util"
import "core:os"
import "core:fmt"
import "core:strings"

// TODO: Convert from generating straight asm to an intermediate AST
//  to allow better optimizations and outputting other ASM types

// Tells whether comments should be generated in final ASM
ASM_COMMENTS :: true
ErrorMsg :: util.ErrorMsg

// TODO convert to have string error messages

paramRegs : []string = {"rax", "rdi", "rsi", "rdx", "r10", "r8", "r9"}

// Stores the state of the ASM as its generated
ASMContext :: struct {
    // Maps string value to label name
    stringLits : map[string]string,
    // Float labels
    floatLits : map[f64]string,
    globalVars: map[string]ast.Variable,
    numIf, numWhile: int,
    // Maps string var names to which index they are on the stack
    blockVars:map[string]int,
}

generateNasmToFile :: proc(program:^ast.ASTProgram, outFile:string) {
    os.remove(outFile)
    fd, err := os.open(outFile, os.O_CREATE | os.O_WRONLY, 0o777)
    if err == -1 {
        fmt.assertf(false, "Error Opening output assembly")
    }
    defer os.close(fd)
    os.write_string(fd, generateNasmFromProgram(program))
}

generateProcCall :: proc(sb: ^strings.Builder, procName:string, program:^ast.ASTProgram) {
    comment(sb, "Call to '%s'", procName)
    if procName not_in program.procs {
        fmt.panicf(
            "Cannot generate proc call '%s' for proc that doesn't exist\n", 
            procName)
    }
    procc := program.procs[procName]
    nVars := procc.body.state.totalVars
    if nVars != 0 {
        nasm(sb, "add rsp, %d", nVars * 8)
    }
    nInputs := len(procc.inputs) 
    if nInputs != 0 {
        assert(nInputs <= len(paramRegs))
        comment(sb, "Setting up inputs for proc")
        for i := nInputs - 1; i >= 0; i -= 1 {
            popReg(sb, paramRegs[i])
        }
    }
    nasm(sb, "call %s", procName)
    // Pop is handled at the end of procs to allow setting up
    //  the return values
    // nasm(sb, "pop rbp")
}

// Takes an ASTProgram and generates nasm for it
generateNasmFromProgram :: proc(program: ^ast.ASTProgram) -> string {
    sb: strings.Builder
    strings.write_string(&sb, 
        "section .text\nglobal _start\n_start:\n")
        // Reserve space on stack for vars
        // fmt.sbprintf(&sb, "")        
    generateGlobalValues(&sb, nil, program)

    generateProcCall(&sb, "main", program)
    // Exit with 0
    comment(&sb, "Safe exit")
    strings.write_string(&sb, "   mov rax, 60\n   mov rdi, 0\n   syscall\n")
    
    ctx := new(ASMContext)
    ctx.floatLits = make(map[f64]string)
    ctx.stringLits = make(map[string]string)
    ctx.globalVars = program.globalVars//make(map[string]ast.Variable)
    ctx.numIf = 0
    ctx.numWhile = 0
    
    // Fill up global vars
    

    for name,pr in program.procs {
        // TODO: Conform to some calling convention
        fmt.printf("Generating Proc %s\n", name)
        fmt.sbprintf(&sb, "%s:\n", name)
        comment(&sb, "Reserve space for vars")
        pushReg(&sb, "rbp")
        nasm(&sb, "mov rbp, rsp")
        comment(&sb, "Pushing input values")
        //for i := len(pr.inputs) - 1; i >= 0; i -= 1 {
        for i in 0..<len(pr.inputs) {
            pushReg(&sb, paramRegs[i])
        }
        a : ast.AST = pr.body
        generateNasmFromASTHelp(&sb, ctx, &a, false, program)
        comment(&sb, "Save output params into regs") 
        // ! Should this be reversed?
        for i := len(pr.outputs) - 1; i >= 0; i -= 1 {
            popReg(&sb, paramRegs[i])
        }

        nasm(&sb, "pop rbp")
        nasm(&sb, "ret")
    }
    generateDataSection(&sb, ctx)
    generateBSSSection(&sb, ctx, program)

    return strings.to_string(sb)
}

// Takes a string value and generates a label for it if one doen't already exist
getStringLabel :: proc(ctx:^ASMContext, str:string) -> string {
    if str not_in ctx.stringLits {
        // Need to generate
        ctx.stringLits[str] = fmt.aprintf("stringLit_%d", len(ctx.stringLits))
    }
    return ctx.stringLits[str]
}
// Takes a float value and generates a label for it unless one already exists
getFloatLabel :: proc(ctx:^ASMContext, flt:f64) -> string {
    if flt not_in ctx.floatLits {
        ctx.floatLits[flt] = fmt.aprintf("floatLit_%d", len(ctx.floatLits))
    }
    return ctx.floatLits[flt]
}

generateNasmFromASTList :: proc(sb:^strings.Builder, ctx: ^ASMContext, as: [dynamic]ast.AST, inDrop:=false, program:^ast.ASTProgram) -> (didDrop:bool = false) {
    for &a in as {
        generateNasmFromASTHelp(sb, ctx, &a, false, program)
    }
    return false
}

// Recursively traverse to generate nasm
generateNasmFromASTHelp :: proc(sb:^strings.Builder, ctx: ^ASMContext, as: ^ast.AST, inDrop:=false, program:^ast.ASTProgram) -> (didDrop:bool = false) {
    using ast
    switch ty in as {
        case ^ASTPushLiteral: {
            switch litType in ty {
                case int: {
                    // Ignore push int if dropped
                    if inDrop do return true
                    nasm(sb, "push %d", int(litType))
                }
                case f64: {
                    assert(false, "TODO")
                }
                case bool: {
                    // Ignore push int if dropped
                    if inDrop do return true
                    nasm(sb, "push %d", int(litType))
                }
                case string: {
                    pushReg(sb, getStringLabel(ctx, litType))
                }
            }
        }
        case ^ASTBinOp:{
            shortcutLits(sb, ctx,
                &ty.lhs, "rax",
                &ty.rhs, "rbx", 
                program)
            switch ty.op {
                case .Plus: {
                    nasm(sb, "add rax, rbx")
                    pushReg(sb, "rax")
                }
                case .Minus: {
                    nasm(sb, "sub rax, rbx")
                    pushReg(sb, "rax")
                }
                // Conditions all are the same
                case .Eq, .Gt, .Lt, .Ne, .Ge, .Le: {
                    nasm(sb, "cmp rax, rbx")
                    // Don't push values for equality checks
                }
            }
            // nasm(sb, "push rax")
        }
        case ^ASTUnaryOp: {
            assert(false, "TODO\n")
        }
        case ^ASTSyscall0: {
            shortcutLit(sb, ctx,
                &ty.call, "rax", program)
            nasm(sb, "syscall ; 0 args")
            if inDrop {
                return true
            }        
            pushReg(sb, "rax")
        }
        case ^ASTSyscall1: {
            shortcutLits(sb, ctx,
                &ty.arg1, "rdi", 
                &ty.call, "rax", program)
            nasm(sb, "syscall ; 1 arg")
            if inDrop {
                comment(sb, "Dropped push rax")
                return true
            }        
            pushReg(sb, "rax")
        }
        case ^ASTSyscall2: {
            // TODO: Optimize later using shortcuts
            shortcutAllLiterals(sb, ctx, program,
                {&ty.call, "rax"},
                {&ty.arg1, "rdi"},
                {&ty.arg2, "rsi"})
            nasm(sb, "syscall ; 2 args")
            if inDrop {
                comment(sb, "Dropped push rax")
                return true
            }        
            pushReg(sb, "rax")
        }
        case ^ASTSyscall3: {
            shortcutAllLiterals(sb, ctx, program,
                {&ty.call, "rax"},
                {&ty.arg1, "rdi"},
                {&ty.arg2, "rsi"},
                {&ty.arg3, "rdx"})
            nasm(sb, "syscall ; 3 args")
            if inDrop {
                comment(sb, "Dropped push rax")
                return true
            }
            pushReg(sb, "rax")
        }
        case ^ASTBlock: {
            // First check how many var decls there are and reserver space for them
            beforeLen := len(ctx.blockVars)
            numDecls := 0
            for &node, i in ty.nodes {
                varDecl, isVarDecl := node.(^ast.ASTVarDecl)
                if !isVarDecl {
                    numDecls = i
                    break
                }
                comment(sb, "Var '%s'", varDecl.ident)
                ctx.blockVars[varDecl.ident] = i
            }
            // Save space on the stack for local vars
            // comment(sb, "Setup base pointer")
            // pushReg(sb, "rbp")
            // nasm(sb, "mov rbp, rsp")
            comment(sb, "{{")
            // Start after all var decls
            for i := numDecls; i < len(ty.nodes); i += 1 {
                generateNasmFromASTHelp(sb, ctx, &ty.nodes[i], false, program)
            }
            // Now clean up stack from variable space
            // comment(sb, "Cleanup base pointer")
            // popReg(sb, "rbp")
            comment(sb, "}")
        }
        case ^ASTDrop: {
            // Move the stack pointer back to ignore the value that was there
            if !generateNasmFromASTHelp(sb, ctx, &ty.value, true, program) {
                // Was not able to shortcut the drop
                comment(sb, "Drop")
                nasm(sb, "add rsp,8")
            }
        }
        case ^ASTVarRef: {
            // TODO
            assert(false, "TODO asm var ref\n")
        }
        case ^ASTVarDecl: {
            // These will always be at the top of the scope
            //  And should be skipped over in ASTBlock
            panic("BUG: AST Var Decl should be skipped in AST Block\n")
        }
        case ^ASTInputParam: {
            // Value should already be pushed
            if ty.from == "while" {
                // This means for a while loop
                comment(sb, "While input")
                return
            } else {
                comment(sb, "Input param %d for '%s'", ty.index, ty.from)
                return
            }
        }
        case ^ASTProcCall: {
            generateProcCall(sb, ty.ident, program)
            comment(sb, "Get saved return values from registers")
            pr := program.procs[ty.ident]
            for i in 0..<len(pr.outputs) {
                pushReg(sb, paramRegs[i])
            }
        }
        case ^ASTDup: {
            // popReg(sb, "rax")
            // pushReg(sb, "rax")
            // pushReg(sb, "rax")
            pushReg(sb, "qword [rsp]")
        }
        case ^ASTNip:{
            popReg(sb, "rax")
            popReg(sb, "rbx")
            pushReg(sb, "rax")
        } 
        case ^ASTOver:{
            /*
            popReg(sb, "rax")
            popReg(sb, "rbx")

            pushReg(sb, "rbx")
            pushReg(sb, "rax")
            pushReg(sb, "rbx")*/
            pushReg(sb, "qword [rsp+8]")

        }
        case ^ASTRot: {
            popReg(sb, "rax")
            popReg(sb, "rbx")
            popReg(sb, "rcx")

            pushReg(sb, "rbx")
            pushReg(sb, "rcx")
            pushReg(sb, "rax")
        } 
        case ^ASTSwap: {
            popReg(sb, "rax")
            popReg(sb, "rbx")
            pushReg(sb, "rax")
            pushReg(sb, "rbx")
        }
        case ^ASTVarRead: {
            if ty.isGlobal {
                comment(sb, "Read from global %s", ty.ident)
                nasm(sb, "push qword [%s]", ctx.globalVars[ty.ident].label)
                // panic("TODO: ASM read global")
            } else if ty.ident == "" {
                // Random memory access
                popReg(sb, "rax")
                pushReg(sb, "[rax]")
            } else {
                comment(sb, "Read from %s", ty.ident)
                nasm(sb, "push qword [rbp-%d]", (ctx.blockVars[ty.ident] + 1) * 4)
            }
        }
        case ^ASTVarWrite: {
            comment(sb, "Write to %s", ty.ident)
            if ty.isGlobal {
                shortcutLit(sb, ctx, &ty.value, 
                    fmt.tprintf("qword [%s]", ctx.globalVars[ty.ident].label), program)
                //nasm(sb, "mov [%s], rax", ctx.globalVars[ty.ident].label)
            } else {
                // Generate value to write
                shortcutLit(sb, ctx, &ty.value, "rax", program)
                nasm(sb, "mov [rbp-%d], rax", (ctx.blockVars[ty.ident] + 1) * 4)
            }
        }
        case ^ASTIf: {
            ctx.numIf += 1
            ifNumber := ctx.numIf
            // Conditional Generation
            // Check if condition is just a boolean lit
            comment(sb, "Begin if %d", ctx.numIf)
            pl, isPl := ty.cond.(^ast.ASTPushLiteral)
            if isPl {
                b, isBool := pl.(bool)
                if isBool {
                    // TODO:
                    // Can optimize here to either only get if or else block
                    loadReg(sb, "rax", int(b))
                    nasm(sb, "cmp rax, 1")
                } else {
                    generateNasmFromASTHelp(sb, ctx, &ty.cond, false, program)
                }
            } else {
                generateNasmFromASTHelp(sb, ctx, &ty.cond, false, program)
            }

            // Should end up with cmp value already made
            // Conditions get flipped due to jumping past the if block
            switch ty.jumpType {
                case .Eq: nasm(sb, "je if_true_%d", ifNumber)
                case .Gt: nasm(sb, "jg if_true_%d", ifNumber)
                case .Lt: nasm(sb, "jl if_true_%d", ifNumber)
                case .Ne: nasm(sb, "jne if_true_%d", ifNumber)
            }
            if ty.elseBlock != nil {
                comment(sb, "Begin Else %d", ifNumber)
                generateNasmFromASTHelp(sb, ctx, &ty.elseBlock, false, program)
            }
            nasm(sb, "jmp end_if_%d", ifNumber)
            addLabel(sb, "if_true_%d", ifNumber)
            // Write if block
            generateNasmFromASTHelp(sb, ctx, &ty.body, false, program)
            addLabel(sb, "end_if_%d", ifNumber)
        }
        case ^ASTWhile: {
            idx := ctx.numWhile
            ctx.numWhile += 1
            comment(sb, "Begin while %d", idx)

            addLabel(sb, "while_%d_cond", idx)
            // Remove last element which should be the thing that actually calculates the condition
            lastElem := pop(&ty.cond)
            generateNasmFromASTList(sb, ctx, ty.cond, false, program)

            // Adapted from if
            pl, isPl := lastElem.(^ast.ASTPushLiteral)
            if isPl {
                b, isBool := pl.(bool)
                if isBool {
                    // TODO:
                    // Can optimize here to either only get if or else block
                    loadReg(sb, "rax", int(b))
                    nasm(sb, "cmp rax, 1")
                } else {
                    generateNasmFromASTHelp(sb, ctx, &lastElem, false, program)
                }
            } else {
                generateNasmFromASTHelp(sb, ctx, &lastElem, false, program)
            }

            // Should end up with cmp value already made
            // Conditions get flipped due to jumping past the if block
            switch ty.jumpType {
                case .Eq: nasm(sb, "jne while_%d_end", idx)
                case .Gt: nasm(sb, "jle while_%d_end", idx)
                case .Lt: nasm(sb, "jge while_%d_end", idx)
                case .Ne: nasm(sb, "je while_%d_end", idx)
            }
            //////////  


            // Last should generate condition
            addLabel(sb, "while_%d_body", idx)

            generateNasmFromASTHelp(sb, ctx, &ty.body, false, program)
            // Must re-check so do conditionx`x`
            nasm(sb, "jmp while_%d_cond", idx)

            addLabel(sb, "while_%d_end", idx)

            comment(sb, "End while %d", idx)

            // panic("TODO: While Generation\n")
        }
        case ^ASTProcReturn: {
            // Nothing to do, value is already pushed
        }
    }
    return false
}

// Takes a literal value and loads it into a register
loadRegWithLit :: proc(sb:^strings.Builder, ctx:^ASMContext, reg:string, lit:^ast.ASTPushLiteral) {
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

// Gets an int into a register from AST. Will generate more if it needs to
shortcutLit :: proc(sb: ^strings.Builder, ctx:^ASMContext, as: ^ast.AST, reg:string, program:^ast.ASTProgram) -> bool {
    if lit1, isLit := as.(^ast.ASTPushLiteral); isLit {
        loadRegWithLit(sb, ctx, reg, lit1)
        return true
    }
    generateNasmFromASTHelp(sb, ctx, as, false, program)
    popReg(sb, reg)
    return false
}

// Gets two ints into registers by either immediate value or generating on the stack
shortcutLits :: proc(sb: ^strings.Builder, ctx:^ASMContext, ast1:^ast.AST, reg1:string, ast2: ^ast.AST, reg2:string, program:^ast.ASTProgram) {
    lit1, isLit1 := ast1.(^ast.ASTPushLiteral)
    lit2, isLit2 := ast2.(^ast.ASTPushLiteral)
    if isLit1 {
        if isLit2 {
            // Load both immediately
            loadRegWithLit(sb, ctx, reg1, lit1)
            loadRegWithLit(sb, ctx, reg2, lit2)
        } else {
            // Generate second then pop second and load first 
            generateNasmFromASTHelp(sb, ctx, ast2, false, program)
            popReg(sb, reg2)
            loadRegWithLit(sb, ctx, reg1, lit1)
        }
    } else {
        if isLit2 {
            // Generate first then pop first and load second 
            generateNasmFromASTHelp(sb, ctx, ast1, false, program)
            popReg(sb, reg1)
            loadRegWithLit(sb, ctx, reg2, lit2)
        } else {
            // Generate both
            generateNasmFromASTHelp(sb, ctx, ast1, false, program)
            generateNasmFromASTHelp(sb, ctx, ast2, false, program)
    
            popReg(sb, reg2)
            popReg(sb, reg1)
        }
    }
}

// Loads many registers with immediate values if possible
shortcutAllLiterals :: proc(sb:^strings.Builder, ctx:^ASMContext, program:^ast.ASTProgram, rest:..struct{ast:^ast.AST,reg:string}) {
    // Values that can be loaded directly are done after
    indiciesForLoad := make([dynamic]int)
    defer delete(indiciesForLoad)
    // Check for literals
    for asReg, i in rest {
        _, isLiteral := asReg.ast.(^ast.ASTPushLiteral)
        if isLiteral {
            // Watch ones that can be immediately loaded after
            append(&indiciesForLoad, i)
        } else {
            // Pushes values that aren't immediately literals
            generateNasmFromASTHelp(sb, ctx, asReg.ast, false, program)
        }
    }
    // Tracks which index in the indicies for load to use
    loadIndex := 0
    for i in 0..<len(rest) {
        // In bounds and needs indexing
        if loadIndex < len(indiciesForLoad) && indiciesForLoad[loadIndex] == i {
            // Should be safe to do
            lit, wasLit := rest[i].ast.(^ast.ASTPushLiteral)
            //assert(wasLit, "Did not find literal value?")
            loadRegWithLit(sb, ctx, rest[i].reg, lit)
            loadIndex += 1
        } else {
            popReg(sb, rest[i].reg)
        }
    }
}
// Many of these smaller functions will later be abstracted into a
//  list of ASM objects for optimizing 

// Adds an indented instruction with a newline
nasm :: proc(sb : ^strings.Builder, instruction : string, args:..any) {
    fmt.sbprintf(sb, "   ")
    fmt.sbprintf(sb, instruction, ..args)
    fmt.sbprintf(sb, "\n")
}
// Creates a label with a name
addLabel :: proc(sb: ^strings.Builder, labelName:string, args:..any) {
    fmt.sbprintf(sb, "%s:\n", fmt.tprintf(labelName, ..args))
}
// Loads an integer into a register
loadRegWithInt :: proc(sb: ^strings.Builder, reg:string, value:int) {
    nasm(sb, "mov %s, %d", reg, value)
}
// Loads a register with label
loadRegWithLabel :: proc(sb: ^strings.Builder, reg:string, label:string) {
    nasm(sb, "mov %s, %s", reg, label)
}

// Loads value into a register
loadReg :: proc{loadRegWithInt, loadRegWithLabel}

// Pops value into register
popReg :: proc(sb: ^strings.Builder, reg:string, isFloat := false) {
    if isFloat {
        panic("TODO")
    }
    nasm(sb, "pop %s", reg)
}

// Pushes value in register
pushReg :: proc(sb: ^strings.Builder, reg:string, isFloat := false) {
    if isFloat {
        assert(false, "TODO")
        /*
            sub rsp,0x10 // 0x10 = 16 of course.
            // And then we just dump our SSE register onto the stack.
            movdqu [rsp],xmm0
            // Do what needs to be done with xmm0...
            movdqu xmm0,[rsp]
            add rsp,0x10
        */
    }
    nasm(sb, "push %s", reg)
}

generateDataSection :: proc(sb:^strings.Builder, ctx:^ASMContext) {
    fmt.printf("Generating Data\n")
    // Nothing to add
    if len(ctx.stringLits) == 0 do return
    strings.write_byte(sb, '\n')
    fmt.sbprintf(sb, "section .data\n")
    comment(sb, "Space for string lits")
    for k, v in ctx.stringLits {
        strings.write_string(sb, v)
        strings.write_string(sb, ": db ")
        escapeStringToNASM(sb, k)
        strings.write_byte(sb, '\n')
        // Should I preload their lengths too?
    }
    comment(sb, "End data section")
}

comment :: proc(sb:^strings.Builder, msg:string, params:..any) {
    when ASM_COMMENTS {
        strings.write_string(sb, "; ")
        fmt.sbprintf(sb, msg, ..params)
        strings.write_byte(sb, '\n')
    }
}

generateBSSSection :: proc(sb:^strings.Builder, ctx:^ASMContext, program:^ast.ASTProgram) {
    // This will be for global variables
    strings.write_string(sb, "section .bss\n")
    comment(sb, "Space for global vars")
    for k, v in program.globalVars {
        // v.value
        fmt.sbprintf(sb, "global_%s: resd 1\n", k)
    }
}

generateGlobalValues :: proc(sb:^strings.Builder, ctx:^ASMContext, program:^ast.ASTProgram) {
    comment(sb, "Setting up global var values")
    for k, &v in program.globalVars {
        shortcutLit(sb, ctx, &v.value, 
            fmt.tprintf("qword [%s]", program.globalVars[k].label), program)
        // nasm(sb, "mov [global_%s], rax", k)
    }
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
    if !lastEscaped do strings.write_byte(sb, '\'')
}