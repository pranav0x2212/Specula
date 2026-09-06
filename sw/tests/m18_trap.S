    .equ TOHOST,    0x00100000
    .equ TRAPINFO,  0x80050000       # scratch RAM: [0]=scause [4]=sepc [8]=sstatus

    .section .text
    .globl  main
main:
    li      t6, TOHOST
    csrw    satp, zero               # bare translation
    la      t0, strap
    csrw    stvec, t0                # S-mode trap vector (direct mode)

    # ---- Test 1: ECALL from M-mode -------------------------------------------
m_ecall:
    ecall
m_after:                            # resumed here, now in S-mode (SPP was 1)
    li      t5, TRAPINFO
    lw      t0, 0(t5)
    li      t1, 11
    bne     t0, t1, fail            # scause == 11 (env call from M)
    lw      t0, 4(t5)
    la      t1, m_ecall
    bne     t0, t1, fail            # sepc == the ecall PC
    lw      t0, 8(t5)
    andi    t1, t0, 0x100
    beqz    t1, fail               # sstatus.SPP == 1 (trap from non-U)
    andi    t1, t0, 0x2
    bnez    t1, fail               # sstatus.SIE cleared on trap entry

    # ---- Test 2: ECALL from S-mode -----------------------------------------
s_ecall:
    ecall
s_after:
    li      t5, TRAPINFO
    lw      t0, 0(t5)
    li      t1, 9
    bne     t0, t1, fail            # scause == 9 (env call from S)
    lw      t0, 4(t5)
    la      t1, s_ecall
    bne     t0, t1, fail            # sepc == the ecall PC
    lw      t0, 8(t5)
    andi    t1, t0, 0x100
    beqz    t1, fail               # sstatus.SPP == 1 (trap from S)

    # ---- transition S -> U via SRET ---------------------------------------
    la      t0, u_entry
    csrw    sepc, t0
    li      t1, 0x100
    csrrc   x0, sstatus, t1         # SPP <- 0  (SRET target = U-mode)
    sret

u_entry:                           # now executing in U-mode
    # ---- Test 3: ECALL from U-mode --------------------------------------
u_ecall:
    ecall
u_after:                           # resumed here, back in U-mode (SPP was 0)
    li      t5, TRAPINFO
    lw      t0, 0(t5)
    li      t1, 8
    bne     t0, t1, fail            # scause == 8 (env call from U)
    lw      t0, 4(t5)
    la      t1, u_ecall
    bne     t0, t1, fail            # sepc == the ecall PC
    lw      t0, 8(t5)
    andi    t1, t0, 0x100
    bnez    t1, fail               # sstatus.SPP == 0 (trap from U)

    # ---- success -------------------------------------------------------
    li      a0, 1
    sw      a0, 0(t6)
1:  j       1b

fail:
    li      a0, 2
    sw      a0, 0(t6)
2:  j       2b

    # ---------------- shared S-mode trap handler ----------------
    .balign 4
strap:
    li      t4, TRAPINFO
    csrr    t2, scause
    sw      t2, 0(t4)
    csrr    t2, sepc
    sw      t2, 4(t4)
    csrr    t3, sstatus
    sw      t3, 8(t4)
    addi    t2, t2, 4               # step over the 4-byte ecall
    csrw    sepc, t2
    sret
