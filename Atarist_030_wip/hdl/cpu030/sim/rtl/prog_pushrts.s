| F64: the TOS dispatch idiom found on the board panel (E21D48: move.l $6ABE,-(sp); rts and
| E00D34: move.l $404,-(sp); moveq #-1,d0; rts): a long pushed on the stack and immediately
| popped by RTS as the new PC. Targets at 4n and 4n+2, abs.w/abs.l/immediate sources, the push
| at 4n/4n+2, the stack far from the code and right behind it (stack in RAM code area: snoop),
| in a loop so periodic interrupts (tb030 IPL_MODE=3) land on every phase. Results at $5000..
        .text
        .org 0
        .long   0x00008000
        .long   0x00fc0008
start:
        lea     0x5000,a4
        move.l  #vblh,0x70
        move.l  #mfph,0x78
        move.l  #errh,0x08
        move.l  #errh,0x0c
        move.l  #errh,0x10
        move.l  #errh,0x14
        move.l  #errh,0x18
        move.l  #errh,0x20
        move.l  #errh,0x28
        move.l  #errh,0x2c
        move.l  #errh,0x38
        move.l  #t_e,0x0404             | abs.w vector -> 4n target
        move.l  #t_o,0x6abe             | abs.l vector -> 4n+2 target
| copy the RAM version of the dispatch code to $3000 (stack right behind it at $3040)
        lea     ramc(pc),a0
        lea     0x3000,a1
        moveq   #(ramce-ramc)/2-1,d0
1:      move.w  (a0)+,(a1)+
        dbra    d0,1b
        moveq   #0,d7
        move.w  #0x2300,sr
        move.w  #39,d6
loop:   bsr     d_absw
        add.l   d0,d7
        bsr     d_absl
        add.l   d0,d7
        bsr     d_imm_o
        add.l   d0,d7
        bsr     d_imm_e
        add.l   d0,d7
        bsr     d_odd
        add.l   d0,d7
        movea.l sp,a5
        lea     0x3040,sp               | stack right behind the RAM code
        jsr     0x3000
        add.l   d0,d7
        jsr     0x3000+(r_2-ramc)
        add.l   d0,d7
        movea.l a5,sp
        rol.l   #1,d7
        dbra    d6,loop
        move.l  d7,(a4)+
        move.l  sp,(a4)+
        move.l  #0x600dc0de,0x3300
self:   bra.s   self
| --- dispatchers (each "returns" through the pushed address; the target does the rts) ---
        .balignw 4,0x4e71
d_absw: move.l  0x0404.w,-(sp)          | at 4n, like E00D34
        moveq   #-1,d0
        rts
        .balignw 4,0x4e71
        nop
d_absl: tst.w   d0                      | at 4n+2, like E21D48
        move.l  0x6abe,-(sp)
        rts
        .balignw 4,0x4e71
d_imm_o: move.l #t_o,-(sp)
        rts
        nop
d_imm_e: move.l #t_e,-(sp)
        rts
        nop
d_odd:  pea     t_o
        moveq   #2,d0
        rts
        .balignw 4,0x4e71
t_e:    addq.l  #3,d0                   | 4n target
        rts
        nop
t_o:    addq.l  #5,d0                   | 4n+2 target
        rts
| --- RAM copy (runs at $3000, stack at $3040 just above it) ---
        .balignw 4,0x4e71
ramc:   move.l  #0x3000+(r_t-ramc),-(sp)
        moveq   #7,d0
        rts
r_2:    move.l  0x6abe,-(sp)
        moveq   #1,d0
        rts
        nop
r_t:    addq.l  #4,d0
        rts
ramce:
        .balignw 4,0x4e71
        nop
vblh:   addq.l  #1,0x5100
        movem.l d0-d2/a0,-(sp)
        move.l  0x5100,d0
        moveq   #3,d1
6:      add.l   d0,d2
        dbra    d1,6b
        movem.l (sp)+,d0-d2/a0
        rte
        .balignw 4,0x4e71
mfph:   addq.l  #1,0x5104
        rte
errh:   move.l  #0xeeee0000,(a4)+
        move.l  2(sp),(a4)+
        move.w  6(sp),(a4)+
        move.l  #0x600dc0de,0x3300
        bra.s   errh
