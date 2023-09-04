package tokenizer

import "core:fmt"

TokenType :: enum {
    Ident = 0,
    IntLit,
    BoolLit,
    StringLit,
    FloatLit,
    // CString,
    If,
    Eq,
    Gt,
    Let,
    End,
    Exit,
    Plus,
    Dash,
    Bang,
    Drop,
    Print,
    Colon,
    Macro,
    OParen,
    CParen,
    Syscall0,
    Syscall1,
    Syscall2,
    Syscall3,
    // Syscall4,
    // Syscall5,
    // Syscall6,

}
IdentifierTokens : map[string]TokenType = {
    "if" = .If,
    "let" = .Let,
    "end" = .End,
    "exit" = .Exit,
    "drop" = .Drop,
    "print" = .Print,
    "macro" = .Macro,
    "syscall1" = .Syscall1,
    "syscall3" = .Syscall3,
}
SymbolTokens : map[u8]TokenType = {
    '>' = .Gt,
    '=' = .Eq,
    '-' = .Dash,
    '+' = .Plus,
    '!' = .Bang,
    ':' = .Colon,
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
        case .Eq:       fmt.printf("<=>")
        case .Gt:       fmt.printf("<>>")
        case .Colon:    fmt.printf("<:>")
        case .Plus:     fmt.printf("<+>")
        case .Dash:     fmt.printf("<->")
        case .OParen:   fmt.printf("<(>")
        case .CParen:   fmt.printf("<)>")
        case .Bang:     fmt.printf("<!>")
        case .If:       fmt.printf("<If>")
        case .End:      fmt.printf("<End>")
        case .Let:      fmt.printf("<Let>")
        case .Drop:     fmt.printf("<Drop>")
        case .Exit:     fmt.printf("<Exit>")
        case .Print:    fmt.printf("<Print>")
        case .Macro:    fmt.printf("<Macro>")
        case .Syscall0: fmt.printf("<Syscall0>")
        case .Syscall1: fmt.printf("<Syscall1>")
        case .Syscall2: fmt.printf("<Syscall2>")
        case .Syscall3: fmt.printf("<Syscall3>")
        // case .Syscall4: fmt.printf("<Syscall4>")
        // case .Syscall5: fmt.printf("<Syscall5>")
        // case .Syscall6: fmt.printf("<Syscall6>")

        // Left without default for compiler complaint on adding more
    }
}

printTokens :: proc(tokens: []Token) {
    for token in tokens {
        printLoc(token.loc)
        printToken(token)
        fmt.printf("\n")
    }
}