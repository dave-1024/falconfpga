        .text
        .org 0
        .long 0x00007000
        .long 0x00fc0008
        jmp start
        .org 0x10000-8
start:  move.l #0x00003111,d7
        movec d7,cacr
        lea loopM(pc),a0
        lea 0x8102,a1
        move.w #(loopMe-loopM)/2-1,d0
cpM:    move.w (a0)+,(a1)+
        dbf d0,cpM
        move.w #1,0x3400
        jsr 0x8102
        move.w #0xffff,0x3400
        move.l #0x600dc0de,0x3300
hang:   bra.s hang
loopM:  move.l #4095,d0
lpM:    subq.l #1,d0
        bne.s lpM
        rts
loopMe:
