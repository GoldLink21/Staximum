package main

import "core:os"
import "core:fmt"
import "./tokenizer"
import "./generator"
import "./ast"

OUT_FILE_NAME :: "out"

main :: proc() {
    if len(os.args) != 2 {
        fmt.printf("Invalid usage\n")
        return
    }
    textBytes, ok := os.read_entire_file_from_filename(os.args[1])
    text := string(textBytes)
    if !ok {
        fmt.printf("Error reading from file %s\n", os.args[1])
        return
    }
    // Tokenize
    tokens := tokenizer.tokenize(text, os.args[1])
    tokenizer.printTokens(tokens[:])
    // Convert to AST
    AST := ast.resolveTokens(tokens[:])
    ast.printAST(AST[:])

    generator.generateNasmFromAST(AST[:], OUT_FILE_NAME + ".S")
    runCmd("nasm", "-felf64", OUT_FILE_NAME + ".S")
    runCmd("ld", OUT_FILE_NAME + ".o", "-o", OUT_FILE_NAME)
    /*
    // Generate asm
    generator.generateNasmFromTokens(tokens[:], OUT_FILE_NAME + ".S")
    // Assemble
    runCmd("nasm", "-felf64", OUT_FILE_NAME + ".S")
    // Link
    runCmd("ld", OUT_FILE_NAME + ".o", "-o", OUT_FILE_NAME)
    */
}

// Does not check your command for correctness
runCmd :: proc(cmd: string, args:..string) -> (ok:bool) {
    pid, err := os.fork()
    if err == -1 do return false
    if pid == 0 do os.execvp(cmd, args)
    return true
}