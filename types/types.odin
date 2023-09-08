// All types that the language can handle
package types

import "core:fmt"

Type :: enum u8 {
    Any,
    Int, 
    Float,
    Bool,
    String,
    CString,
}
TypeToString : map[Type]string = {
    .Any = "any",
    .Int = "int",
    .Bool = "bool",
    .Float = "float",
    .String = "string",
    .CString = "cstring",
}
StringToType : map[string]Type = {
    "any" = .Any,
    "int" = .Int,
    "bool" = .Bool,
    "float" = .Float,
    "string" = .String,
    "cstring" = .CString,
}