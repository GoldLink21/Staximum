LINK_LIBC=true

# Helps with quickly testing asmTest/testing.S
rm -f testing.o testing
nasm -felf64 asmTest/testing.S

if [ $? -ne 0 ]; then 
    exit
fi

if $LINK_LIBC ; then 
    ld -dynamic-linker /lib64/ld-linux-x86-64.so.2 -o testing -lc asmTest/testing.o
    # ld asmTest/testing.o -o testing -lc -e main -dynamic-linker /lib/ld-linux-x86-64.so.2
else
    ld asmTest/testing.o -o testing
fi
if [ $? -ne 0 ]; then 
    echo "Linking Error"
    exit
fi

rm asmTest/testing.o
./testing
echo "Returned with $?"
rm testing