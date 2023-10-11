package tokenizer

import "core:fmt"
import "core:os"
import "core:strings"
import "../util"
import "../types"

Location :: util.Location

Token :: struct {
    type : TokenType,
    loc: Location,
    value: TokenValue 
}

// Helps handling going from token to token
Tokenizer :: struct {
    text : string,
    loc: Location,
    i: int,
    // This is the last column before last character
    oldCol: int,
}

// Opens file, tokenizes and returns
tokenizeFile :: proc(fileName: string) -> (output:[dynamic]Token = nil, err:util.ErrorMsg) {
    textBytes, ok := os.read_entire_file_from_filename(fileName)
    if !ok {
        return nil, fmt.tprintf("Could not open file '%s'\n", fileName)
    }
    text := string(textBytes)
    return tokenize(text, fileName)
}

// Returns true if the tokenizer currently points at a comment
checkComment :: proc(tok: ^Tokenizer) -> bool {
    cur := curT(tok)
    if cur == '/' {
        nextT, hasN := peekNext(tok)
        if hasN && nextT == '/' {
            return true
        }
    }
    return false
}

// Tokenize a string. File is used solely for debugging
tokenize :: proc(content : string, file: string="") -> (output:[dynamic]Token, errMsg:util.ErrorMsg) {
    // TODO: Fix up the curT, next, curGood naming to be more clear
    tok : Tokenizer = {
        text=content[:],
        loc={ 1,1, file[:] },
        i = 0,
        oldCol = 0,
    }
    output = make([dynamic]Token)
    for char := curT(&tok); curGood(&tok); char, _ = next(&tok) {
        switch {
            // Skip Whitespace
            case isWhitespace(char), char == 0: {}
            case char == '{': {
                append(&output, Token{.OBrace, tok.loc, nil})
            }
            case char == '.': { 
                // Decimals
                if val, _ := peekNext(&tok); isNum(val) {
                    token := parseNumber(&tok) or_return
                    append(&output, token)
                    continue
                }
                return output, util.locStr(tok.loc, 
                    "Expected number after decimal point\n")
            }
            case isNum(char): {
                token := parseNumber(&tok) or_return
                append(&output, token)
            }
            // Checking for negative numbers
            case char == '-': {
                token := handleDash(&tok) or_return
                append(&output, token)
            }
            case char == '"': {
                token := parseString(&tok) or_return
                append(&output, token)    
            }
            case char == '/' && nextIs(&tok, '/'): {
                // Comment
                for curGood(&tok) {
                    toSkip, _ := next(&tok)
                    if toSkip == '\n' {
                        break
                    }
                }
            }
            case char == '/' && nextIs(&tok, '*'): {
                // Block Comment
                nestLevel := 1
                next(&tok)
                for curGood(&tok) {
                    toSkip, _ := next(&tok)
                    if toSkip == '*' && nextIs(&tok, '/') {
                        next(&tok)
                        nestLevel -= 1
                        if nestLevel == 0 do break
                    } else if toSkip == '/' && nextIs(&tok, '*') {
                        fmt.printf("Increased comment block\n")
                        nestLevel += 1
                    }                    
                }
            }
            
            case char == '(': {
                // Casting
                loc := tok.loc
                start := tok.i
                // Read until ')'
                for curGood(&tok) {
                    toSkip, _ := next(&tok)
                    if toSkip == ')' {
                        break
                    }
                }
                if !curGood(&tok) {
                    return nil, "Reached End of input when expecing ')'\n"
                }
                str := strings.trim(tok.text[start+1:tok.i], " ")
                if str in types.StringToType {
                    append(&output, Token{.Cast, loc, types.StringToType[str]})
                } else {
                    return nil, util.locStr(tok.loc, 
                        "Invalid type of '%s'", str)
                }
            }
            case: {
                parseIdent(&tok, &output) or_return
            }
        }
    }
    return output, nil
}

