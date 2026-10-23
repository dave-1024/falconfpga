| [PFCOF] change-of-flow mix in ROM (E00000), VDI/AES-like: bsr/rts, jsr (An), jmp table,
| forward Bcc taken/not taken, short dbra loops, line drawing style inner loop.
        .text
        .long   0x00008000
        .long   start
start:  move.w  #0x2700,%sr
        lea     0x8000,%sp
        move.b  #0x0a,0xffff8001.w
        moveq   #0,%d6
        move.w  #23,%d5
outer:  moveq   #7,%d0
        and.w   %d5,%d0
        add.w   %d0,%d0
        move.w  jtab(%pc,%d0.w),%d1
        jmp     jtab(%pc,%d1.w)
jtab:   .word   f0-jtab,f1-jtab,f2-jtab,f3-jtab,f0-jtab,f1-jtab,f2-jtab,f3-jtab
f0:     bsr.s   sub_a
        bra.s   next
f1:     lea     sub_b(%pc),%a0
        jsr     (%a0)
        bra.s   next
f2:     bsr.w   sub_c
        bra.s   next
f3:     bsr.s   sub_a
        bsr.w   sub_c
next:   dbra    %d5,outer
        move.l  %d6,0x1000.w
        move.l  #0x600dc0de,0x1ffc.w
9:      bra.s   9b
sub_a:  move.w  %d5,%d2
        btst    #0,%d2
        beq.s   1f
        addq.l  #3,%d6
        rts
1:      subq.l  #1,%d6
        cmp.w   #50,%d2
        bhi.s   2f
        addq.l  #7,%d6
2:      rts
sub_b:  moveq   #5,%d3
1:      add.l   %d3,%d6
        tst.w   %d3
        bmi.s   2f
        lsl.l   #1,%d6
2:      dbra    %d3,1b
        rts
sub_c:  moveq   #5,%d3                  | Bresenham-like inner loop
        moveq   #0,%d4
1:      add.w   #23,%d4
        cmp.w   #40,%d4
        blt.s   2f
        sub.w   #40,%d4
        addq.l  #1,%d6
2:      dbra    %d3,1b
        rts
