package ast

import "core:fmt"


optimizeAST :: proc(input:[dynamic]AST) -> ([dynamic]AST) {
    for changedSomething := true; changedSomething; {
        // Run again if something was optimized
        changedSomething = false
        for _,idx in input {
            changedSomething ||= optimizeASTHelp(&input[idx])
        }
    }
    return input
}

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
                case .Minus: {
                    v1, isInt1 := getInnerLiteralInt(type.lhs)
                    v2, isInt2 := getInnerLiteralInt(type.rhs)
                    if isInt1 && isInt2 {
                        // Cleanup
                        free(type)
                        pl := new(PushLiteral)
                        pl ^= v1 - v2
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
            changedSomething = optimizeASTHelp(&type.value)
            switch type.op {
                case .CastFloatToInt: {
                    // If is a float literal, then convert manually
                    flLit, isFloat := getInnerLiteralType(type.value, f64)
                    if isFloat {
                        free(type)
                        pl := new(PushLiteral)
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
                        pl := new(PushLiteral)
                        pl ^= f64(intLit)
                        ast ^= pl
                        return true
                    }
                }
            }
            return changedSomething
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

getInnerLiteralType :: proc(ast:AST, $T:typeid) -> (T, bool) {
    lit, isLit := ast.(^PushLiteral)
    if !isLit do return 0, false
    return lit.(T)
}

getInnerLiteral :: proc(ast:AST) -> (PushLiteral, bool)