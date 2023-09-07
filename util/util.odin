package util

import "core:fmt"

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