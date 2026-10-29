| [IRQWB] Dn write-back vs interrupt entry: MiNT strlen("") tail (move.l a0,d0; tst.b; beq; suba.l d0,a0;
| move.l a0,d0; rts) then lea (1,a2,d0.l),a2, with level 4 interrupts every IRQ_PER clocks. Handler saves and
| restores all registers with movem. Result: error count (word) at $5000, last bad a2 at $5004.
        .text
        .org 0
        .long   0x00008000
        .long   0x00fc0008
start:
        move.l  #irq,0x70
        clr.l   0x2000
        moveq   #0,d7
        move.w  #0x2000,sr              | IPL 0: interrupts on
        move.w  #1999,d6
lp:     lea     0x2000,a2
        move.l  a2,d0
        move.l  a2,-(sp)
        bsr.s   sl
        lea     (1,a2,d0.l),a2
        addq.l  #4,sp
        cmp.l   #0x2001,a2
        beq.s   1f
        addq.l  #1,d7
        move.l  a2,0x5004
1:      dbf     d6,lp
        move.w  #0x2700,sr
        move.w  d7,0x5000
        move.l  #0x600dc0de,0x3300
h:      bra.s   h
sl:     move.l  (4,sp),a0
        addq.l  #1,a0
        move.l  a0,d0
        tst.b   (-1,a0)
        beq.s   s2
s1:     addq.l  #1,a0
        tst.b   (-1,a0)
        bne.s   s1
s2:     suba.l  d0,a0
        move.l  a0,d0
        rts
irq:    movem.l d0-d7/a0-a6,-(sp)
        moveq   #-1,d0
        move.l  d0,a0
        moveq   #-1,d7
        movem.l (sp)+,d0-d7/a0-a6
        rte
