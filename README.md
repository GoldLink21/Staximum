# Staximum Language

A [Stack based programming language](https://en.wikipedia.org/wiki/Stack-oriented_programming) intended mostly for programming practice. File extensions is .stax

Inspiration came from [Porth](https://gitlab.com/tsoding/porth) and the Youtube videos that were covering its development

Currently written in [Odin](https://github.com/odin-lang/Odin) with hopes of eventually self hosting the language

## General Info

A stack based languages uses values on a stack to handle its operations.
Operators use the top of the stack as the left hand side. With this `1 2 -` is in math terms `2 - 1`

## To Use

Build the comiler with `odin build . -out:stax`. After that, you can use `./stax inFile.stax [outFile.stax]`.

You can also use the [Build Script](./build.sh) which is crafted to help with testing using a single input file quickly. It can be tweaked with the variables at the top of the script

## Operations

TODO

---

See the [Expected Syntax](./expectedSyntax.stax) for examples of what the syntax should become

## Feature Goals

- [ ] Variables
- [ ] Branching/Loops
- [ ] Functions/Procedures
- [ ] Macros/Inline Functions
- [ ] Optimizations
- [ ] Other Assembly Formats