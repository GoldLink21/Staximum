package ast

// Tells if you need to keep optimizing
changedSomething := true

optimizeAST :: proc(input:[dynamic]AST) -> [dynamic]AST {
    for changedSomething {
        changedSomething = false
    for ast in input {
        switch type in ast {
            case ^BinOp: {

            }
            case ^UnaryOp: {

            }
            case ^PushLiteral: {

            }
            case ^Syscall1: {

            }
            case ^Syscall3: {

            }
        }
    }}
    return nil
}