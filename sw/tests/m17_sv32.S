    .equ TOHOST,     0x00100000
    .equ ROOTPT,     0x80200000
    .equ L0PT,       0x80201000
    .equ SCRATCH,    0x80280000
    .equ HIVA,       0xFFFFE000
    .equ SATP_SV32,  0x80000000

    .section .text
    .globl  main
main:
    li      t6, TOHOST

    li      t0, ROOTPT
    li      t1, 2048
9:  sw      zero, 0(t0)
    addi    t0, t0, 4
    addi    t1, t1, -1
    bnez    t1, 9b

    # ---- root[0]: identity superpage for VA 0..0x3FFFFF, RWX|V ----
    li      t0, ROOTPT
    li      t1, 0x0000000f
    sw      t1, 0(t0)

    # ---- root[512]: identity superpage for VA 0x80000000.., RWX|V ----
    li      t2, ROOTPT + 0x800           # 512 * 4
    li      t1, 0x2000000f
    sw      t1, 0(t2)

    # ---- root[1023]: pointer to L0PT (V only) ----
    li      t2, ROOTPT + 0xffc           # 1023 * 4
    li      t1, 0x20080401               # PA2PTE(0x80201000) | V
    sw      t1, 0(t2)

    # ---- L0PT[1022]: 4 KiB leaf RW|V -> PA 0x80280000 ----
    li      t2, L0PT + 0xff8             # 1022 * 4
    li      t1, 0x200a0007               # PA2PTE(0x80280000) | R | W | V
    sw      t1, 0(t2)

    # ---- enter S-mode with paging enabled ----
    la      t0, smode
    csrw    mepc, t0
    li      t0, 0x800                    # mstatus.MPP = S
    csrw    mstatus, t0
    li      t0, ROOTPT
    srli    t0, t0, 12
    li      t1, SATP_SV32
    or      t0, t0, t1                   # satp = SV32 | PPN(ROOTPT)
    csrw    satp, t0
    mret

smode:
    # paging on, S-mode. store + load through the high VA.
    li      t0, HIVA
    li      t1, 0xC0FFEE11
    sw      t1, 0(t0)
    lw      t2, 0(t0)
    bne     t2, t1, fail

    # the same physical page, reached via the identity mapping of SCRATCH
    li      t3, SCRATCH
    lw      t4, 0(t3)
    bne     t4, t1, fail

    # page offset preserved across translation
    li      t0, HIVA
    li      t1, 0x000000ab
    sw      t1, 0x124(t0)                # -> SCRATCH + 0x124
    li      t3, SCRATCH
    lw      t4, 0x124(t3)
    bne     t4, t1, fail

    li      a0, 1
    sw      a0, 0(t6)
1:  j       1b

fail:
    li      a0, 2
    sw      a0, 0(t6)
2:  j       2b
