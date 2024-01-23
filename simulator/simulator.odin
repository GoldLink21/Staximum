package simulator

import "core:fmt"

import "../ast"
import "../types"
import "../util"

ErrorMsg :: util.ErrorMsg
Type :: types.Type

PtrValue :: ^any

ExitCode : int = 0

Value :: struct {
    type:types.Type,
    value:union {
        int,
        PtrValue,
        f64,
        bool,
        string
    }
}

VariableFrame :: map[string]Value

Program :: struct {
    ast: ^ast.ASTProgram,
    stack: [dynamic]Value,
    variables: [dynamic]VariableFrame
}

newVariableFrame :: proc(prg:^Program) {
    frame := new(VariableFrame)
    append(&prg.variables, frame^)
}
dropVariableFrame :: proc(prg:^Program) {
    oldFrame := pop(&prg.variables)
    delete(oldFrame)
}
defineVariable :: proc(prg:^Program, name:string, type:Type) {
    prg.variables[len(prg.variables) - 1][name] = { type, nil }
}
getVariable :: proc(prg:^Program, name:string) -> ^Value {
    // Read backwards because you are more likely to access current framed vars
    #reverse for frame in prg.variables {
        if name in frame {
            return &frame[name]
        }
    }
    return nil
}
setVariable :: proc(prg:^Program, name:string, newValue: Value) -> ErrorMsg {
    #reverse for frame in &prg.variables {
        if name in &frame {
            if frame[name].type != newValue.type {
                return "Setting variable to incorrect type\n"
            }
            (&frame[name]).value = newValue.value
            return nil
        }
    }
    return "Invalid variable name\n"
}

simulateProgram :: proc(program: ^ast.ASTProgram) -> (ErrorMsg) {
    prg := Program {
        ast = program,
        stack = make([dynamic]Value),
        variables = make([dynamic]VariableFrame)
    }
    // Check for main and run it
    if "main" not_in program.procs {
        return "No main proc exists\n"
    }
    simulateProcCall(&prg, program.procs["main"]) or_return
    return nil
}

simulateProcCall :: proc(prg: ^Program, pr: ^ast.Procedure) -> ErrorMsg {
    simulateAST(prg, pr.body) or_return
    return nil
}

