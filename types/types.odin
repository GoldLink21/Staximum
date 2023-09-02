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
TypeStrings : map[Type]string = {
    .Any = "any",
    .Int = "int",
    .Float = "float",
    .Bool = "bool",
    .String = "string",
    .CString = "cstring",
}

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