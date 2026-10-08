| F64: TOS 2.06 Line-A init as called by the AES on a menu title (E17CF4 jsr E22870: A000):
| the handler (E068E4) reads the opword through the stacked PC, steps the PC by 2, dispatches
| through a table and returns with RTE to 4n+2 / 4n; the caller copies Line-A variables.
| Line-A opcodes at 4n and 4n+2, from supervisor and user mode. Results at $5000..; DONE at $3300.
        .text
        .org 0
        .long   0x00008000
        .long   0x00fc0008
start:
        lea     0x5000,a4
        move.l  #lineah,0x28
        move.l  #errh,0x08
        move.l  #errh,0x0c
        move.l  #errh,0x10
        move.l  #errh,0x2c
        move.l  #errh,0x2c
        move.l  #trap0h,0x80
        lea     0x7000,a0
        move.l  a0,usp
        moveq   #0,d7
        moveq   #3,d6
loop:   jsr     la_even
        move.l  a0,(a4)+
        move.l  d0,(a4)+
        jsr     la_odd
        move.l  a0,(a4)+
        move.l  d0,(a4)+
        add.l   d0,d7
        dbra    d6,loop
        move.w  #0x0000,sr              | user mode
        jsr     la_even
        add.l   d0,d7
        jsr     la_odd
        add.l   d0,d7
        dc.w    0xa001                  | inline at whatever alignment
        add.l   d0,d7
        trap    #0                      | back to supervisor
        move.l  d7,(a4)+
        move.l  #0x600dc0de,0x3300
self:   bra.s   self
        .balignw 4,0x4e71
la_even:
        dc.w    0xa000                  | 4n
        suba.w  #0x0358,a0
        move.l  a0,0x4000
        lea     0x4004,a1
        move.w  #5,d0
1:      move.w  (a0)+,(a1)+
        dbf     d0,1b
        move.l  0x4004,d0
        rts
        .balignw 4,0x4e71
        nop
la_odd: dc.w    0xa002                  | 4n+2
        suba.w  #0x0358,a0
        move.l  (a0),d0
        rts
trap0h: bset    #5,(sp)
        rte
        .balignw 4,0x4e71
lineah: movea.l 2(sp),a1
        move.w  (a1),d2
        and.w   #0x0fff,d2
        addq.l  #2,a1
        move.l  a1,2(sp)
        cmp.w   #0x000f,d2
        bhi.b   9f
        lsl.w   #2,d2
        movea.l latab(pc,d2.w),a1
        movem.l d3-d7/a3-a5,-(sp)
        jsr     (a1)
        movem.l (sp)+,d3-d7/a3-a5
9:      rte
latab:  .long   la0, la1, la2
la0:    lea     0x2904,a0
        move.l  a0,d0
        lea     0x00fc0000,a1
        rts
la1:    move.l  #0x11112222,d0
        lea     0x2904,a0
        rts
        nop
la2:    move.l  #0x33334444,d0
        lea     0x2a04,a0
        rts
errh:   move.l  #0xeeee0000,(a4)+
        move.l  2(sp),(a4)+
        move.w  (sp),(a4)+
        move.l  #0x600dc0de,0x3300
        bra.s   errh
