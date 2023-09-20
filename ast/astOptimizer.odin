package ast

import "core:fmt"

optimizeASTProgram :: proc(program: ^ASTProgram) -> ^ASTProgram {
    // TODO:
    for _, mac in program.macros {
        optimizeASTBlock(mac.body, true)
    }
    for _, pr in program.procs {
        optimizeASTBlock(pr.body, true)
    }
    return program
}

optimizeASTBlock :: proc(block:^ASTBlock, isProc:=false) -> AST {
    rerun := true
    for rerun {
        rerun = false
        for &node in block.nodes {
            rerun ||= optimizeASTHelp(&node, &block.state)
        }
    }
    // Unwind single element blocks?
    if len(block.nodes) == 1 && !isProc {
        // Can replace with just the individual node
        return block.nodes[0]
    }
    if len(block.nodes) == 0 && !isProc {
        // Can just remove
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
            ast ^= optimizeASTBlock(type)
        }
        case ^ASTVarDef: {
            changedSomething ||= optimizeASTHelp(&type.value, state)
        }
        case ^ASTDrop: {
            changedSomething ||= optimizeASTHelp(&type.value, state)
        }
        // No optimizations
        case ^ASTPushLiteral, ^ASTVarRef, ^ASTInputParam, ^ASTProcCall: {}
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