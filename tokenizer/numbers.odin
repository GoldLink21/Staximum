package tokenizer

import "../util"

// Handles numeric tokens
parseNumber :: proc(tok:^Tokenizer) -> (Token, util.ErrorMsg) {
    // Peek first. If 0, then dispatch where it needs to go
    switch curT(tok) {
        case '0': {
            // Check for escapes to handle
            n, ok := next(tok)
            if !ok {
                // End of input is just 0
                return { .IntLit, tok.loc, 0 }, nil
            }
            switch n {
                case 'x':{
                    // Eat x
                    next(tok)
                    return parseHex(tok)
                }
                case 'o':{
                    // Eat x
                    next(tok)
                    return parseOct(tok)
                }
                case 'b': {
                    // Eat b
                    next(tok)
                    return parseBin(tok)
                }
                case 'r':{
                    // Eat r
                    next(tok)
                    return parseRoman(tok)
                }
                case '0'..='9':{
                    // Any other digit means we should assume it to be decimal
                    return parseDec(tok)
                }
                case ' ', '\n', '\t', '\r':{
                    // End of number, just give one digit 0
                    return { .IntLit, tok.loc, 0 }, nil
                }
                case: {
                    // Error
                    return {}, util.locStr(tok.loc, 
                        "Invalid number type of '%c'", n)
                }
            }
        }
        case '1'..='9': {
            return parseDec(tok)
        }
        case '.': {
            // Eat .
            next(tok)
            // This should be caught before, but its here in case
            return parseFloat(tok, 0, tok.loc)
        }
        case: {
            // 
            return {}, "BUG: Unhandled number case"
        }
    }
}

parseDec :: proc(tok:^Tokenizer) -> (Token, util.ErrorMsg) {
    loc := tok.loc
    value := 0
    getOut := false
    for cur := curT(tok); curGood(tok); cur, _ = next(tok) {
        switch cur {
            case '0'..='9': {
                value = (value * 10) + int(cur - '0')
            }
            // Ignore
            case '_':{}
            case '.':{
                // Eat .
                next(tok)
                return parseFloat(tok, value, loc)
            }
            case: {
                // Must be whitespace or error
                if !isWhitespace(cur) && cur != '{' do return {}, util.locStr(tok.loc, 
                    "Int literal includes invalid character '%c'", cur)
                getOut = true
            }
        }
        if getOut do break
    }
    return { .IntLit, loc, int(value) }, nil

}

isHexChar :: proc(c:u8) -> bool {
    return (c >= '0' && c <= '9') || 
        (c >= 'A' && c <= 'F') || 
        (c >= 'a' && c <= 'f') ||
        // Can have _ to break up things
        c == '_'
}

parseHex :: proc(tok:^Tokenizer) -> (Token, util.ErrorMsg) {
    // After 0x is read. Just parse hex values from there
    loc := tok.loc
    value, hadVal := 0, false
    getOut := false
    for cur := curT(tok); curGood(tok); cur, _ = next(tok) {
        switch cur {
            case '0'..='9': {
                value = (value * 16) + int(cur - '0')
                hadVal = true
            }
            // Upper case
            case 'A'..='F': {
                value = (value * 16) + int(cur - 'A' + 10)
                hadVal = true
            }
            // Lower case
            case 'a'..='f': {
                value = (value * 16) + int(cur - 'a' + 10)
                hadVal = true
            }
            case '_':{
                // Ignore
            }
            case: {
                // Must be whitespace or error
                if !isWhitespace(cur) && cur != '{' do return {}, util.locStr(tok.loc, 
                    "Hex literal includes invalid character '%c'", cur)
                getOut = true
            }
        }
        if getOut do break
    }
    if !hadVal do return {}, util.locStr(loc, 
        "Hex value must have something after '0x'")
    return { .IntLit, loc, int(value) }, nil
}

