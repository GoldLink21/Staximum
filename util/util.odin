package util

import "core:fmt"
import "core:strings"

ErrorMsg :: union { string }

Location :: struct {
    line, col: uint,
    file: string,
}

// TODO: Location reporting is broken
printLoc :: proc(loc:Location){
    fmt.printf("%s %d:%d ", loc.file, loc.line, loc.col)
}

locStr :: proc(loc:Location, msg:string, args:..any) -> string{
    locString := fmt.tprintf("%s %d:%d ", loc.file, loc.line, loc.col)
    msgString := fmt.tprintf(msg, ..args)
    return fmt.tprintf("%s%s\n", locString, msgString)
}

// Takes a string with literal escaped values and 
//   replaces them with \char
escapeString :: proc(input:string) -> string {
    sb : strings.Builder// = strings.builder_make_len_cap(len(input), len(input)*2)
    strings.write_byte(&sb, '"')
    // Escape characters
    for c in input {
        if c == '\n' {
            strings.write_string(&sb, "\\n")
        } else if c == '\r' {
            strings.write_string(&sb, "\\r")
        } else if c == '\t' {
            strings.write_string(&sb, "\\t")
        } else if c == '"' {
            strings.write_string(&sb, "\\\"")
        } else if c == 0 {
            strings.write_string(&sb, "\\0")
        } else {
            strings.write_byte(&sb, u8(c))
        }
    }
    strings.write_byte(&sb, '"')
    return strings.to_string(sb)
}