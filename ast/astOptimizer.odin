package ast

import "core:fmt"

optimizeASTProgram :: proc(program: ^ASTProgram) -> ^ASTProgram {
    state := new(ASTState)
    for _, &glob in program.globalVars {
        optimizeASTHelp(&glob.value, state)
    }
    // Don't need to optimize macros
    /*
    for _, mac in program.macros {
        optimizeASTBlock(mac.body, true)
    }*/
    for _, pr in program.procs {
        optimizeASTBlock(pr.body, true)
    }
    // Since it's required, moved over to resolveProgram
    // hoistVarDecls(program)
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

// Recursively traverse to optimize everything
optimizeASTHelp :: proc(ast:^AST, state:^ASTState) -> (bool) {
    if ast == nil do return false
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
                    v1, isInt1 := getInnerLiteralInt(type.lhs)
                    v2, isInt2 := getInnerLiteralInt(type.rhs)
                    if isInt1 && isInt2 {
                        // Cleanup
                        free(type)
                        pl := new(ASTPushLiteral)
                        pl ^= v1 == v2
                        ast ^= pl
                        return true
                    }
                }
                case .Gt: {
                    v1, isInt1 := getInnerLiteralInt(type.lhs)
                    v2, isInt2 := getInnerLiteralInt(type.rhs)
                    if isInt1 && isInt2 {
                        // Cleanup
                        free(type)
                        pl := new(ASTPushLiteral)
                        pl ^= v1 > v2
                        ast ^= pl
                        return true
                    }
                }
                case .Ge: {
                    v1, isInt1 := getInnerLiteralInt(type.lhs)
                    v2, isInt2 := getInnerLiteralInt(type.rhs)
                    if isInt1 && isInt2 {
                        // Cleanup
                        free(type)
                        pl := new(ASTPushLiteral)
                        pl ^= v1 >= v2
                        ast ^= pl
                        return true
                    }
                }
                case .Lt: {
                    v1, isInt1 := getInnerLiteralInt(type.lhs)
                    v2, isInt2 := getInnerLiteralInt(type.rhs)
                    if isInt1 && isInt2 {
                        // Cleanup
                        free(type)
                        pl := new(ASTPushLiteral)
                        pl ^= v1 < v2
                        ast ^= pl
                        return true
                    }
                }
                case .Le: {
                    v1, isInt1 := getInnerLiteralInt(type.lhs)
                    v2, isInt2 := getInnerLiteralInt(type.rhs)
                    if isInt1 && isInt2 {
                        // Cleanup
                        free(type)
                        pl := new(ASTPushLiteral)
                        pl ^= v1 <= v2
                        ast ^= pl
                        return true
                    }
                }
                case .Ne: {
                    v1, isInt1 := getInnerLiteralInt(type.lhs)
                    v2, isInt2 := getInnerLiteralInt(type.rhs)
                    if isInt1 && isInt2 {
                        // Cleanup
                        free(type)
                        pl := new(ASTPushLiteral)
                        pl ^= v1 != v2
                        ast ^= pl
                        return true
                    }
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
        case ^ASTVarDecl: {}
        case ^ASTDrop: {
            return optimizeASTHelp(&type.value, state)
        }
        case ^ASTIf: {
            return optimizeASTHelp(&type.cond, state) || 
                optimizeASTHelp(&type.body, state) ||
                // TODO: Check this
                optimizeASTHelp(&type.elseBlock, state)

        }
        case ^ASTWhile: {

        }
        // No optimizations
        case ^ASTVarRead: {
            // TODO: If value is never updated, then replace with constant
        }
        case ^ASTVarWrite: {
            // TODO: If never used after this write, then can throw out most of time
            return optimizeASTHelp(&type.value, state)
        }
        case ^ASTPushLiteral, ^ASTVarRef, ^ASTInputParam, ^ASTProcCall: {}
        case ^ASTNip, ^ASTOver, ^ASTRot, ^ASTSwap, ^ASTDup: {}
        case ^ASTProcReturn: {}
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

// Moves all varDecls to the top of their respective function
hoistVarDecls :: proc(program:^ASTProgram) {
    // Do not iterate macros, as they will already be spread into
    //  Where they get used
    for _,pro in program.procs {
        hoistVarDeclsBlock(pro.body)
    }
}

hoistVarDeclsBlock :: proc(blk : ^ASTBlock) {
    // First index that isn't a varDecl
    topIndex := 0
    for i := 0; i < len(blk.nodes); i += 1 {
        #partial switch &type in blk.nodes[i] {
            case ^ASTBlock: {
                // TODO:
                hoistVarDeclsBlock(type)
                // Remove all inner ones and push up

            }
            case ^ASTVarDecl: {
                // Move to top after any other varDecls
                if i == topIndex {
                    topIndex += 1
                    continue
                }
                // Remove current
                elem := blk.nodes[i]
                ordered_remove(&blk.nodes, i)
                // Put it back at new location
                inject_at(&blk.nodes, topIndex, elem)
                topIndex += 1
            }
        }
    }
}