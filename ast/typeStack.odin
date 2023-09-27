package ast

import "../types"
import "../util"
import "core:fmt"
import "core:os"

Type :: types.Type

handleInOutIfValid :: proc(ts:^[dynamic]Type, ins:[]Type, outs:[]Type = {}) -> bool {
    if !hasTypes(ts, ins) do return false
    for _ in ins do popType(ts)
    for t in outs do pushType(ts, t)
    return true
}
expectTransform :: proc(ts:^[dynamic]Type, ins:[]Type, outs:[]Type, loc:util.Location) {
    expectTypes(ts, ins, loc)
    for t in outs do pushType(ts, t)
}

// Not needed, but helps document code throughout
pushType :: proc(ts:^[dynamic]Type, ty : Type) {
    append(ts, ty)
}
// Does some bounds checking for us
popType :: proc(ts:^[dynamic]Type) -> (Type, bool) {
    if len(ts) == 0 do return nil, false
    return pop(ts), true
}

// Look at last element of type stack
peekType :: proc(ts:^[dynamic]Type, ) -> Type {
    return ts[len(ts) - 1]
}


hasTypes :: proc(ts:^[dynamic]Type, types: []Type) -> bool {
    if len(types) == 0 do return true
    if len(ts) < len(types) do return false
    for ty, i in types {
        // Can accept if wants type Any
        if ty != .Any && ty != ts[len(ts) - 1 - i] do return false
    }
    return true
}

// Expects types and pops them
expectTypes :: proc(ts:^[dynamic]Type, types: []Type, loc:util.Location) -> util.ErrorMsg {
    if len(types) == 0 do return nil
    if len(ts) < len(types) {
        return util.locStr(loc, 
            "Expected %d typed values, but got only %d", 
            len(types), len(ts))
    }
    for ty in types {
        top := pop(ts)
        if top != ty && ty != .Any {
            s1, _ := fmt.enum_value_to_string(ty)
            s2, _ := fmt.enum_value_to_string(top)
            
            return util.locStr(loc, "Expected type of '%s' but got '%s'\n", 
                s1, s2)
        }
    }
    return nil
}
