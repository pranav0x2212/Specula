    .section .text.init,"ax",@progbits
    .globl  _start
_start:
    addi    sp, x0, 0x400        /* sp = top of data RAM (grows down) */
    jal     ra, main             /* enter main (declared noreturn)    */
1:  beq     x0, x0, 1b           /* safety net: spin if main returns  */
