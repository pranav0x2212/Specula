/* Specula milestone-3 startup.
 *
 * Initialises the stack pointer, then enters main(). Without this, sp is
 * whatever the reset register file holds (0), and any function prologue that
 * spills to the stack writes out of the LSU's address space.
 *
 * The LSU data RAM is 256 words = 0x400 bytes. The stack starts at the top
 * (0x400) and grows down; the program's data window is 0x100..0x10c and
 * tohost is 0x700, so there is ample clearance for the shallow call chain.
 */
    .section .text.init,"ax",@progbits
    .globl  _start
_start:
    addi    sp, x0, 0x400        /* sp = top of data RAM (grows down) */
    jal     ra, main             /* enter main (declared noreturn)    */
1:  beq     x0, x0, 1b           /* safety net: spin if main returns  */
