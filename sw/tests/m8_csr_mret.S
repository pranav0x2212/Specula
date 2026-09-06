    .equ    TOHOST,  0x00100000
    .equ    CANARY,  0x80030000       # scratch RAM, zero at reset, never legitimately written

    .section .text
    .globl  main
main:
    li      t6, TOHOST

    li      t0, 0x1800
    csrw    mstatus, t0               # mstatus = 0x1800
    csrr    t1, mstatus
    bne     t1, t0, fail             # read-after-write

    csrrs   t2, mstatus, x0          # csrr form (rs1=x0): must NOT modify, returns old
    bne     t2, t0, fail

    li      t3, 0x40
    csrrs   t4, mstatus, t3          # set bit 6; return value is the OLD mstatus (0x1800)
    bne     t4, t0, fail
    csrr    t5, mstatus
    li      t3, 0x1840
    bne     t5, t3, fail             # CSRRS RMW actually applied

    li      t3, 0x40
    csrrc   t4, mstatus, t3          # clear bit 6 again; return value is 0x1840
    li      t0, 0x1840
    bne     t4, t0, fail
    csrr    t5, mstatus
    li      t3, 0x1800
    bne     t5, t3, fail             # CSRRC RMW actually applied

    li      a1, CANARY
    lw      a0, 0(a1)
    bnez    a0, fail

    la      t0, mret_target
    csrw    mepc, t0
    li      t1, 0x880                # MPP = S (0x800) | MPIE = 1 (0x80)
    csrw    mstatus, t1
    mret

    li      a0, 0xBAD
    li      a1, CANARY
    sw      a0, 0(a1)                # poison store
    li      a0, 2
    sw      a0, 0(t6)
3:  j       3b

mret_target:
    li      a1, CANARY
    lw      a0, 0(a1)
    bnez    a0, fail                 # canary still zero -> younger instrs were flushed

    csrr    t0, mepc
    la      t1, mret_target
    bne     t0, t1, fail             # mepc unchanged, redirect target correct

    csrr    t0, mstatus
    li      t2, 0x1800
    and     t1, t0, t2
    bnez    t1, fail                 # MPP cleared to 0 by mret
    andi    t1, t0, 0x80
    beqz    t1, fail                 # MPIE = 1 after mret

    li      a0, 1
    sw      a0, 0(t6)
4:  j       4b

fail:
    li      a0, 2
    sw      a0, 0(t6)
5:  j       5b
