    .section .text
    .globl  main
main:
    li      t6, 0x10000000          # tohost

    # MUL: 0x1000 * 3 = 0x3000
    li      t0, 0x1000
    li      t1, 3
    mul     t2, t0, t1
    li      t3, 0x3000
    bne     t2, t3, fail

    # MUL low-word truncation: 0x00010000 * 0x00010000 -> 0 (low 32 bits)
    li      t0, 0x10000
    mul     t2, t0, t0
    bnez    t2, fail

    # MUL, the exact _entry value: 0x1000 * 1 = 0x1000
    li      t0, 0x1000
    li      t1, 1
    mul     t2, t0, t1
    li      t3, 0x1000
    bne     t2, t3, fail

    # DIVU: 100 / 7 = 14
    li      t0, 100
    li      t1, 7
    divu    t2, t0, t1
    li      t3, 14
    bne     t2, t3, fail

    # REMU: 100 % 7 = 2
    remu    t2, t0, t1
    li      t3, 2
    bne     t2, t3, fail

    # DIVU unsigned high bit: 0x80000000 / 2 = 0x40000000
    li      t0, 0x80000000
    li      t1, 2
    divu    t2, t0, t1
    li      t3, 0x40000000
    bne     t2, t3, fail

    # DIVU by zero -> 0xFFFFFFFF
    li      t0, 0x12345678
    li      t1, 0
    divu    t2, t0, t1
    li      t3, -1
    bne     t2, t3, fail

    # REMU by zero -> dividend
    remu    t2, t0, t1
    bne     t2, t0, fail

    li      a0, 1
    sw      a0, 0(t6)
1:  j       1b

fail:
    li      a0, 2
    sw      a0, 0(t6)
2:  j       2b
