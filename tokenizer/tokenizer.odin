package tokenizer

import "core:fmt"
import "core:os"

Location :: struct {
    line, col: uint,
    file: string,
}

printLoc :: proc(loc:Location){
    fmt.printf("%s %d:%d ", loc.file, loc.line + 1, loc.col)
}

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
}
IdentifierTokens : map[string]TokenType = {
    "exit" = .Exit,
    "syscall1" = .Syscall1,
    "let" = .Let,
    "if" = .If,
}
SymbolTokens : map[u8]TokenType = {
    '-' = .Dash,
    '+' = .Plus,
    '=' = .Eq,
}



TokenValue :: union {
    string,
    int,
    f32,
    bool,
}

Token :: struct {
    type : TokenType,
    loc: Location,
    value: TokenValue 
}

Tokenizer :: struct {
    text : string,
    loc: Location,
    i: int
}

printToken :: proc(using token:Token) {
    printLoc(loc)
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

        // Left without default for compiler complaint on adding more
    }
    // fmt.printf("<>")
}

printTokens :: proc(tokens: []Token) {
    for token in tokens {
        printToken(token)
        fmt.printf("\n")
    }
}

tokenize :: proc(content : string, file: string="") -> [dynamic]Token {
    tok : Tokenizer = {
        text=content[:],
        loc={ 0,0, file[:] },
        i = -1,
    }
    cLen := len(content)
    curLoc : Location
    output : [dynamic]Token = make([dynamic]Token)
    for hasNext(&tok) {
        char, _ := next(&tok)
        switch {
            // Skip Whitespace
            case isWhitespace(char): {}
            // Null terminator catch, just in case
            case char == 0:{}
            case isAlpha(char): {
                append(&output, parseIdent(&tok))
            }
            case isNum(char): { 
                append(&output, parseNumber(&tok))
            }
            case char == '.': { printLoc(tok.loc); notImpl("Number Decimals") }
            case char == '"': { 
                append(&output, parseString(&tok))    
            }
            case char == '/': {
                // Check for comment
                if nextIs(&tok, '/') {
                    // Comment
                    for hasNext(&tok) {
                        toSkip, _ := next(&tok)
                        if toSkip == '\n' {
                            break
                        }
                    }
                }
            }
            
            case: {
                // Check for single symbol tokens
                if char in SymbolTokens {
                    append(&output, Token{SymbolTokens[char], tok.loc, nil})
                } else {
                    // Error
                    printLoc(tok.loc)
                    fmt.printf("Invalid text input\n")
                    os.exit(1)
                }
                
            }
        }
    }
    return output
}

parseIdent :: proc(tok:^Tokenizer) -> Token {
    // Start of word
    startIdx := tok.i
    token : Token = {.Ident, tok.loc, nil}
    // Make sure you don't go past the end
    for hasNext(tok) {
        if nextChar, _ := next(tok); !isAlnum(nextChar) {
            break
        }
    }
    // Handle checking what the token is
    text := tok.text[startIdx:tok.i]
    if text in IdentifierTokens {
        token.type = IdentifierTokens[text]
    } else if text == "true" {
        token.type = .BoolLit
        token.value = true
    } else if text == "false" {
        token.type = .BoolLit
        token.value = false
    } else {
        token.value = text
    }
    return token
}

parseNumber :: proc(tok:^Tokenizer) -> Token {
    token : Token = {
        type = .IntLit,
        loc  = tok.loc,
    }
    value : f32 = 0
    for hasNext(tok) {
        nextChar := curT(tok)
        if !isNum(nextChar) && nextChar != '.' {
            break
        }
        // Eat next character
        next(tok)
        if nextChar == '.' {
            token.type = .FloatLit
            // Read tail end of float
            decimal : i32 = 0
            power : i32 = 1
            // Read the rest of the digits
            for hasNext(tok) {
                if isNum(curT(tok)) {
                    nex := curT(tok)
                    decimal = (decimal * 10) + i32(nex - '0')
                    power *= 10
                } else if nextIs(tok, '.') {
                    fmt.printf("Invalid '.' after decimal of float\n")
                    os.exit(1)
                } else {
                    break
                }
                next(tok)
            }
            token.value = value + f32(decimal) / f32(power)
            return token 
        } else {
            // That means its a digit
            value = (value * 10) + f32(nextChar - '0')
        }
    }
    if token.type == .IntLit {
        token.value = int(value)
    } else if token.type == .FloatLit {
        token.value = f32(value)
    } else {
        assert(false, "BUG: This should not occur")
    }
    return token
}

// No escaping or anything yet
parseString :: proc(tok:^Tokenizer) -> Token {
    token : Token = {
        type = .StringLit,
        loc = tok.loc
    }
    startIdx := tok.i + 1
    // Eat "
    for hasNext(tok) {
        switch val, _ := next(tok); val {
            case '"':{
                // End string
                token.value = tok.text[startIdx:tok.i]
                next(tok)
                return token
            }
            case: {
                // Do nothing
            }
        }
    }
    // Reached end without matching " so error
    printLoc(token.loc)
    fmt.printf("Reached end of input with no matching '\"'\n")
    os.exit(1)
}

notImpl :: proc(msg:string = "") {
    fmt.printf("NOT IMPLEMENTED: %s\n", msg)
    os.exit(1)
}

isAlpha :: proc(char:u8) -> bool {
    return char == '_' || 
        (char >= 'A' && char <= 'Z') || 
        (char >= 'a' && char <= 'z') 
}
isNum :: proc(char:u8) -> bool {
    return char >= '0' && char <= '9'
}
isAlnum :: proc(char:u8) -> bool {
    return isAlpha(char) || isNum(char)
}
isWhitespace :: proc(char:u8) -> bool {
    return char == ' ' || char == '\t' || char == '\r' || char == '\n'
}

nextIs :: proc(tok:^Tokenizer, val:u8) -> bool {
    return hasNext(tok) && curT(tok) == val
}

// Tells if at the end of the input
hasNext :: proc(tok:^Tokenizer) -> bool {
    // "xyz" i:2 len:3 => false 
    return tok.i < len(tok.text)
}

expect :: proc(tok:^Tokenizer, char:u8, skipWhitespace:bool = true) {
    nextChar, ok := next(tok)
    if ok && (isWhitespace(nextChar) && skipWhitespace) {
        // Eat extra whitespace
        for hasNext(tok) {
            if nextChar, _ = next(tok); !isWhitespace(nextChar) {
                break
            }
        }
    }
    if !ok || !hasNext(tok) {
        printLoc(tok.loc)
        fmt.printf("Expected '%c' but got end of input\n", char)
        os.exit(1)
    }
    if nextChar != char {
        printLoc(tok.loc)
        fmt.printf("Expected '%c' but got '%c'\n", char, nextChar)
        os.exit(1)
    }
    return
}

requireNext :: proc(tok:^Tokenizer, cb : proc(u8) -> bool) {
    
}


curT :: proc(tok:^Tokenizer) -> u8 {
    return tok.text[tok.i]
}

// Peek & Consume
next :: proc(tok:^Tokenizer) -> (u8, bool) {
    tok.i += 1
    if !hasNext(tok) do return 0, false
    if tok.text[tok.i] == '\n' {
        tok.loc.line += 1
        tok.loc.col = 0
    } else {
        tok.loc.col += 1
    }
    return tok.text[tok.i], true
}