// Handles loose text tokens and appends it
parseIdent :: proc(tok:^Tokenizer, output:^[dynamic]Token) -> (util.ErrorMsg) {
    // Start of word
    startIdx := tok.i
    token : Token = {.Ident, tok.loc, nil}
    // Make sure you don't go past the end
    for cur:= curT(tok); curGood(tok); cur, _ = next(tok) {
        if nextChar, _ := peekNext(tok); isWhitespace(nextChar) || 
            // Also break on braces
            nextChar == '{' || nextChar == '}' {
            break
        } else if checkComment(tok) {
            tok.i -= 1
            break
        }
    }
    text : string = ---
    // Handle checking what the token is
    if tok.i >= len(tok.text) {
        text = tok.text[startIdx:len(tok.text)]
    } else {
        text = tok.text[startIdx:tok.i+1]
    }
    if text in IdentifierTokens {
        // Just a string that is a token value
        token.type = IdentifierTokens[text]
    } else if text == "true" {
        token.type = .BoolLit
        token.value = true
    } else if text == "false" {
        token.type = .BoolLit
        token.value = false
    } else if text == ":>" {
        // Split up into two tokens
        token.type = .Gt
        append(output, Token{.Colon,tok.loc,nil})
        tok.loc.col += 1
    } else if text in types.StringToType {
        token.type = .Type
        token.value = types.StringToType[text]
    } else {
        token.value = text
    }
    // Add back next char
    append(output, token)
    return nil
}

// Handles numeric tokens
parseNumber :: proc(tok:^Tokenizer) -> (Token, util.ErrorMsg) {
    token : Token = {
        type = .IntLit,
        loc  = tok.loc,
    }
    value : f64 = 0
    for curGood(tok) {
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
            for curGood(tok) {
                if isNum(curT(tok)) {
                    nex := curT(tok)
                    decimal = (decimal * 10) + i32(nex - '0')
                    power *= 10
                } else if curIs(tok, '.') {
                    return token, util.locStr(tok.loc, 
                        "Invalid '.' after decimal of float")
                } else {
                    break
                }
                next(tok)
            }
            token.value = value + f64(decimal) / f64(power)
            return token, nil
        } else {
            // That means its a digit
            value = (value * 10) + f64(nextChar - '0')
        }
    }
    if token.type == .IntLit {
        token.value = int(value)
    } else if token.type == .FloatLit {
        token.value = f64(value)
    } else {
        assert(false, "BUG: This should not occur")
    }
    goBack(tok)
    return token, nil
}

// Handles string literals
parseString :: proc(tok:^Tokenizer) -> (Token, util.ErrorMsg) {
    token : Token = {
        type = .StringLit,
        loc = tok.loc
    }
    startIdx := tok.i + 1

    sb : strings.Builder
    // Eat "
    for curGood(tok) {
        switch val, _ := next(tok); val {
            case '"':{
                // End string
                strings.write_string(&sb, tok.text[startIdx:tok.i])
                token.value = strings.clone(strings.to_string(sb))
                next(tok)
                return token, nil
            }
            case '\\': {
                escapeVal, ok := next(tok)
                if !ok {
                    return token, util.locStr(tok.loc, 
                        "Reached end of input within string escape")
                }
                strings.write_string(&sb, tok.text[startIdx:tok.i - 1])
                startIdx = tok.i + 1
                switch escapeVal {
                    case 'r': strings.write_byte(&sb, '\r')
                    case 'n': strings.write_byte(&sb, '\n')
                    case 't': strings.write_byte(&sb, '\t')
                    case '0': strings.write_byte(&sb, 0)
                    case '"', '\\': strings.write_byte(&sb, escapeVal)
                    case: {
                        return token, util.locStr(tok.loc, 
                            "Invalid escape character of '%c'", escapeVal)
                    }
                }
            }
            case: {
                // Do nothing
            }
        }
    }
    // Reached end without matching " so error
    return token, util.locStr(tok.loc, 
        "Reached end of input with no matching '\"'")
}

