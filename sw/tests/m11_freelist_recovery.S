    .equ TOHOST, 0x00100000
    .section .text
    .globl  main
main:
    li      t6, TOHOST
    li      gp, 0x80030000
    sw      zero, 0(gp)
    sw      zero, 4(gp)

    li      s0, 0xABC              
    li      t5, 0x5EED         
    li      a1, 200               
    li      a0, 0                 

loop:
    beq     a0, a1, done

    lw      t1, 0(gp)             
    lw      t2, 4(gp)

    addi    s1, a0, 1
    addi    s2, a0, 2
    addi    s3, a0, 3
    addi    s4, a0, 4
    addi    s5, a0, 5
    addi    s6, a0, 6
    addi    s7, a0, 7
    addi    s8, a0, 8
    addi    s9, a0, 9
    addi    s10, a0, 10
    addi    s11, a0, 11
    addi    a2, a0, 12
    addi    a3, a0, 13
    addi    a4, a0, 14
    addi    a5, a0, 15
    add     t3, s1, s2
    add     t4, s3, s4
    add     a6, s5, s6
    add     a7, s7, s8

    addi    a0, a0, 1
    j       loop

    addi    s1, s1, 1
    addi    s2, s2, 1
    addi    s3, s3, 1
    addi    s4, s4, 1
    addi    s5, s5, 1
    addi    s6, s6, 1
    addi    s7, s7, 1
    addi    s8, s8, 1

done:
    li      t1, 200
    bne     a0, t1, fail         
    li      t1, 0xABC
    bne     s0, t1, fail         
    li      t1, 0x5EED
    bne     t5, t1, fail          
    li      t1, 210               
    bne     s11, t1, fail
    li      t1, 211             
    bne     a2, t1, fail

    li      a0, 1
    sw      a0, 0(t6)
1:  j       1b

fail:
    li      a0, 2
    sw      a0, 0(t6)
2:  j       2b
