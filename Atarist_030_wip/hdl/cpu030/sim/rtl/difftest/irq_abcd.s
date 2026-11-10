# F157v regression: IRQ during memory ABCD/SBCD RMW must keep the incoming X.
# IPL_MODE=2, sweep IRQ_DLY. Compare vs F156 (run_one.sh) and expect $3320=600D.
# Before F157v, DLY 21 and 29 wrote 0x00 instead of 0x01 at the first predec ABCD.
        .text
        .long 0x00002F00
        .long 0x00FC0008
start:  move.w #0x2700,sr
        lea 0x400,a7
        lea h4(pc),a0
        move.l a0,0x70
        clr.l 0x3200
        lea 0x2100,a0
        lea 0x2110,a1
        move.b #0x19,(a0)
        move.b #0x28,-(a0)
        move.b #0x34,(a1)
        move.b #0x45,-(a1)
        move.l #0x19,d1
        move.l #0x28,d2
        move.w #0x2000,sr
        move.w #1,0x3400
        move.w #40,d0
lp:     abcd d1,d2
        sbcd d2,d1
        abcd -(a1),-(a0)
        sbcd -(a0),-(a1)
        addq.l #2,a0
        addq.l #2,a1
        nbcd d2
        subq.w #1,d0
        bne.s lp
        move.w sr,d5
        move.w #0x2700,sr
        move.l 0x3200,0x3310
        move.w d5,0x3316
        andi.w #0x2000,d5
        bne.s ok
        move.w #0xDEAD,0x3320
        bra.s hang
ok:     move.w #0x600D,0x3320
        move.w #1,0x3300
hang:   bra.s hang
h4:     addq.l #1,0x3200
        move.w (sp),0x3208
        rte