// Handle tokens that start with '-'
handleDash :: proc(tok:^Tokenizer) -> (token:Token, err:util.ErrorMsg) {
    // First check for negative numbers
    if curGood(tok) {
        if val, _ := peekNext(tok); isNum(val) || val == '.' {
            next(tok)
            token = parseNumber(tok) or_return
            switch type in token.value {
                case int: { token.value = -1 * type }
                case f64: { token.value = -1 * type }
                case bool, string, types.Type: {
                    return token, "BUG: Parsing number but got bool, string, or Type\n"
                }
            }
            return token, nil
        } else if !isWhitespace(val) && val != 0 {
            // Something not number related
            return {}, util.locStr(tok.loc, "Invalid character of '%c' following '-'", val)
        }                    
    }
    // Just a dash then
    return Token{.Dash,tok.loc,nil}, nil
}

// Alpha is A-z and _
isAlpha :: proc(char:u8) -> bool {
    return char == '_' || 
        (char >= 'A' && char <= 'Z') || 
        (char >= 'a' && char <= 'z') 
}
// Num is 0-9
isNum :: proc(char:u8) -> bool {
    return char >= '0' && char <= '9'
}
isAlnum :: proc(char:u8) -> bool {
    return isAlpha(char) || isNum(char)
}
// Whitespace is ' ', tab, newline and carridge return
isWhitespace :: proc(char:u8) -> bool {
    return char == ' ' || char == '\t' || char == '\r' || char == '\n'
}

// Checks if the current token is ok and is a specific value
curIs :: proc(tok:^Tokenizer, val:u8) -> bool {
    return curGood(tok) && curT(tok) == val
}

// Tells if not at the end of the input
curGood :: proc(tok:^Tokenizer) -> bool {
    // "xyz" i:2 len:3 => false 
    return tok.i < len(tok.text)
}

expect :: proc(tok:^Tokenizer, char:u8, skipWhitespace:bool = true) -> util.ErrorMsg {
    nextChar, ok := next(tok)
    // Skip whitespace if that is wanted
    if ok && (isWhitespace(nextChar) && skipWhitespace) {
        // Eat extra whitespace
        for curGood(tok) {
            if nextChar, _ = next(tok); !isWhitespace(nextChar) {
                break
            }
        }
    }
    // Make sure you are in bounds
    if !ok || !curGood(tok) {
        return util.locStr(tok.loc, 
            "Expected '%c' but got end of input", char)
    }
    if nextChar != char {
        return util.locStr(tok.loc, 
            "Expected '%c' but got '%c'\n", char, nextChar)
    }
    return nil
}

// Look at current element
curT :: proc(tok:^Tokenizer) -> u8 {
    return tok.text[tok.i]
}
// Look at next element
peekNext :: proc(tok:^Tokenizer) -> (u8, bool) {
    if tok.i + 1 >= len(tok.text) do return 0, false
    return tok.text[tok.i + 1], true
}
nextIs :: proc(tok:^Tokenizer, val:u8) -> (bool) {
    if tok.i + 1 >= len(tok.text) do return false
    return tok.text[tok.i + 1] == val
}
goBack :: proc(tok:^Tokenizer) {
    tok.i -= 1
    if tok.text[tok.i] == '\n' {
        tok.loc.col = uint(tok.oldCol)
        tok.loc.line -= 1
    } else {
        tok.loc.col -= 1
    }
}

// Peek & Consume
next :: proc(tok:^Tokenizer) -> (u8, bool) {
    tok.i += 1
    if !curGood(tok) do return 0, false
    if tok.text[tok.i] == '\n' {
        tok.loc.line += 1
        tok.oldCol = int(tok.loc.col)
        tok.loc.col = 0
    } else {
        tok.oldCol = int(tok.loc.col)
        tok.loc.col += 1
    }
    return tok.text[tok.i], true
}