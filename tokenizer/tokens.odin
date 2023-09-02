package tokenizer

import "core:fmt"

TokenType :: enum {
    Ident = 0,
    IntLit,
    BoolLit,
    StringLit,
    FloatLit,
    // CString,
    Exit,
    Plus,
    Let,
    Dash,
    Syscall1,
    If,
    Eq,
    End,
    OParen,
    CParen,
    Print,
}
IdentifierTokens : map[string]TokenType = {
    "exit" = .Exit,
    "syscall1" = .Syscall1,
    "let" = .Let,
    "if" = .If,
    "end" = .End,
    "print" = .Print,
}
SymbolTokens : map[u8]TokenType = {
    '-' = .Dash,
    '+' = .Plus,
    '=' = .Eq,
    '(' = .OParen,
    ')' = .CParen,
}



TokenValue :: union {
    string,
    int,
    f32,
    bool,
}


printToken :: proc(using token:Token) {
    switch token.type {
        case .Ident:    fmt.printf("<Ident '%s'>", value.(string))
        case .IntLit:   fmt.printf("<Int '%d'>", value.(int))
        case .FloatLit: fmt.printf("<Float '%f'>", value.(f32))
        case .StringLit:fmt.printf("<String \"%s\">", value.(string))
        case .BoolLit:  fmt.printf("<Bool '%s'>", value.(bool) ? "true" : "false")
        case .Exit:     fmt.printf("<Exit>")
        case .Plus:     fmt.printf("<+>")
        case .Dash:     fmt.printf("<->")
        case .Let:      fmt.printf("<Let>")
        case .Syscall1: fmt.printf("<Syscall1>")
        case .If:       fmt.printf("<If>")
        case .Eq:       fmt.printf("<=>")
        case .End:      fmt.printf("<End>")
        case .OParen:   fmt.printf("<(>")
        case .CParen:   fmt.printf("<)>")
        case .Print:    fmt.printf("<Print>")

        // Left without default for compiler complaint on adding more
    }
    // fmt.printf("<>")
}

printTokens :: proc(tokens: []Token) {
    for token in tokens {
        printLoc(token.loc)
        printToken(token)
        fmt.printf("\n")
    }
}