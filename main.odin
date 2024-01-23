package main

import "core:os"
import "core:fmt"
import "./tokenizer"
import "./generator"
import "./ast"
import "./simulator"

DEFAULT_OUT_FILE_NAME :: "out"

GENERATE_ASM :: #config(GENERATE_ASM,false)
// May shift away from doing internally
ASSEMBLE     :: #config(ASSEMBLE,    false)
LINK         :: #config(LINK,        false)

main :: proc() {

    // 0 1 2
    if len(os.args) > 3 || len(os.args) < 2  {
        fmt.printf("Invalid usage\n")
        return
    }
    inFile := os.args[1]
    outFile : string = DEFAULT_OUT_FILE_NAME
    if len(os.args) == 3 {
        outFile = os.args[2]
    }
    textBytes, ok := os.read_entire_file_from_filename(inFile)
    text := string(textBytes)
    if !ok {
        fmt.printf("Error reading from file %s\n", os.args[1])
        return
    }
    // Tokenize
    tokens, err := tokenizer.tokenize(text, os.args[1])
    if err != nil {
        fmt.printf("%s", err.(string))
        os.exit(1)
    }
    if len(tokens) == 0 {
        fmt.printf("Error: There were no tokens to resolve\n")
        os.exit(1)
    }
    fmt.printf("v---Tokenized Program---v\n")
    tokenizer.printTokens(tokens[:])
    fmt.printf("^-----------------------^\n")
    // Convert to AST
    program, astErr := ast.resolveTokens(tokens[:])
    
    if astErr != nil {
        fmt.printf("AST Error: %s", astErr.(string))
        os.exit(1)
    }

    fmt.printf("\nv------Made AST-------v\n")
    ast.printProgram(program)
    fmt.printf("^-----------------------^\n")
    program = ast.optimizeASTProgram(program)
    fmt.printf("\nv-----Optimized AST-----v\n")
    ast.printProgram(program)
    fmt.printf("^-----------------------^\n")

    when  GENERATE_ASM {
        generator.generateNasmToFile(program, fmt.tprintf("%s.S", outFile))
        fmt.printf("\n$-------Made ASM--------$\n")
    } else {
        fmt.printf("\nv-------Simulate--------v\n")

        simErr := simulator.simulateProgram(program)
        if simErr != nil {
            if simErr == "exit" {
                fmt.printf("\nExited with code '%d'", simulator.ExitCode)

            } else {
                fmt.printf("Error: %s", simErr.(string))
            }
        }

        fmt.printf("\n$-------Simulated-------$\n")
    }
}

// Does not check your command for correctness
runCmd :: proc(cmd: string, args:..string) -> (ok:bool) {
    pid, err := os.fork()
    if err == -1 do return false
    if pid == 0 do os.execvp(cmd, args)
    return true
}