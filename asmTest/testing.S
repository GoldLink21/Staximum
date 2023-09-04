; Used to help me make sure my
;  x86_64 is correct

   section .bss
   ; This is where variables go

   section .text
   ; This is where actual code goes
global _start
; %macro xxx 1

; %endmacro
_start:
   ; write
   mov rdx,len ; Length to send
   mov rsi,str ; Msg to send
   mov rdi,1 ; stdout
   mov rax,1 ; SYS_WRITE
   syscall
   
   mov rax, 60
   mov rdi, 0
   syscall

   section .data
   ; This is where constant strings and expressions can go
str: db 'Hello',10
len: equ $-str