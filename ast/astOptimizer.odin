package ast

import "core:fmt"


optimizeAST :: proc(input:[dynamic]AST) -> ([dynamic]AST) {
    for changedSomething := true; changedSomething; {
        changedSomething = false
        for _,idx in input {
            changedSomething ||= optimizeASTHelp(&input[idx])
        }
    }
    return input
}

// TODO: Currently broken
optimizeASTHelp :: proc(ast:^AST) -> (bool) {
    changedSomething := false
    switch type in ast {
        case ^BinOp: {
            // Optimize inner parts
            changedSomething = 
                optimizeASTHelp(&type.lhs) ||
                optimizeASTHelp(&type.rhs)
            switch type.op {
                case .Plus: {
                    v1, isInt1 := getInnerLiteralInt(type.lhs)
                    v2, isInt2 := getInnerLiteralInt(type.rhs)
                    if isInt1 && isInt2 {
                        // Cleanup
                        free(type)
                        pl := new(PushLiteral)
                        pl ^= v1 + v2
                        ast ^= pl
                        return true
                    }
                }
                case .Eq: {
                    
                }
            }
            return changedSomething
        }
        case ^UnaryOp: {
            return optimizeASTHelp(&type.value)
        }
        case ^Syscall0: {
            return optimizeASTHelp(&type.call)
        }
        case ^Syscall1: {
            return optimizeASTHelp(&type.call) ||
                optimizeASTHelp(&type.arg1)

        }
        case ^Syscall2: {
            return optimizeASTHelp(&type.call) ||
                optimizeASTHelp(&type.arg1) ||
                optimizeASTHelp(&type.arg2)
                
        }
        case ^Syscall3: {
            return optimizeASTHelp(&type.call) ||
                optimizeASTHelp(&type.arg1) ||
                optimizeASTHelp(&type.arg2) ||
                optimizeASTHelp(&type.arg3)
        }
        // No optimizations
        case ^PushLiteral, ^Drop: {}
    }
    return false
}

getInnerLiteralInt :: proc(ast:AST) -> (int, bool) {
    lit, isLit := ast.(^PushLiteral)
    if !isLit do return 0, false
    return lit.(int)
}