; this is a different addressing mode
default rel

; Used to help me make sure my
;  x86_64 is correct
   section .bss
   ; This is where variables go

;Convert a long to a double
;  cvtsi2sdq %rdi, %xmm0
; Convert a float to a int
;  cvttss2sil %xmm0, %eax

   section .text
   ; This is where actual code goes
extern printf
   ; int args in order RDI, RSI, RDX, RCX, R8, and R9, then stack
   ; float vals go into regs xmm0-xmm7
   ;  float returns are xmm0 and xmm1
global _start
; %macro xxx 1

; %endmacro
_start:
   ; Align Stack
   ; sub rsp,8
   ; Load float value
   movsd xmm0, qword [flVal]
   movsd xmm1, qword [flVal]
   addsd xmm0, xmm1
   mov rdi, fmt
   mov eax, 1
   call printf
   ; Tell that we have 1 float arg
   ; Put stack back
   ; add rsp, 8


   mov rax, 60
   mov rdi, 0
   syscall

   section .data
   ; This is where constant strings and expressions can go
msg: db 'Hello',10,0
fmt: db '[%f]',10,0
flVal: dq 1.234
len: equ $-msg