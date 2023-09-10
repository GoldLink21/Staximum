package ast

import "core:fmt"


optimizeAST :: proc(input:[dynamic]AST, state:^ASTState) -> ([dynamic]AST) {
    for changedSomething := true; changedSomething; {
        // Run again if something was optimized
        changedSomething = false
        for _,idx in input {
            changedSomething ||= optimizeASTHelp(&input[idx], state)
        }
    }
    return input
}

optimizeASTBlock :: proc(block:^ASTBlock) -> ^ASTBlock {
    rerun := true
    for rerun {
        rerun = false
        for &node in block.nodes {
            rerun ||= optimizeASTHelp(&node, &block.state)
        }
    }
    return block
}

optimizeASTHelp :: proc(ast:^AST, state:^ASTState) -> (bool) {
    changedSomething := false
    switch type in ast {
        case ^ASTBinOp: {
            // Optimize inner parts
            changedSomething = 
                optimizeASTHelp(&type.lhs, state) ||
                optimizeASTHelp(&type.rhs, state)
            switch type.op {
                case .Plus: {
                    v1, isInt1 := getInnerLiteralInt(type.lhs)
                    v2, isInt2 := getInnerLiteralInt(type.rhs)
                    if isInt1 && isInt2 {
                        // Cleanup
                        free(type)
                        pl := new(ASTPushLiteral)
                        pl ^= v1 + v2
                        ast ^= pl
                        return true
                    }
                }
                case .Minus: {
                    v1, isInt1 := getInnerLiteralInt(type.lhs)
                    v2, isInt2 := getInnerLiteralInt(type.rhs)
                    if isInt1 && isInt2 {
                        // Cleanup
                        free(type)
                        pl := new(ASTPushLiteral)
                        pl ^= v1 - v2
                        ast ^= pl
                        return true
                    }
                }
                case .Eq: {
                    
                }
            }
        }
        case ^ASTUnaryOp: {
            changedSomething = optimizeASTHelp(&type.value, state)
            switch type.op {
                case .CastFloatToInt: {
                    // If is a float literal, then convert manually
                    flLit, isFloat := getInnerLiteralType(type.value, f64)
                    if isFloat {
                        free(type)
                        pl := new(ASTPushLiteral)
                        pl ^= int(flLit)
                        ast ^= pl
                        return true
                    }
                }

                case .CastIntToFloat: {
                    // If is an int literal, then convert manually
                    intLit, isInt := getInnerLiteralType(type.value, int)
                    if isInt {
                        free(type)
                        pl := new(ASTPushLiteral)
                        pl ^= f64(intLit)
                        ast ^= pl
                        return true
                    }
                }
            }
        }
        case ^ASTSyscall0: {
            return optimizeASTHelp(&type.call, state)
        }
        case ^ASTSyscall1: {
            return optimizeASTHelp(&type.call, state) ||
                optimizeASTHelp(&type.arg1, state)

        }
        case ^ASTSyscall2: {
            return optimizeASTHelp(&type.call, state) ||
                optimizeASTHelp(&type.arg1, state) ||
                optimizeASTHelp(&type.arg2, state)
                
        }
        case ^ASTSyscall3: {
            return optimizeASTHelp(&type.call, state) ||
                optimizeASTHelp(&type.arg1, state) ||
                optimizeASTHelp(&type.arg2, state) ||
                optimizeASTHelp(&type.arg3, state)
        }
        case ^ASTBlock: {
            for &node in type.nodes {
                changedSomething ||= optimizeASTHelp(&node, state)
            }
            // Remove unused vars
        }
        // No optimizations
        case ^ASTPushLiteral, ^ASTDrop, ^ASTVarRef: {}
    }
    return changedSomething
}

getInnerLiteralInt :: proc(ast:AST) -> (int, bool) {
    lit, isLit := ast.(^ASTPushLiteral)
    if !isLit do return 0, false
    return lit.(int)
}

getInnerLiteralType :: proc(ast:AST, $T:typeid) -> (T, bool) {
    lit, isLit := ast.(^ASTPushLiteral)
    if !isLit do return 0, false
    return lit.(T)
}

// getInnerLiteral :: proc(ast:AST) -> (ASTPushLiteral, bool)