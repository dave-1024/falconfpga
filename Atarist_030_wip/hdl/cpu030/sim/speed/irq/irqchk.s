| irqchk: register-only instruction mix with periodic level 4 / level 6 interrupts (F141 IRQ_HOT bisect).
| Result: checksum of d0-d7/a0-a4 and the handler counts written to $3300.., then DONE.
        .org 0
        dc.l    0x2000, start
start:  move.w  #0x2700,%sr
        lea     0x400,%sp
        lea     h4(%pc),%a0
        move.l  %a0,0x70
        lea     h6(%pc),%a0
        move.l  %a0,0x78
        move.l  %a0,0x100
        lea     0x01000000,%a0
        lea     loop(%pc),%a1
        move.w  #(lend-loop)/4,%d0
cp:     move.l  (%a1)+,(%a0)+
        dbf     %d0,cp
        clr.l   0x3200
        clr.l   0x3204
        move.l  #0x12345678,%d1
        moveq   #0,%d2
        moveq   #0,%d3
        move.l  #0x9abcdef0,%d4
        moveq   #0,%d5
        moveq   #0,%d6
        moveq   #0,%d7
        lea     0x10,%a2
        lea     0x20,%a3
        move.w  #0x2000,%sr
        move.l  #100,%d0
        jsr     loop(%pc)
        move.l  #100,%d0
        jsr     0x01000000
        move.w  #0x2700,%sr
        add.l   %d1,%d2
        add.l   %d3,%d2
        add.l   %d4,%d2
        add.l   %d5,%d2
        add.l   %d6,%d2
        add.l   %d7,%d2
        add.l   %a2,%d2
        add.l   %a3,%d2
        move.l  %d2,0x3300
1:      bra.s   1b
loop:   moveq   #5,%d7
        add.l   %d7,%d1
        eor.l   %d1,%d4
        swap    %d4
        cmp.l   %d1,%d4
        scs     %d5
        tst.l   %d4
        smi     %d6
        add.l   %d5,%d3
        sub.l   %d6,%d3
        moveq   #3,%d7
        lsl.l   #3,%d1
        ror.l   #5,%d4
        exg     %d1,%d4
        move.l  %d1,%d7
        not.l   %d7
        and.l   %d7,%d3
        or.l    %d4,%d3
        addq.l  #1,%a2
        adda.l  %d7,%a3
        cmpa.l  %a2,%a3
        bclr    #2,%d3
        btst    #1,%d3
        sne     %d6
        ext.w   %d6
        ext.l   %d6
        add.l   %d6,%d3
        subq.l  #1,%d0
        bne.s   loop
        rts
lend:
h4:     addq.l  #1,0x3200
        move.l  %d1,-(%sp)
        move.l  6(%sp),%d1
        eor.l   %d1,0x3204
        move.l  (%sp)+,%d1
        rte
h6:     addq.l  #1,0x3200
        rte
