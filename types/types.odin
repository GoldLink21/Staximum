// All types that the language can handle
package types

import "core:fmt"
import "core:strings"

// These are the possible underlying types you can have
Type :: enum u8 {
    Any,
    Int, 
    Ptr,
    Float,
    Bool,
    String,
    CString,
}
TypeToString : map[Type]string = {
    .Any = "any",
    .Int = "int",
    .Ptr = "ptr",
    .Bool = "bool",
    .Float = "float",
    .String = "string",
    .CString = "cstring",
}
StringToType : map[string]Type = {
    "any" = .Any,
    "int" = .Int,
    "ptr" = .Ptr,
    "bool" = .Bool,
    "float" = .Float,
    "string" = .String,
    "cstring" = .CString,
}
TypeStack :: [dynamic]Type
cloneTypeStack :: proc(ts:TypeStack) -> TypeStack {
    newStack := make([dynamic]Type)
    for t in ts {
        append(&newStack, t)
    }
    return newStack
}
popType :: proc(ts:^TypeStack) -> Type {
    return pop(ts)
}
pushType :: proc(ts:^TypeStack, type:Type) {
    append(ts, type)
}

typesToString :: proc(types:[dynamic]Type) -> string {
    sb : strings.Builder
    strings.write_string(&sb, "[ ")
    for t, i in types {
        strings.write_string(&sb, TypeToString[t])
        if i != len(types) - 1 do strings.write_string(&sb, ", ")
    }
    strings.write_string(&sb, " ]")
    return strings.to_string(sb)
}

printType :: proc(t:Type){
    fmt.printf("(%s)", TypeToString[t])
}

printTypes :: proc(ts:[dynamic]Type) {
    fmt.print("[")
    for t in ts {
        printType(t)
        fmt.println()
    }
    fmt.print("]")
}