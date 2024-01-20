# Staximum Language

A [Stack based programming language](https://en.wikipedia.org/wiki/Stack-oriented_programming) intended mostly for programming practice. It has strong typing. File extensions is .stax

Inspiration came from [Porth](https://gitlab.com/tsoding/porth) and the Youtube videos that were covering its development

Currently written in [Odin](https://github.com/odin-lang/Odin) with hopes of eventually self hosting the language

## General Info

A stack based languages uses values on a stack to handle its operations.
Operators use the top of the stack as the left hand side. With this `1 2 -` is in math terms `2 - 1`

## To Use

Build the comiler with `odin build . -out:stax`. After that, you can use `./stax inFile.stax [outFile.stax]`.

You can also use the [Build Script](./build.sh) which is crafted to help with testing using a single input file quickly. It can be tweaked with the variables at the top of the script

## Global Scope

Stax has two forms of code, those being `proc`edures and `macro`s.
They can be created with their respective keywords, followed by their name and then type annotations for input and output types.

```
macro One :> int {
    1
}
proc main :> {

}
// You can also give comments like this
/* or have block comments 
    /* They can also be nested like this */ 
*/
// If there are no inputs, you can ommit the ':' from the signature
macro Two > int {
    2
}
// Same goes with the '>' for output types, which is helpful with main
proc main {

}
```

The only difference between the two is that `macro`s will inject their body where they get invoked, and `proc`s will call to the code and return afterwards.

You are also able to import code from other files using the `import "./file/name.stax"`
- Currently does not check for repeated imports, but will likely happen later

You can also have global variables (Currently only supports integer types) using the `let` keyword

```
let x = 1
// Or you can initialize after a block, but 
//  only when there is 1 value on the stack at the end
let y = { 1 2 + }
```

## Literals

You can get literal values for strings and integers currently

For strings, you just enclose what you want in quotes: `"Hello there"`
There is also support for escape characters, those being:
- \n
- \r
- \t
- \0 For use with c or the terminal
- \" to insert a quote into the string

You can also postfix a string with 'c' to make it into a c string. C strings do not push their length and end with a 0 byte
"C string here"c

Integers also have a few different variations
- Hex with the common `0x` format that takes 0-9, a-f, A-F
- Octals with `0o` that takes 0-7
- Binary using `0b` taking only 0 and 1
- And Roman Numerals, using `0r` which accepts somewhat valid roman numerals, like `0rXVIII` = 18. 
    - There is no validation of ordering other than that are bigger after the current number means subtract the two. This means `0rVX` = 5 and `0rVIX` = 5 + 9 = 14

## Primitives

There are a few primitive operations you can use in your code

System Calls can be used to request the system to do things. They take varing amount of parameters, and because we can't know ahead of time due to passing parameters on the stack, there are instead 7 different operations, aptly `syscall%d` with `%d` being a digit from 0-6. Each syscall takes 1 argument for the syscall number, and then `%d` extra arguments to get passed on. 

A reference for Linux x86_64 syscalls can be found [Here](https://blog.rchapman.org/posts/Linux_System_Call_Table_for_x86_64/)

There are some shortcut primitives for some common syscalls
- `puts` for doing a write syscall on a string
- `exit` for quitting execution with an exit code

## Variables

Variables either require a type, or the types can be inferred by the declarations

```
// Pedantic way 
let x : int = 10
// Not having the = after makes it just a declation
let y : int 
// You can ignore the type annotation as well
let z = 12

// You are also able to assign using a block. It must have one return type
let w = { 5 10 12 + - }
```

### Reading

Getting a value from a variable is done with the `@` symbol. You just first say the variable you want to read from

```
let x = 10
x @ // Puts 10 onto the stack
```

### Writing

Writing into a variable is done with `!`. First is the variable, then the value to write, and then `!`

```
let z = 20
z 2 !
z @ // This will put 2 onto the stack
```

## Control Flow

Conditionals are done with the `if ... then` syntax. Anything can go between the if and then block, it just requires a boolean at the top of the stack before the then statement

```
let x = 10
if x @ 10 = then {
    "Was 10\n" puts drop
}
```

The stack has to be the same going out of the if block as it was going in. You can also add an `else` block, and doing so requires both branches to have the same output types

```
if false then {

} else if false then {

} else {

}
```

You can also swap out the `if` for `while`. It will re-evaluate everything between the `while` and `then` statements

```
// This will print "Iteration" 10 times
10
while dup 0 > then {
    "Iteration\n" puts drop
    1 -
}
// Don't forget to get rid of the counter
drop
```

---

See the [Expected Syntax](./expectedSyntax.stax) for examples of what the syntax should become

## Feature Goals

- [ ] Variables (Needs work)
- [x] Branching/Loops
- [x] Functions/Procedures
- [x] Macros/Inline Functions
- [ ] Arrays
- [ ] Structures
- [ ] Multiple Returns
- [ ] Optimizations
- [ ] Other Assembly Formats