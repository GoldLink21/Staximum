package ast

import "../types"
import "core:fmt"

Type :: types.Type
Intrinsic :: types.Intrinsic

typeStack : [dynamic]Type


handleInOutIfValid :: proc(ins:[]Type, outs:[]Type = {}) -> bool {
    if !hasTypes(ins) do return false
    for _ in ins do popType()
    for t in outs do pushType(t)
    return true
}
expectTransform :: proc(ins:[]Type, outs:[]Type) {
    expectTypes(ins)
    for t in outs do pushType(t)
}


pushType :: proc(ty : Type) {
    append(&typeStack, ty)
}

popType :: proc() -> (Type, bool) {
    if len(typeStack) == 0 do return nil, false
    return pop(&typeStack), true
}

peekType :: proc() -> Type {
    return typeStack[len(typeStack) - 1]
}

applyTransIfValid :: proc(inOuts:[]Intrinsic) -> bool {
    for intrinsic in inOuts {
        // Has exact possible inputs from many choices
        if hasTypes(intrinsic.inputs) {
            // Push output types
            for i in 0..<len(intrinsic.inputs) {
                popType()
            }
            for out in intrinsic.outputs {
                pushType(out)
            }
            return true
        }
    }
    return false
}

hasTypes :: proc(types: []Type) -> bool {
    if len(types) == 0 do return true
    if len(typeStack) < len(types) do return false
    for ty, i in types {
        // Can accept if wants type Any
        if ty != .Any && ty != typeStack[len(typeStack) - 1 - i] do return false
    }
    return true
}

expectTypes :: proc(types: []Type) {
    if len(types) == 0 do return
    if len(typeStack) < len(types) {
        fmt.assertf(false, "Expected %d typed values, but got only %d\n", 
            len(types), len(typeStack))
    }
    for ty in types {
        top := pop(&typeStack)
        if top != ty && ty != .Any {
            fmt.assertf(false, "Expected type of '%s' but got '%s'\n", 
                fmt.enum_value_to_string(ty), 
                fmt.enum_value_to_string(top)
            )
        }
    }
}

handleNextToken :: proc() {
    

}