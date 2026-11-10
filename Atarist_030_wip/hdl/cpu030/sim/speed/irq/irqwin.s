| One delayed level-4 IRQ (IPL_MODE=2, trigger write to $3400) during a MOVEQ/ADD stream.
        .org 0
        dc.l    0x2000, start
start:  move.w  #0x2700,%sr
        lea     0x400,%sp
        lea     h4(%pc),%a0
        move.l  %a0,0x70
        clr.l   0x3200
        clr.l   0x3204
        moveq   #0,%d1
        moveq   #0,%d2
        moveq   #0,%d3
        move.w  #0x2000,%sr
        move.w  #1,0x3400
        move.w  #80,%d0
lp:     moveq   #1,%d1
        add.l   %d1,%d2
        add.l   %d2,%d3
        eor.l   %d1,%d3
        addq.l  #1,%d2
        subq.w  #1,%d0
        bne.s   lp
        move.w  #0x2700,%sr
        move.l  %d2,0x3300
        move.l  %d3,0x3304
        move.l  0x3200,0x3310
        move.l  0x3204,0x3314
1:      bra.s   1b
h4:     addq.l  #1,0x3200
        move.l  2(%sp),%d6
        move.l  %d6,0x3204
        rte
