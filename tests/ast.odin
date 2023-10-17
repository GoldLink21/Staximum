package tests
import "../ast"
import "../tokenizer"
import "../types"
import "core:testing"
import "core:fmt"

AST :: ast.AST


testTokenToAST :: proc(t:^T, inTokens: []Token, expectedAST:[dynamic]AST, loc:=#caller_location) {
    tw : ast.TokWalk = { inTokens, 0 , inTokens[0].loc }
    ts := make([dynamic]types.Type)
    program := ast.ASTProgram{}
    vars := make(map[string]ast.Variable)
    curAST := make([dynamic]AST)
    for _, err := ast.resolveNextToken(&tw, &ts, &program, &vars, &curAST); 
        int(tw.i) < len(tw.tokens); 
        _, err = ast.resolveNextToken(&tw, &ts, &program, &vars, &curAST) {
            
        if err != nil {
            testing.fail(t, loc)
            return
        }
    }
    if len(expectedAST) != len(curAST) {
        testing.fail(t, loc)
        return
    }
}