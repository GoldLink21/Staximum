package ast
import "../tokenizer"
import "../util"
import "core:fmt"
import "core:os"

Token     :: tokenizer.Token
TokenType :: tokenizer.TokenType

// Used instead of manually iterating through tokens
TokWalk :: struct {
    tokens : []Token,
    i: i32,
    loc:util.Location
}

// Looks at the current token
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
// Checks if the next token is in bounds
hasNext :: proc(tw:^TokWalk) -> bool {
    return tw.i + 1 < i32(len(tw.tokens))    
}
// Steps forward in the tokens and gives the new first element
next :: proc(tw: ^TokWalk) -> (Token, bool) {
    tw.i += 1
    if tw.i >= i32(len(tw.tokens)) do return {}, false
    tw.loc = tw.tokens[tw.i].loc
    return tw.tokens[tw.i], true
}
// Check if next is a type and eats it if so
tryNext :: proc(tw:^TokWalk, type:TokenType) -> (Token, bool) {
    tok, ok := peek(tw)
    if ok {
        if tok.type == type {
            tw.i += 1
            tw.loc = tw.tokens[tw.i].loc
            return curr(tw), true
        } else {
            return tok, false
        }
    }
    return curr(tw), false
}
// Expects the next token to be a type
expectNext :: proc(tw:^TokWalk, type:TokenType) -> (Token, util.ErrorMsg) {
    tok, ok := tryNext(tw, type);
    if !ok {
        expected, _ := fmt.enum_value_to_string(type)
        got, _ := fmt.enum_value_to_string(tok.type)
        return tok, util.locStr(tok.loc, 
            "Expected a token of '%s' but got '%s' instead\n",
            expected, got
        )
    }
    return tok, nil
}

