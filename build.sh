# remove any output files before running
rm -f out out.o out.S stax

# Control what is happening on build
GENERATE_ASM=true
ASSEMBLE=true
LINK=true
RUN=true

OUT_EXE=stax
IN_FILE=input.stax
OUT_FILE=out

# Check that input file exists
if ! [ -f $IN_FILE ]; then
    echo "Expeced input file \"$IN_FILE\""
    exit 1
fi

odin build . -out:$OUT_EXE -define:GENERATE_ASM=$GENERATE_ASM # \
     # -define:$ASSEMBLE=true -define:LINK=$LINK

# Only continue if ok
if [ $? -ne 0 ]; then 
    echo "Error in building"
    exit 1
fi
# Run with test inputs
./$OUT_EXE $IN_FILE $OUT_FILE

# Only continue if ok
if [ $? -ne 0 ]; then 
    echo "Error in compilation"
    exit
fi

if ! $GENERATE_ASM ; then
    exit 0
fi

if ! $ASSEMBLE ; then 
    exit 0
fi

# Compile to allow gdb 
nasm -felf64 -F dwarf out.S
# nasm -felf64 out.S

if ! $LINK ; then
    exit 0
fi
ld out.o -o out

if $RUN ; then
    ./out
    echo "Exited with $?"
fi