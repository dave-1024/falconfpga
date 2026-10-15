| Float Math crash: AUTOFPU $55D0E..$55D20 (board) beq/lea/bra/lea with the same
| 4n/4n+2 alignment, run from user mode with periodic level 4 (AVEC) and level 6
| (vector 69, MFP-like) interrupts (tb030 IPL_MODE=3, VEC6=69). Any exception
| (single shot: NITER=0, TAKEN=0/1, tb030 IPL_MODE=2 IRQ_DLY sweep, TRIG6)
| other than the IRQs (CHK etc.) or a wrong A0 -> $EEEE/$BADBAD at $5000. DONE at $3300.
        .text
        .org 0
        .long   0x00008000
        .long   0x00fc0008
start:
        lea     0x5000,a4
        move.l  #vblh,0x70
        move.l  #mfph,0x114
        lea     0x08,a0
        moveq   #9,d0
1:      move.l  #errh,(a0)+
        dbra    d0,1b
        clr.l   0x5100
        clr.l   0x5104
        lea     0x7000,a0
        move.l  a0,usp
        move.w  #NITER,d5
        move.w  #0x0300,sr              | user mode, IPL mask 3
loop:   moveq   #1,d7
        and.w   d5,d7
        eor.w   #TAKEN,d7
        move.l  d0,0x3400               | IPL_MODE=2: trigger point
        lea     0x6000,a6
        jsr     cmpf(pc)
        .balignw 4,0x4e71
        bles    bad                     | board $55D0C (4n), not taken
        tstl    d7                      | $55D0E 4n+2
        beqs    2f                      | $55D10 4n
        lea     36(a4),a0               | $55D12
        bras    3f                      | $55D16 4n+2
2:      lea     42(a4),a0               | $55D18 4n
3:      moveq   #0,d0
        moveq   #0,d1
        move.l  d1,-(sp)
        move.l  d0,-(sp)
        addq.l  #8,sp
        lea     36(a4),a1
        tst.l   d7
        bne.s   4f
        addq.l  #6,a1
4:      cmpa.l  a0,a1
        bne     bad
        dbra    d5,loop
        move.l  0x5100,(a4)+
        move.l  0x5104,(a4)+
        move.l  #0x600dc0de,0x3300
self:   bra.s   self
bad:    move.l  #0xbadbad00,(a4)+
        move.l  d5,(a4)+
        move.l  #0x600dc0de,0x3300
        bra.s   self
cmpf:   moveq   #1,d0                   | like the $567ac compare: flags GT
        cmp.l   #0,d0
        rts
        .balignw 4,0x4e71
vblh:   addq.l  #1,0x5100
        rte
        .balignw 4,0x4e71
mfph:   addq.l  #1,0x5104
        move.w  #0x2600,sr
        nop
        rte
errh:   move.l  #0xeeee0000,(a4)+
        move.l  (sp),(a4)+
        move.l  4(sp),(a4)+
        move.l  #0x600dc0de,0x3300
        bra.s   errh
