    .equ    TOHOST, 0x10000000

    .section .text
    .globl  main
main:                                   # == xv6 _entry
    li      a0, 0x1000                   # 4096
    csrr    a1, mhartid                  # -> 0
    addi    a1, a1, 1                    # -> 1
    mul     a0, a0, a1                   # -> 0x1000  (RV32M + mhartid together)
    jal     ra, m8_start
junk:
    j       junk                         # xv6's dead-end if start() returns

m8_start:                               # == xv6 start()
    # mstatus: clear MPP, set MPP = S
    csrr    a5, mstatus
    li      a4, 0xFFFFE7FF               # ~MSTATUS_MPP_MASK
    and     a5, a5, a4
    li      a4, 0x800                    # MSTATUS_MPP_S
    or      a5, a5, a4
    csrw    mstatus, a5
    # mepc = real_main
    la      a5, real_main
    csrw    mepc, a5
    li      a5, 0
    csrw    satp, a5
    li      a5, -1
    csrw    pmpaddr0, a5
    li      a5, 0x1F
    csrw    pmpcfg0, a5
    li      a5, 0xFFFF
    csrw    medeleg, a5
    csrw    mideleg, a5
    csrr    a5, mstatus
    ori     a5, a5, 0x8                  # MIE
    csrw    mstatus, a5
    csrr    a5, mie
    ori     a5, a5, 0x80                 # MTIE
    csrw    mie, a5
    li      a4, 0x80030000
    csrw    mscratch, a4
    la      a5, tvec
    csrw    mtvec, a5
    # tp = mhartid
    csrr    a5, mhartid
    mv      tp, a5
    mret

tvec:                                    # machine trap vector - must never run
    li      a0, 2
    li      t6, TOHOST
    sw      a0, 0(t6)
6:  j       6b

real_main:                              # == xv6 main(): mret landed here in S-mode
    li      t6, TOHOST

    bnez    tp, fail                     # (1) mhartid propagated to tp == 0

    csrr    t0, mepc
    la      t1, real_main
    bne     t0, t1, fail                 # (2) mepc == main

    csrr    t0, mstatus
    li      t2, 0x1800
    and     t1, t0, t2
    bnez    t1, fail                     # (3) mstatus.MPP == 0 after mret
    andi    t1, t0, 0x80
    beqz    t1, fail                     # (4) mstatus.MPIE == 1 after mret

    li      a0, 1                        # (6) tohost = 1
    sw      a0, 0(t6)
7:  j       7b

fail:
    li      a0, 2
    sw      a0, 0(t6)
8:  j       8b