simulateAST :: proc(prg: ^Program, node:ast.AST) -> ErrorMsg {
    if node == nil { return nil }
    switch type in node {
        case ^ast.ASTPushLiteral: {
            switch lit in type {
                case int: {
                    append(&prg.stack, Value{.Int, lit})
                }
                case f64: {
                    append(&prg.stack, Value{.Float, lit})
                }
                case bool: {
                    append(&prg.stack, Value{.Bool, lit})
                }
                case string: {
                    append(&prg.stack, Value{.Int, len(lit)})
                    append(&prg.stack, Value{.Ptr, PtrValue(&lit)})
                }
            }
        }
        case ^ast.ASTInputParam: {
            assert(false, "TODO input param")
        }
        case ^ast.ASTUnaryOp: {
            switch type.op {
                case .CastFloatToInt: {
                    val := getInnerFloat(pop(&prg.stack)) or_return
                    append(&prg.stack, Value{.Int, int(val)})
                }
                case .CastIntToFloat: {
                    val := getInnerInt(pop(&prg.stack)) or_return
                    append(&prg.stack, Value{.Float, f64(val)})
                }
            }
        }
        case ^ast.ASTBinOp: {
            simulateAST(prg, type.lhs)
            simulateAST(prg, type.rhs)
            rhs := pop(&prg.stack)
            lhs := pop(&prg.stack)
            val : Value = {}
            switch type.op {
                case .Plus: {
                    assert(false, "TODO: BinOp +")
                }
                case .Minus: {
                    assert(false, "TODO: BinOp -")
                }
                case .Eq: {
                    cmp := compareValues(lhs, rhs)
                    if .Eq in cmp {
                        val = {.Bool, true}
                    } else {
                        val = {.Bool, false}
                    }
                }
                case .Ge: {
                    cmp := compareValues(lhs, rhs)
                    if .Eq in cmp || .Gt in cmp {
                        val = {.Bool, true}
                    } else {
                        val = {.Bool, false}
                    }
                }
                case .Gt: {
                    cmp := compareValues(lhs, rhs)
                    if .Gt in cmp {
                        val = {.Bool, true}
                    } else {
                        val = {.Bool, false}
                    }
                }
                case .Le: {
                    cmp := compareValues(lhs, rhs)
                    if .Eq in cmp || .Lt in cmp {
                        val = {.Bool, true}
                    } else {
                        val = {.Bool, false}
                    }
                }
                case .Lt: {
                    cmp := compareValues(lhs, rhs)
                    if .Lt in cmp {
                        val = {.Bool, true}
                    } else {
                        val = {.Bool, false}
                    }
                }
                case .Ne: {
                    cmp := compareValues(lhs, rhs)
                    if .Eq not_in cmp {
                        val = {.Bool, true}
                    } else {
                        val = {.Bool, false}
                    }
                }
            }
            append(&prg.stack, val)
        }
        case ^ast.ASTSyscall0: {
            simulateAST(prg, type.call) or_return
            call := getInnerInt(Value(pop(&prg.stack))) or_return
            ret := simulateSyscall0(prg, call) or_return
        }
        case ^ast.ASTSyscall1: {
            simulateAST(prg, type.arg1) or_return
            simulateAST(prg, type.call) or_return
            call := getInnerInt(Value(pop(&prg.stack))) or_return
            arg1 := Value(pop(&prg.stack))
            ret := simulateSyscall1(prg, call, arg1) or_return
        }
        case ^ast.ASTSyscall2: {
            simulateAST(prg, type.arg2) or_return
            simulateAST(prg, type.arg1) or_return
            simulateAST(prg, type.call) or_return
            call := getInnerInt(Value(pop(&prg.stack))) or_return
            arg1 := Value(pop(&prg.stack))
            arg2 := Value(pop(&prg.stack))
            ret := simulateSyscall2(prg, call, arg1, arg2) or_return
        }
        case ^ast.ASTSyscall3: {
            simulateAST(prg, type.arg3) or_return
            simulateAST(prg, type.arg2) or_return
            simulateAST(prg, type.arg1) or_return
            simulateAST(prg, type.call) or_return
            call := getInnerInt(Value(pop(&prg.stack))) or_return
            arg1 := Value(pop(&prg.stack))
            arg2 := Value(pop(&prg.stack))
            arg3 := Value(pop(&prg.stack))
            ret := simulateSyscall3(prg, call, arg1, arg2, arg3) or_return
        }
        case ^ast.ASTDrop: {
            simulateAST(prg, type.value) or_return
            pop(&prg.stack)
        }
        case ^ast.ASTBlock: {
            newVariableFrame(prg)
            for n in type.nodes {
                simulateAST(prg, n) or_return
            }
            dropVariableFrame(prg)
        }
        case ^ast.ASTVarRef: {
            ptr : ^any
            switch iv in &getVariable(prg, type.ident).value {
                case ^any:   ptr = (^any)(&iv)
                case bool:   ptr = (^any)(&iv)
                case f64:    ptr = (^any)(&iv)
                case int:    ptr = (^any)(&iv)
                case string: ptr = (^any)(&iv)
            }
            append(&prg.stack, Value{.Ptr, ptr})
        }
        case ^ast.ASTVarRead: {
            append(&prg.stack, 
                copyValue(getVariable(prg, type.ident)^)
            )
        }
        case ^ast.ASTVarWrite: {
            simulateAST(prg, type.value) or_return
            setVariable(prg, type.ident, pop(&prg.stack))
        }
        case ^ast.ASTVarDecl: {
            defineVariable(prg, type.ident, type.type)
        }
        case ^ast.ASTProcCall: {
            if type.ident in prg.ast.procs {
                simulateProcCall(prg, prg.ast.procs[type.ident])
            } else {
                return fmt.tprintf("Proc call for '%s' does not exist\n", type.ident)
            }
        }
        case ^ast.ASTProcReturn: {
            assert(false, "TODO: ASTProcRet")

        }
        case ^ast.ASTIf: {
            simulateAST(prg, type.cond) or_return
            b := getInnerBool(pop(&prg.stack)) or_return
            if b {
                newVariableFrame(prg)
                    simulateAST(prg, type.body) or_return
                dropVariableFrame(prg)
            } else {
                if type.elseBlock != nil {
                    newVariableFrame(prg)
                        simulateAST(prg, type.elseBlock) or_return
                    dropVariableFrame(prg)
                }
            }
        }
        case ^ast.ASTWhile: {
            // First check
            simulateASTList(prg, type.cond[:]) or_return
            b := getInnerBool(pop(&prg.stack)) or_return
            for b {
                // Body
                newVariableFrame(prg)
                    simulateAST(prg, type.body) or_return
                dropVariableFrame(prg)
                // Re-Evaluate
                simulateASTList(prg, type.cond[:]) or_return
                b = getInnerBool(pop(&prg.stack)) or_return
            }
        }
        case ^ast.ASTDup: {
            nv := copyValue(prg.stack[len(prg.stack) - 1])
            append(&prg.stack, nv)
        }
        case ^ast.ASTRot: {
            top  := pop(&prg.stack)
            next := pop(&prg.stack)
            bot  := pop(&prg.stack)
            append(&prg.stack, next)
            append(&prg.stack, bot)
            append(&prg.stack, top)
        }
        case ^ast.ASTSwap: {
            top  := pop(&prg.stack)
            next := pop(&prg.stack)
            append(&prg.stack, top)
            append(&prg.stack, next)
        }
        case ^ast.ASTNip: {
            top  := pop(&prg.stack)
            lose := pop(&prg.stack)
            append(&prg.stack, top)
        }
        case ^ast.ASTOver: {
            nv := copyValue(prg.stack[len(prg.stack) - 2])
            append(&prg.stack, nv)
        }
    }
    return nil
}

