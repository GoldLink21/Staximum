rm -f testing.o testing
nasm -felf64 asmTest/testing.S
ld asmTest/testing.o -o testing

rm asmTest/testing.o
./testing
rm testing