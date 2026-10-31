| [F116] XaAES xaaes.km+$3266: move.w d3,d5 ; addq.w #1,d5 ; move.l d2,-(a7) ; muls.w #$30,d3 ;
| pea (bd.l,d3.l) [4870 39B0, full format, base suppressed] ; jsr (a0). The board pushed bd+$01FD2000.
| Each case stores the pea value at $5000.. ; expect bd + 48*i.
        .text
        .org 0
        .long 0x00008000
        .long 0x00fc0008
        lea 0x5000,a5
        move.l #0x01fd2072,d2
        moveq #0,d6
loop:   moveq #3,d0
        movea.l d0,a0
        move.w d6,d3
        move.w d3,d5
        addq.w #1,d5
        move.l d2,-(a7)
        muls.w #0x30,d3
        pea (0x1fc7dda.l,d3.l)
        move.l (a7)+,(a5)+
        addq.l #4,a7
| same without the push before muls
        move.w d6,d3
        muls.w #0x30,d3
        pea (0x1fc7dda.l,d3.l)
        move.l (a7)+,(a5)+
        addq.w #1,d6
        cmp.w #4,d6
        bne loop
        move.l #0x600dc0de,0x3300
h:      bra.s h