simulateASTList :: proc(prg:^Program, ast:[]ast.AST) -> ErrorMsg {
    for node in ast {
        simulateAST(prg, node) or_return
    }
    return nil
}

getInnerInt :: proc(val:Value) -> (int, ErrorMsg) {
    if val.type != .Int do return -1, "Value was not an integer\n"
    i, ok := val.value.(int)
    if !ok do return -1, "BUG: Int tagged value was not an integer\n"
    return i, nil
}

getInnerPtr :: proc(val:Value) -> (PtrValue, ErrorMsg) {
    if val.type != .Ptr do return nil, "Value was not an Pointer\n"
    p, ok := val.value.(PtrValue)
    if !ok do return nil, "BUG: Ptr tagged value was not a pointer\n"
    return p, nil
}
getInnerBool :: proc(val:Value) -> (bool, ErrorMsg) {
    if val.type != .Bool do return false, "Value was not an Bool\n"
    b, ok := val.value.(bool)
    if !ok do return false, "BUG: Bool tagged value was not a boolean\n"
    return b, nil
}
getInnerFloat :: proc(val:Value) -> (f64, ErrorMsg) {
    if val.type != .Float do return 0, "Value was not an Float\n"
    b, ok := val.value.(f64)
    if !ok do return 0, "BUG: Float tagged value was not a float\n"
    return b, nil
}

