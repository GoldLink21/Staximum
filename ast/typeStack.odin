package ast

import "../types"
import "../util"
import "core:fmt"
import "core:os"

Type :: types.Type

typeStack : [dynamic]Type


handleInOutIfValid :: proc(ins:[]Type, outs:[]Type = {}) -> bool {
    if !hasTypes(ins) do return false
    for _ in ins do popType()
    for t in outs do pushType(t)
    return true
}
expectTransform :: proc(ins:[]Type, outs:[]Type, loc:util.Location) {
    expectTypes(ins, loc)
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


hasTypes :: proc(types: []Type) -> bool {
    if len(types) == 0 do return true
    if len(typeStack) < len(types) do return false
    for ty, i in types {
        // Can accept if wants type Any
        if ty != .Any && ty != typeStack[len(typeStack) - 1 - i] do return false
    }
    return true
}

// Expects types and pops them
expectTypes :: proc(types: []Type, loc:util.Location) -> util.ErrorMsg {
    if len(types) == 0 do return nil
    if len(typeStack) < len(types) {
        return util.locStr(loc, 
            "Expected %d typed values, but got only %d", 
            len(types), len(typeStack))
    }
    for ty in types {
        top := pop(&typeStack)
        if top != ty && ty != .Any {
            s1, _ := fmt.enum_value_to_string(ty)
            s2, _ := fmt.enum_value_to_string(top)
            
            return util.locStr(loc, "Expected type of '%s' but got '%s'\n", 
                s1, s2)
        }
    }
    return nil
}

handleNextToken :: proc() {
    

}