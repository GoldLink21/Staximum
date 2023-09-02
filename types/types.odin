// Handles watching types going throughout the program
package types

import "core:fmt"
import "../tokenizer"

Intrinsic :: struct {
    inputs:  []Type,
    outputs: []Type,
}

Type :: enum u8 {
    Any,
    Int, 
    Float,
    Bool,
    String,
    CString,
}

typeStack : [dynamic]Type

// Intrinsic procedures. Contains overridden type ios
intrinsics : map[tokenizer.TokenType][]Intrinsic = {
    .Exit = {{ {.Int}, {} }},
    .Plus = {
        { {.Int,   .Int},   {.Int  } },
        { {.Float, .Float}, {.Float} },
        { {.Float, .Int},   {.Float} },
        { {.Int,   .Float}, {.Float} },
    },
    .Dash = {
        { {.Int,   .Int},   {.Int  } },
        { {.Float, .Float}, {.Float} },
        { {.Float, .Int},   {.Float} },
        { {.Int,   .Float}, {.Float} },
    },
    .Eq = {
        { {.Int,   .Int},   {.Bool} },
        { {.Float, .Float}, {.Bool} },
    },
    .Syscall1 = {{{.Int, .Any}, {.Any} } }
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