parseOct :: proc(tok:^Tokenizer) -> (Token, util.ErrorMsg) {
    // After 0o is read. Just parse oct values from there
    loc := tok.loc
    value, hadVal := 0, false
    getOut := false
    for cur := curT(tok); curGood(tok); cur, _ = next(tok) {
        switch cur {
            case '0'..='7': {
                value, hadVal = (value * 8) + int(cur - '0'), true
            }
            // Ignore
            case '_':{}
            case: {
                // Must be whitespace or error
                if !isWhitespace(cur) && cur != '{' do return {}, util.locStr(tok.loc, 
                    "Octal literal includes invalid character '%c'", cur)
                getOut = true
            }
        }
        if getOut do break
    }
    if !hadVal do return {}, util.locStr(loc, 
        "Octal value must have something after '0o'")
    return { .IntLit, loc, int(value) }, nil
}

romanValues : map[u8]int = {
    'i' = 1,    'I' = 1,
    'v' = 5,    'V' = 5,
    'x' = 10,   'X' = 10,
    'l' = 50,   'L' = 50,
    'c' = 100,  'C' = 100,
    'd' = 500,  'D' = 500,
    'm' = 1000, 'M' = 1000,
}

parseRoman :: proc(tok:^Tokenizer) -> (Token, util.ErrorMsg) {
    /*
    First char can be less than next, which means subtract from next. 
    Can have at most 
    */
    loc := tok.loc
    startIdx := tok.i
    lastIdx := 0
    // Get string of roman numeral
    for cur := curT(tok); curGood(tok); cur, _ = next(tok) {
        switch {
            // Do nothing
            case cur in romanValues: {}
            case cur == '_': {
                return {}, util.locStr(tok.loc, 
                    "'_' is not supported in roman numeral literals")
            }
            case isWhitespace(cur) || cur == '{': {
                // Okay, just exit
                lastIdx = tok.i
            }
            case: {
                return {}, util.locStr(tok.loc, 
                    "Roman Numeral literal includes invalid character '%c'", 
                    cur)
            }
        }
        if lastIdx != 0 do break
    }
    // Catch end of input errors
    if !curGood(tok) {
        lastIdx = tok.i
    }
    if startIdx >= lastIdx {
        return {}, util.locStr(tok.loc, 
            "Roman Numeral literal needs more than 0r")
    }
    roman := tok.text[startIdx:lastIdx]
    // Evaluate roman numeral
    value := 0
    i := 0
    for ; i < len(roman) - 1; i += 1 {
        v1 := romanValues[roman[i]]
        v2 := romanValues[roman[i + 1]]
        if v1 < v2 {
            value += (v2 - v1)
            i += 1
        } else {
            value += v1
        }
    }
    if i != len(roman) {
        value += romanValues[roman[i]]
    }
    return {.IntLit, loc, value}, nil
}

parseBin :: proc(tok:^Tokenizer) -> (Token, util.ErrorMsg) {
    // After 0b is read. Just parse bin values from there
    loc := tok.loc
    value, hadVal := 0, false
    getOut := false
    for cur := curT(tok); curGood(tok); cur, _ = next(tok) {
        switch cur {
            case '0', '1': {
                value, hadVal = (value * 2) + int(cur - '0'), true
            }
            // Ignore
            case '_':{}
            case: {
                // Must be whitespace or error
                if !isWhitespace(cur) && cur != '{' do return {}, util.locStr(tok.loc, 
                    "Binary literal includes invalid character '%c'", cur)
                getOut = true
            }
        }
        if getOut do break
    }
    if !hadVal do return {}, util.locStr(loc, 
        "Binary value must have something after '0b'")
    return { .IntLit, loc, int(value) }, nil
}

parseFloat :: proc(tok:^Tokenizer, beforeValue:int, startLoc:util.Location) -> (Token, util.ErrorMsg) {
    // If . then end of input, catch it
    if !curGood(tok) {
        return {.FloatLit, startLoc, f64(beforeValue)}, nil
    }
    value, pow : f64 = 0, 1
    getOut := false
    for cur := curT(tok); curGood(tok); cur, _ = next(tok) {
        switch cur {
            case '0'..='9': {
                value = (value * 10) + f64(cur - '0')
                pow *= 10
            }
            // Ignore
            case '_':{}
            case: {
                // Must be whitespace or error
                if !isWhitespace(cur) && cur != '{' do return {}, util.locStr(tok.loc, 
                    "Float literal includes invalid character '%c'", cur)
                getOut = true
            }
        }
        if getOut do break
    }
    return { .FloatLit, startLoc, f64(beforeValue) + value/pow }, nil
}