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
    CString,
    At, // Used for reading from variables
    If,
    Eq,
    Gt,
    Lt,
    Le,
    Ge,
    Ne,
    Let,
    Rot, // Bot Mid Top => Mid Top Bot
    Dup, // Top => Top, Top
    Nip, // Mid, Top => Top
    QQQ, // ??? Shows current type stack
    Exit,
    Plus,
    Dash,
    Bang, // Used for writing to variables
    Swap, // Mid, Top => Mid, Top
    Drop, // Mid, Top => Mid
    Over, // Mid Top => Mid Top Mid
    Type,
    Puts,
    Proc,
    Then,
    Else,
    Cast,
    While,
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
    OBracket,
    CBracket,

}
// Converting strings to tokens
IdentifierTokens : map[string]TokenType = {
    "@" = .At,
    "=" = .Eq,
    "<" = .Lt,
    ">" = .Gt,
    "if" = .If,
    "<=" = .Le,
    ">=" = .Ge,
    "!=" = .Ne,
    "+" = .Plus,
    "-" = .Dash,
    "!" = .Bang,
    ":" = .Colon,
    "let" = .Let,
    "dup" = .Dup,
    "nip" = .Nip,
    "rot" = .Rot,
    "???" = .QQQ,
    "(" = .OParen,
    ")" = .CParen,
    "{" = .OBrace,
    "}" = .CBrace,
    "swap" = .Swap,
    "over" = .Over,
    "exit" = .Exit,
    "drop" = .Drop,
    "proc" = .Proc,
    "puts" = .Puts,
    "then" = .Then,
    "else" = .Else,
    "[" = .OBracket,
    "]" = .CBracket,
    "while" = .While,
    "macro" = .Macro,
    "import" = .Import,
    "syscall0" = .Syscall0,
    "syscall1" = .Syscall1,
    "syscall2" = .Syscall2,
    "syscall3" = .Syscall3,
}

// These are tokens that need to be handled themselves
splitsToken : map[u8]TokenType = {
    // ',' = .Comma,
    '[' = .OBracket,
    ']' = .CBracket,
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
        case .IntLit:   fmt.printf("<%d>", value.(int))
        case .FloatLit: fmt.printf("<%f>", value.(f64))
        case .Error:    fmt.printf("<Error '%s'>", value.(string))
        case .Ident:    fmt.printf("<Ident '%s'>", value.(string))
        case .BoolLit:  fmt.printf("<Bool '%s'>", value.(bool) ? "true" : "false")
        case .StringLit:fmt.printf("<%s>", util.escapeString(value.(string)))
        case .CString  :fmt.printf("<c%s>", util.escapeString(value.(string)))
        case .Type:     fmt.printf("<(%s)>", types.TypeToString[value.(types.Type)])
        case .Cast:     fmt.printf("<cast(%s)>", types.TypeToString[value.(types.Type)])
        case .Eq:       fmt.printf("<=>")
        case .At:       fmt.printf("<@>")
        case .Gt:       fmt.printf("<>>")
        case .Lt:       fmt.printf("<<>")
        case .Colon:    fmt.printf("<:>")
        case .Plus:     fmt.printf("<+>")
        case .Dash:     fmt.printf("<->")
        case .OParen:   fmt.printf("<(>")
        case .CParen:   fmt.printf("<)>")
        case .CBrace:   fmt.printf("<}>")
        case .Bang:     fmt.printf("<!>")
        case .OBrace:   fmt.printf("<{{>")
        case .If:       fmt.printf("<If")
        case .Le:       fmt.printf("<<=")
        case .Ge:       fmt.printf("<>=")
        case .Ne:       fmt.printf("<!=")
        case .Let:      fmt.printf("<Let>")
        case .Dup:      fmt.printf("<Dup>")
        case .Nip:      fmt.printf("<Nip>")
        case .Rot:      fmt.printf("<Rot>")
        case .QQQ:      fmt.printf("<???>")
        case .Swap:     fmt.printf("<Swap>")
        case .Over:     fmt.printf("<Over>")
        case .Drop:     fmt.printf("<Drop>")
        case .Exit:     fmt.printf("<Exit>")
        case .Puts:     fmt.printf("<Puts>")
        case .Proc:     fmt.printf("<Proc>")
        case .Then:     fmt.printf("Then>")
        case .Else:     fmt.printf("<Else>")
        case .While:    fmt.printf("<While")
        case .Macro:    fmt.printf("<Macro>")
        case .Import:   fmt.printf("<Import>")
        case .OBracket: fmt.printf("<[>")
        case .CBracket: fmt.printf("<]>")
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

// Prints all the tokens given along with their locations
printTokens :: proc(tokens: []Token, includeLines := false) {
    if includeLines {
        for token in tokens {
            util.printLoc(token.loc)
            printToken(token)
            fmt.println()
        }
        return
    }
    indent := 0
    for token in tokens {
        if token.type == .OBrace {
            printToken(token)
            indent += 1
            fmt.println()
            for i in 0..<indent do fmt.printf(" ")
        } else if token.type == .CBrace {
            indent -= 1
            fmt.println()
            for i in 0..<indent do fmt.printf(" ")
            printToken(token)
            fmt.println()
            for i in 0..<indent do fmt.printf(" ")
        } else if token.type == .Proc {
            fmt.println()
            printToken(token)
            fmt.printf(" ")
        } else {
            printToken(token)
            fmt.printf(" ")
        }
    }
    fmt.println()
}