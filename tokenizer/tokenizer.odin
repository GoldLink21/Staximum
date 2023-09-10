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
}

// Tokenize a string. File is used solely for debugging
tokenize :: proc(content : string, file: string="") -> (output:[dynamic]Token, errMsg:util.ErrorMsg) {
    // TODO: Fix up the curT, next, curGood naming to be more clear
    tok : Tokenizer = {
        text=content[:],
        loc={ 1,1, file[:] },
        i = 0,
    }
    output = make([dynamic]Token)
    for char := curT(&tok); curGood(&tok); char, _ = next(&tok) {
        switch {
            // Skip Whitespace
            case isWhitespace(char), char == 0: {}
            case isAlpha(char): {
                token := parseIdent(&tok) or_return
                append(&output, token)
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
            case char == '-': {
                token := handleDash(&tok) or_return
                append(&output, token)
            }
            case char == '"': {
                token := parseString(&tok) or_return
                append(&output, token)    
            }
            case char == '/' && curIs(&tok, '/'): {
                // Comment
                for curGood(&tok) {
                    toSkip, _ := next(&tok)
                    if toSkip == '\n' {
                        break
                    }
                }
            }
            case: {
                // Check for single symbol tokens
                if char in SymbolTokens {
                    append(&output, Token{SymbolTokens[char], tok.loc, nil})
                } else {
                    // Error
                    return output, util.locStr(tok.loc, 
                        "Invalid Text input")
                }
            }
        }
    }
    return output, nil
}

// Handles loose text tokens
parseIdent :: proc(tok:^Tokenizer) -> (Token, util.ErrorMsg) {
    // Start of word
    startIdx := tok.i
    token : Token = {.Ident, tok.loc, nil}
    // Make sure you don't go past the end
    for cur:= curT(tok); curGood(tok); cur, _ = next(tok) {
        if nextChar, _ := peekNext(tok); !isAlnum(nextChar) {
            break
        }
    }
    // Handle checking what the token is
    text := tok.text[startIdx:tok.i+1]
    if text in IdentifierTokens {
        // Just a string that is a token value
        token.type = IdentifierTokens[text]
    } else if text == "true" {
        token.type = .BoolLit
        token.value = true
    } else if text == "false" {
        token.type = .BoolLit
        token.value = false
    } else if text in types.StringToType {
        token.type = .Type
        token.value = types.StringToType[text]
    } else {
        token.value = text
    }
    // Add back next char
    return token, nil
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

// Peek & Consume
next :: proc(tok:^Tokenizer) -> (u8, bool) {
    tok.i += 1
    if !curGood(tok) do return 0, false
    if tok.text[tok.i] == '\n' {
        tok.loc.line += 1
        tok.loc.col = 0
    } else {
        tok.loc.col += 1
    }
    return tok.text[tok.i], true
}