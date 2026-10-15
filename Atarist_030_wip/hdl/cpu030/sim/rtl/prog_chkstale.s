        .text
        .org 0
        .long   0x00008000
        .long   0x00fc0008
start:  lea     0x5000,a4
        move.l  #errh,0x18
        move.l  #trh,0x80
        move.l  #vblh,0x70
        move.w  #200,d5
        lea     0x7000,a0
        move.l  a0,usp
        move.w  #0x0300,sr
loop:   moveq   #5,d0
        move.w  #10,0x6000
        chk.w   0x6000,d0          | in range, no trap
        moveq   #-1,d0             | now d0 out of range
        nop
        jmp     1f
1:      bsr.s   sub
        trap    #0
        movem.l d0-d3,-(sp)
        movem.l (sp)+,d0-d3
        pea     2f
        rts
2:      link    a6,#-8
        unlk    a6
        lea     0x5000,a4
        moveq   #5,d0
        chk.w   0x6000,d0
        moveq   #-1,d0
        dbra    d5,loop
        move.l  #0x600dc0de,0x3300
self:   bra.s   self
sub:    rts
trh:    rte
vblh:   rte
errh:   move.l  #0xeeee0000,0x5000
        move.l  2(sp),0x5004
        move.l  #0x600dc0de,0x3300
        bra.s   errh
