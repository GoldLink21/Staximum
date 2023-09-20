package main

import "core:os"
import "core:fmt"
import "./tokenizer"
import "./generator"
import "./ast"

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
    // Convert to AST
    program, astErr := ast.resolveTokens(tokens[:])
    
    if astErr != nil {
        fmt.printf("%s", astErr.(string))
        os.exit(1)
    }
    fmt.printf("\n---Tokenized Program---\n")

    program = ast.optimizeASTProgram(program)
    ast.printProgram(program)

    fmt.printf("\n---Made AST---\n")

    when  GENERATE_ASM {
        generator.generateNasmToFile(program, fmt.tprintf("%s.S", outFile))
        fmt.printf("\n---Made ASM---\n")
    }
}

// Does not check your command for correctness
runCmd :: proc(cmd: string, args:..string) -> (ok:bool) {
    pid, err := os.fork()
    if err == -1 do return false
    if pid == 0 do os.execvp(cmd, args)
    return true
}