CompResult :: bit_set[enum {Eq, Lt, Gt}]
compareValues :: proc(v1, v2: Value) -> CompResult {
    ret := CompResult{}
    switch a in v1.value {
        case bool: {
            switch b in v1.value {
                case bool: {
                    if a == b  do ret += {.Eq}
                    if !a && b do ret += {.Lt}
                    if a && !b do ret += {.Gt}
                }
                case int: {
                    if int(a) == b do ret += {.Eq}
                    if int(a) < b  do ret += {.Lt}
                    if int(a) > b  do ret += {.Gt}
                }
                case f64: {
                    if f64(int(a)) == b do ret += {.Eq}
                    if f64(int(a)) < b  do ret += {.Lt}
                    if f64(int(a)) > b  do ret += {.Gt}
                }
                case PtrValue: {
                    // if int(a) == int(b) do ret += {.Eq}
                    // if int(a) <  int(b) do ret += {.Lt}
                    // if int(a) >  int(b) do ret += {.Gt}
                    assert(false, "TODO: ptrVal compairison")

                }
                case string: {
                    assert(false, "Uncomparable")
                }
            }
        }
        case int: {
            switch b in v1.value {
                case bool: {
                    if a == int(b) do ret += {.Eq}
                    if a <  int(b) do ret += {.Lt}
                    if a >  int(b) do ret += {.Gt}
                }
                case int: {
                    if a == b do ret += {.Eq}
                    if a <  b do ret += {.Lt}
                    if a >  b do ret += {.Gt}
                }
                case f64: {
                    if f64(a) == b do ret += {.Eq}
                    if f64(a) <  b do ret += {.Lt}
                    if f64(a) >  b do ret += {.Gt}
                }
                case PtrValue: {
                    // if a == int(b) do ret += {.Eq}
                    // if a <  int(b) do ret += {.Lt}
                    // if a >  int(b) do ret += {.Gt}
                    assert(false, "TODO: ptrVal compairison")

                }
                case string: {
                    assert(false, "Uncomparable")
                }
            }
        }
        case f64: {
            switch b in v1.value {
                case bool: {
                    if a == f64(int(b)) do ret += {.Eq}
                    if a >  f64(int(b)) do ret += {.Gt}
                    if a <  f64(int(b)) do ret += {.Lt}
                }
                case int: {
                    if a == f64(b) do ret += {.Eq}
                    if a >  f64(b) do ret += {.Gt}
                    if a <  f64(b) do ret += {.Lt}
                }
                case f64: {
                    if a == b do ret += {.Eq}
                    if a >  b do ret += {.Gt}
                    if a <  b do ret += {.Lt}
                }
                case PtrValue: {
                    // if a == f64(b) do ret += {.Eq}
                    // if a >  f64(b) do ret += {.Gt}
                    // if a <  f64(b) do ret += {.Lt}
                    assert(false, "TODO: ptrVal compairison")

                }
                case string: {
                    assert(false, "Uncomparable")
                }
            }
        }
        case PtrValue: {
            switch b in v1.value {
                case bool: {
                    // if int(a) == int(b) do ret += {.Eq}
                    // if int(a) <  int(b) do ret += {.Lt}
                    // if int(a) >  int(b) do ret += {.Gt}
                    assert(false, "TODO: ptrVal compairison")
                }
                case int: {
                    // if int(a) == b do ret += {.Eq}
                    // if int(a) <  b do ret += {.Lt}
                    // if int(a) >  b do ret += {.Gt}
                    assert(false, "TODO: ptrVal compairison")

                }
                case f64: {
                    // if f64(a) == b do ret += {.Eq}
                    // if f64(a) <  b do ret += {.Lt}
                    // if f64(a) >  b do ret += {.Gt}
                    assert(false, "TODO: ptrVal compairison")

                }
                case PtrValue: {
                    // if int(a) == int(b) do ret += {.Eq}
                    // if int(a) <  int(b) do ret += {.Lt}
                    // if int(a) >  int(b) do ret += {.Gt}
                    assert(false, "TODO: ptrVal compairison")

                }
                case string: {
                    assert(false, "Uncomparable")
                }
            }
        }
        case string: {
            switch b in v1.value {
                case bool: {
                    assert(false, "Uncomparable")
                }
                case int: {
                    assert(false, "Uncomparable")
                }
                case f64: {
                    assert(false, "Uncomparable")
                }
                case PtrValue: {
                    assert(false, "Uncomparable")
                }
                case string: {
                    if a == b do ret += {.Eq}
                    if a < b  do ret += {.Lt}
                    if a > b  do ret += {.Gt}
                }
            }
        }
    }
    return ret
}

copyValue :: proc(value:Value) -> Value {
    n : Value
    n.type = value.type
    n.value = value.value
    return n
}