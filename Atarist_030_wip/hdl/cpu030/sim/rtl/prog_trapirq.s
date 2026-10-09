| F64: AES-style TRAP #2 / TRAP #13 polling loop from user mode with periodic
| level 4 (VBL-like) and level 6 (MFP-like) interrupts (tb030 IPL_MODE=3).
| Handlers and return points at 4n and 4n+2, MOVE to SR, MOVEM, RTE.
| Results at $5000.. must not depend on interrupt timing; DONE at $3300.
        .text
        .org 0
        .long   0x00008000
        .long   0x00fc0008
start:
        lea     0x5000,a4
        move.l  #vblh,0x70
        move.l  #mfph,0x78
        move.l  #trap2h,0x88
        move.l  #trap13h,0xb4
        move.l  #errh,0x08
        move.l  #errh,0x0c
        move.l  #errh,0x10
        move.l  #errh,0x2c
        move.l  #errh,0x28
        clr.l   0x5100
        clr.l   0x5104
        lea     0x7000,a0
        move.l  a0,usp
        moveq   #0,d7
        moveq   #11,d1
        moveq   #22,d2
        moveq   #33,d3
        move.w  #15,d6
        move.w  #0x0300,sr              | user mode, IPL mask 3
loop:   moveq   #0x73,d0
        move.l  #0x1234,d1
        trap    #2                      | returns to 4n+2 or 4n (see .balignw below)
        add.l   d0,d7
        nop
        move.w  #11,-(sp)
        trap    #13
        addq.l  #2,sp
        add.l   d0,d7
        rol.l   #3,d7
        cmp.l   #0x1234,d1
        bne     bad
        cmp.l   #22,d2
        bne     bad
        cmp.l   #33,d3
        bne     bad
        bsr.s   sub2
        dbra    d6,loop
        move.l  d7,(a4)+
        move.l  #0x600dc0de,0x3300
self:   bra.s   self
bad:    move.l  #0xbadbad00,(a4)+
        move.l  d7,(a4)+
        move.l  #0x600dc0de,0x3300
        bra.s   self
sub2:   moveq   #0x15,d0
        trap    #2
        eor.l   d0,d7
        rts
        .balignw 4,0x4e71
        nop
trap2h: movem.l d1-d6/a0-a3,-(sp)
        move.w  sr,-(sp)
        move.w  #0x2700,sr
        lea     tab2(pc),a0
        move.l  d0,d1
        and.w   #3,d1
        add.w   d1,d1
        move.w  0(a0,d1.w),d1
        jsr     0(a0,d1.w)
        move.w  (sp)+,sr
        movem.l (sp)+,d1-d6/a0-a3
        rte
tab2:   .word   f0-tab2, f1-tab2, f2-tab2, f3-tab2
f0:     addq.l  #1,d0
        rts
        nop
f1:     mulu.w  #3,d0
        rts
f2:     not.l   d0
        rts
        nop
f3:     move.l  #0x55aa,d2
        add.l   d2,d0
        move.l  usp,a1
        move.l  (a1),d3
        rts
        .balignw 4,0x4e71
trap13h:
        btst    #5,(sp)
        bne.s   1f
        move.l  usp,a0
        move.w  (a0),d0
        bra.s   2f
1:      move.w  6(sp),d0
2:      ext.l   d0
        swap    d0
        rte
        .balignw 4,0x4e71
        nop
vblh:   addq.l  #1,0x5100
        movem.l d0-d2/a0,-(sp)
        move.l  0x5100,d0
        moveq   #7,d1
3:      add.l   d0,d2
        dbra    d1,3b
        move.l  d2,0x5108
        movem.l (sp)+,d0-d2/a0
        rte
        .balignw 4,0x4e71
mfph:   addq.l  #1,0x5104
        move.w  #0x2500,sr              | lower the mask in the handler like the MFP code
        nop
        rte
errh:   move.l  #0xeeee0000,(a4)+
        move.l  2(sp),(a4)+
        move.l  #0x600dc0de,0x3300
        bra.s   errh
