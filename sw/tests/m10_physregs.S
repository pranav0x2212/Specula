    .equ TOHOST, 0x00100000

    .section .text
    .globl  main
main:
    li      t6, TOHOST

    li      gp, 30
    li      tp, 31
    li      s0, 100
    li      s1, 101
    li      s2, 102
    li      s3, 103
    li      s4, 104
    li      s5, 105
    li      s6, 106
    li      s7, 107
    li      s8, 108
    li      s9, 109
    li      s10, 110
    li      s11, 111
    li      a1, 201
    li      a2, 202
    li      a3, 203
    li      a4, 204
    li      a5, 205
    li      a6, 206
    li      a7, 207
    li      t3, 40
    li      t4, 41
    li      t5, 42

    li      t0, 0x80030000
    li      a0, 0
    .rept 40
    addi    a0, a0, 1
    lw      t1, 0(t0)
    lw      t2, 4(t0)
    .endr

    li      t1, 40
    bne     a0, t1, fail          # dependent chain completed through the stalls

    li      t1, 111
    bne     s11, t1, fail         # pinned registers intact under pressure
    li      t1, 42
    bne     t5, t1, fail
    li      t1, 30
    bne     gp, t1, fail

    li      a0, 1
    sw      a0, 0(t6)
1:  j       1b

fail:
    li      a0, 2
    sw      a0, 0(t6)
2:  j       2b
