package tests

import "../tokenizer"
import "core:testing"
import "core:fmt"

T :: testing.T
Token :: tokenizer.Token
TokenType :: tokenizer.TokenType
TokenValue :: tokenizer.TokenValue

@(test)
testLits :: proc(t:^testing.T) {
    validTest(t, "1", {
        {.IntLit, 1},
    })
    validTest(t, "2.", {
        {.FloatLit, 2.0},
    })
    invalidTest(t, ".")
    validTest(t, "-3",{
        {.IntLit, -3}
    })
    validTest(t, "-1.234",{
        {.FloatLit, -1.234}
    })
    validTest(t, "-.6789",{
        {.FloatLit, -0.6789}
    })
    validTest(t, "\"xyz\"", {
        {.StringLit, "xyz"}
    })
    invalidTest(t, "\"there is no end")
    invalidTest(t, "\"bad escape\\c\"")
    invalidTest(t, "\"No escape at end\\")

}

@(test)
testOps :: proc(t:^testing.T) {
    validTest(t, "1 2 +", {
        {.IntLit, 1},
        {.IntLit, 2},
        {.Plus, nil},
    })
    validTest(t, "1 2 -", {
        {.IntLit, 1},
        {.IntLit, 2},
        {.Dash, nil},
    })
    validTest(t, "12 40 syscall1", {
        {.IntLit, 12},
        {.IntLit, 40},
        {.Syscall1, nil},
    })
    validTest(t, "- + { } ( ) !", {
        {.Dash, nil},
        {.Plus, nil},
        {.OBrace, nil},
        {.CBrace, nil},
        {.OParen, nil},
        {.CParen, nil},
        {.Bang, nil},
    })
}

@(test)
testFails :: proc(t:^T) {

}

validTest :: proc(t:^T, input:string, typeVals:[]struct{type:TokenType, val:TokenValue}, 
    loc := #caller_location) -> bool 
{
    tokens, err := tokenizer.tokenize(input)
    defer delete(tokens)
    if err != nil {
        testing.fail_now(t, "Got a parsing error")
        return false
    }
    if !testing.expect_value(t, len(tokens), len(typeVals), loc) {
        testing.fail_now(t, "Did not get the right number of tokens")
        return false
    }
    for tv, i in typeVals {
        isType(t, tokens[i], tv.type, tv.val, loc) or_return
    }
    return true
}

invalidTest :: proc(t:^T, input:string) {
    tokens, err := tokenizer.tokenize(input)
    defer delete(tokens)
    if err == nil {
        testing.fail_now(t, "Expected to fail at parsing, but didn't")
    }
}

isType :: proc(t:^T, tok:Token, type:TokenType, val:TokenValue = nil, loc:=#caller_location) -> bool {
    if tok.type != type {
        exp, _ := fmt.enum_value_to_string(type)
        got, _ := fmt.enum_value_to_string(tok.type)
        testing.errorf(t, "Mismatched types. Expected '%s' but got '%s'",
            exp, got
        )
        return false
    }
    if val != nil {
        return testing.expect_value(t, tok.value, val, loc)
    }
    return true
}