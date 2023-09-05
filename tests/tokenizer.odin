package tests

import "../tokenizer"
import "core:testing"

T :: testing.T
Token :: tokenizer.Token
TokenType :: tokenizer.TokenType
TokenValue :: tokenizer.TokenValue

@(test)
test1 :: proc(t:^testing.T) {
    tokens := tokenizer.tokenize("1")
    defer delete(tokens)
    testing.expect_value(t, len(tokens), 1)
    isType(t, tokens[0], .IntLit, 1)
}

@(test)
test2 :: proc(t:^testing.T) {
    tokens := tokenizer.tokenize("1 2 +")
    defer delete(tokens)
    testing.expect_value(t, len(tokens), 3)
    checkTypes(t, "1 2 +", 
        {.IntLit, 1},
        {.IntLit, 2},
        {.Plus, nil})
}

checkTypes :: proc(t:^T, input:string, typeVals:..struct{type:TokenType, val:TokenValue}) {
    tokens := tokenizer.tokenize(input)
    defer delete(tokens)
    testing.expect_value(t, len(tokens), len(typeVals))
    for tv, i in typeVals {
        isType(t, tokens[i], tv.type, tv.val)
    }
}

isType :: proc(t:^T, tok:Token, type:TokenType, val:TokenValue = nil) {
    testing.expect_value(t, tok.type, type)
    if val != nil {
        testing.expect_value(t, tok.value, val)
    }
}