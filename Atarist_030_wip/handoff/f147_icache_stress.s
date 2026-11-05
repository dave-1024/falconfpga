        .text
        .org 0
        .long 0x00007000
        .long 0x00fc0008
        jmp start
        .org 0x10000-8
start:  moveq #1,d7
        movec d7,cacr
        lea loopA(pc),a0
        lea 0x01000000,a1
        move.w #(loopAe-loopA)/2-1,d0
cpA:    move.w (a0)+,(a1)+
        dbf d0,cpA
        lea loopM(pc),a0
        lea 0x01000102,a1
        move.w #(loopMe-loopM)/2-1,d0
cpM:    move.w (a0)+,(a1)+
        dbf d0,cpM
        move.w #1,0x3400
        jsr 0x01000000
        move.w #2,0x3400
        jsr 0x01000102
        move.w #0xffff,0x3400
        move.l #0x600dc0de,0x3300
hang:   bra.s hang
        .balign 4
loopA:  move.l #4095,d0
lpA:    subq.l #1,d0
        bne.s lpA
        rts
loopAe:
        .balign 2
loopM:  move.l #4095,d0
lpM:    subq.l #1,d0
        bne.s lpM
        rts
loopMe:
