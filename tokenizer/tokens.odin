package tokenizer

import "core:fmt"
import "../types"
import "../util"

// All the available tokens
TokenType :: enum {
    Error = 0,
    Ident,
    IntLit,
    BoolLit,
    StringLit,
    FloatLit,
    // CString,
    If,
    Eq,
    Gt,
    Lt,
    Let,
    End,
    Exit,
    Plus,
    Dash,
    Bang,
    Drop,
    Type,
    Puts,
    Proc,
    Colon,
    Macro,
    OParen,
    CParen,
    OBrace,
    CBrace,
    Import,
    Syscall0,
    Syscall1,
    Syscall2,
    Syscall3,
    // Syscall4,
    // Syscall5,
    // Syscall6,

}
// Converting strings to tokens
IdentifierTokens : map[string]TokenType = {
    "if" = .If,
    "let" = .Let,
    "end" = .End,
    "exit" = .Exit,
    "drop" = .Drop,
    "proc" = .Proc,
    "puts" = .Puts,
    "macro" = .Macro,
    "import" = .Import,
    "syscall0" = .Syscall0,
    "syscall1" = .Syscall1,
    "syscall2" = .Syscall2,
    "syscall3" = .Syscall3,
}
// Single char tokens
SymbolTokens : map[u8]TokenType = {
    '>' = .Gt,
    '<' = .Lt,
    '=' = .Eq,
    '-' = .Dash,
    '+' = .Plus,
    '!' = .Bang,
    ':' = .Colon,
    '(' = .OParen,
    ')' = .CParen,
    '{' = .OBrace,
    '}' = .CBrace,
}


// Possible Values for a token
TokenValue :: union {
    string,
    int,
    f64,
    bool,
    // Used for casting types
    types.Type
}

// Prints a simple format for each token type
printToken :: proc(using token:Token) {
    switch token.type {
        case .Error:    fmt.printf("<Error '%s'>", value.(string))
        case .Ident:    fmt.printf("<Ident '%s'>", value.(string))
        case .IntLit:   fmt.printf("<Int '%d'>", value.(int))
        case .FloatLit: fmt.printf("<Float '%f'>", value.(f64))
        case .StringLit:fmt.printf("<String \"%s\">", value.(string))
        case .BoolLit:  fmt.printf("<Bool '%s'>", value.(bool) ? "true" : "false")
        case .Type:     fmt.printf("<Type '%s'>", types.TypeToString[value.(types.Type)])
        case .Eq:       fmt.printf("<=>")
        case .Gt:       fmt.printf("<>>")
        case .Lt:       fmt.printf("<<>")
        case .Colon:    fmt.printf("<:>")
        case .Plus:     fmt.printf("<+>")
        case .Dash:     fmt.printf("<->")
        case .OParen:   fmt.printf("<(>")
        case .CParen:   fmt.printf("<)>")
        case .OBrace:   fmt.printf("<{{>")
        case .CBrace:   fmt.printf("<}>")
        case .Bang:     fmt.printf("<!>")
        case .If:       fmt.printf("<If>")
        case .End:      fmt.printf("<End>")
        case .Let:      fmt.printf("<Let>")
        case .Drop:     fmt.printf("<Drop>")
        case .Exit:     fmt.printf("<Exit>")
        case .Puts:     fmt.printf("<Puts>")
        case .Proc:     fmt.printf("<Proc>")
        case .Macro:    fmt.printf("<Macro>")
        case .Import:   fmt.printf("<Import>")
        case .Syscall0: fmt.printf("<Syscall0>")
        case .Syscall1: fmt.printf("<Syscall1>")
        case .Syscall2: fmt.printf("<Syscall2>")
        case .Syscall3: fmt.printf("<Syscall3>")
        // case .Syscall4: fmt.printf("<Syscall4>")
        // case .Syscall5: fmt.printf("<Syscall5>")
        // Syscalls can go up to having 6 inputs
        // case .Syscall6: fmt.printf("<Syscall6>")

        // Left without default for compiler complaint on adding more
    }
}

printTokens :: proc(tokens: []Token) {
    for token in tokens {
        util.printLoc(token.loc)
        printToken(token)
        fmt.printf("\n")
    }
}