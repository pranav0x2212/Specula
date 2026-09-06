    .equ TOHOST, 0x00100000

    .section .text
    .globl  main
main:
    li      t6, TOHOST

    li      t0, 0x80030000
    li      t1, 0xAAAA5555
    sw      t1, 0(t0)

    li      t2, 0x12345678
    amoswap.w t3, t2, (t0)
    li      t4, 0xAAAA5555
    bne     t3, t4, fail            # rd receives old memory value
    lw      t5, 0(t0)
    bne     t5, t2, fail            # memory now holds rs2

    li      t0, 0x80030010
    li      a5, 1
    sw      zero, 0(t0)
    amoswap.w a5, a5, (t0)         # xv6 acquire pattern: a5 = old(0), lock = 1
    bnez    a5, fail
    lw      t5, 0(t0)
    li      t4, 1
    bne     t5, t4, fail

    li      a0, 1
    sw      a0, 0(t6)
1:  j       1b

fail:
    li      a0, 2
    sw      a0, 0(t6)
2:  j       2b
