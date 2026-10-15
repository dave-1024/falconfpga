| Float panic: AUTOFPU.BIN FPU/SFP004 probe (GEMBENCH 4.03 BIN/AUTOFPU.BIN $579A0-$57A80),
| supervisor, _longframe = 1. Results at $5000: SSP before, D3 after FNOP, SSP after FNOP,
| frame format word seen by the BERR handler, D3 after SFP probe, SSP at the end.
        .text
        .org 0
        .long   0x00008000
        .long   0x00fc0008
start:
        lea     0x5000,a4
        move.l  #linef,0x2c
        move.l  #berr,0x08
        move.l  sp,(a4)+                | SSP before
        moveq   #1,d3
        lea     afterf(pc),a2
        fnop
        fsave   -(sp)
        moveq   #0,d0
        move.b  1(sp),d0
        adda.w  d0,sp
        addq.l  #4,sp
afterf: move.l  d3,(a4)+                | -1 expected (no FPU)
        move.l  sp,(a4)+                | = SSP before
        lea     aftersfp(pc),a2
        tst.w   0xfffa40
        move.w  #3,0xfffa42
aftersfp:
        move.l  d6,(a4)+                | frame format word
        move.l  d3,(a4)+                | 0 expected
        move.l  sp,(a4)+                | = SSP before
        move.w  #1,0x3400               | DONE
1:      bra.s   1b
linef:  moveq   #-1,d3
        move.l  a2,2(sp)
        rte
berr:   move.w  6(sp),d6
        move.w  6(sp),d3
        andi.w  #0xf000,d3
        cmpi.w  #0xa000,d3
        beq.s   1f
        move.w  (sp),d3
        lea     84(sp),sp
2:      move.w  d3,(sp)
        move.l  a2,2(sp)
        clr.w   6(sp)
        moveq   #0,d3
        rte
1:      move.w  (sp),d3
        lea     24(sp),sp
        bra.s   2b
