    .section .text.init,"ax",@progbits
    .globl  _start
_start:
    li      sp, 0x80038000
    jal     ra, main
1:  beq     x0, x0, 1b
