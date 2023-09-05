// All types that the language can handle
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
TypeStrings : map[Type]string = {
    .Any = "any",
    .Int = "int",
    .Float = "float",
    .Bool = "bool",
    .String = "string",
    .CString = "cstring",
}
