package ast
import "../tokenizer"
import "../util"
import "core:fmt"
import "core:os"

Token     :: tokenizer.Token
TokenType :: tokenizer.TokenType

TokWalk :: struct {
    tokens : []Token,
    i: i32,
}

curr :: proc(tw : ^TokWalk) -> Token {
    // if tw.i >= i32(len(tw.tokens)) do return nil
    return tw.tokens[tw.i]
}
// If the current token is alright
curOk :: proc(tw:^TokWalk) -> bool {
    return tw.i < i32(len(tw.tokens))
}
// Shows next token without consume
peek :: proc(tw:^TokWalk) -> (Token, bool) {
    if !hasNext(tw) do return {}, false
    return tw.tokens[tw.i + 1], true
}
hasNext :: proc(tw:^TokWalk) -> bool {
    return tw.i + 1 < i32(len(tw.tokens))    
}
next :: proc(tw: ^TokWalk) -> (Token, bool) {
    tw.i += 1
    if tw.i >= i32(len(tw.tokens)) do return {}, false
    return tw.tokens[tw.i], true
}
// Check if next is a type and eats it if so
tryNext :: proc(tw:^TokWalk, type:TokenType) -> bool {
    if tok, ok := peek(tw); ok && tok.type == type {
        tw.i += 1
        return true
    }
    return false
}
// Expects the next token to be a type
expectNext :: proc(tw:^TokWalk, type:TokenType) -> util.ErrorMsg {
    if !tryNext(tw, type) {
        return fmt.tprintf("Expected a type of '%s' but got '%s' instead\n")
    }
    return nil
}