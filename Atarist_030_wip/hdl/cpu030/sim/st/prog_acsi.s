| [TOS206] TOS 2.06 dmaboot ACSI probe replica (E01782..E0180A): DMA chip probe under a BERR trap,
| per device: mode/count writes, long command write to $FF8604 (data+mode), GPIP bit 5 poll.
        .text
        .long   0x00008000
        .long   start
start:  move.w  #0x2700,%sr
        lea     0x8000,%sp
        move.b  #0x0a,0xffff8001.w
        lea     berr(%pc),%a0
        move.l  %a0,0x8.w
        clr.l   0x1100.w
        move.l  %sp,%a2
        tst.w   0xffff8606.w
        bra.s   1f
berr:   move.l  %a2,%sp
        move.w  #0xbe,0x1100.w
1:      lea     0xffff8604.w,%a1
        moveq   #0,%d4
dev:    move.w  #0x190,2(%a1)
        move.w  #0x090,2(%a1)
        move.w  #1,(%a1)
        move.l  %d4,%d1
        lsl.l   #5,%d1
        or.l    #0x08,%d1
        swap    %d1
        move.w  #0x88,2(%a1)
        move.w  #0x8a,%d1
        move.l  %d1,(%a1)
        move.w  #3000,%d3
2:      btst    #5,0xfffffa01.w
        beq.s   3f
        dbra    %d3,2b
3:      move.w  %d3,%d0
        move.w  %d4,%d2
        lsl.w   #2,%d2
        lea     0x1200.w,%a3
        move.w  %d0,0(%a3,%d2.w)
        move.w  #0x8a,2(%a1)
        move.w  (%a1),%d0
        move.w  %d0,2(%a3,%d2.w)
        addq.w  #1,%d4
        cmp.w   #2,%d4
        bne     dev
        move.w  #0xdead,0x1300.w
9:      bra.s   9b
