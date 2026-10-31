| [F118] XaAES +$...FA02: move.w (76,a2),d0 ; muls.w #24,d0 ; ori.w #$80,(8,a4,d0.l)  (brief EA, RMW)
| a muls.w/divs.w result indexing a brief-format read-modify-write EA. Results at $5000+.
        .text
        .org 0
        .long 0x00008000
        .long 0x00fc0008
        lea 0x5000,a5
        lea 0x6000,a4
        lea 0x7000,a2
        move.w #2,(76,a2)
        clr.l 0x6038
        clr.l 0x6008
        move.l #0x12345678,d0
        move.w (76,a2),d0
        muls.w #24,d0
        ori.w #0x80,(8,a4,d0.l)
        move.l 0x6038,(a5)+
        move.l 0x6008,(a5)+
| same with addq to memory (RMW) and a plain move
        move.l #0x55aa0000,d0
        move.w (76,a2),d0
        muls.w #24,d0
        addq.w #1,(8,a4,d0.l)
        move.l 0x6038,(a5)+
        move.w (76,a2),d0
        muls.w #24,d0
        move.w #0x1234,(10,a4,d0.l)
        move.l 0x6038,(a5)+
        move.l #0x600dc0de,0x3300
h:      bra.s h
