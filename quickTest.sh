# Helps with quickly testing asmTest/testing.S
rm -f testing.o testing
nasm -felf64 asmTest/testing.S
ld asmTest/testing.o -o testing

rm asmTest/testing.o
./testing
echo "Returned with $?"
rm testing