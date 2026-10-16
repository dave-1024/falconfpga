| [OPTION-A] MOVEM memory-to-register coverage for the early read request (step 3):
| long/word (sign extension), (An), (An)+ with An in the list, d16(An) with An in the list, (d8,An,Xn), abs,
| sparse masks; every result is stored with plain moves so cmp_wr.sh compares it.
        .text
        .org 0
        .long   0x00008000
        .long   0x00fc0008
start:
        lea     0x6000,a0
        move.l  #0x01020304,d0
        moveq   #31,d1
1:      move.l  d0,(a0)+
        add.l   #0x8f1e2d3c,d0
        dbra    d1,1b
        lea     0x5100,a5
        lea     0x6000,a0
        movem.l (a0),d0-d7/a1-a4
        movem.l d0-d7/a1-a4,(a5)
        lea     0x6004,a0
        movem.w (a0),d0-d7/a1-a4
        movem.l d0-d7/a1-a4,0x30(a5)
        lea     0x6008,a2
        movem.l (a2)+,d1/d3/a2/a3
        movem.l d1/d3/a2/a3,0x60(a5)
        lea     0x6010,a3
        movem.l 4(a3),d4/a3/a4
        movem.l d4/a3/a4,0x70(a5)
        lea     0x6000,a1
        moveq   #8,d0
        movem.w (2,a1,d0.w),d5-d7
        movem.l d5-d7,0x80(a5)
        movem.l 0x6040,d0-d2
        movem.l d0-d2,0x90(a5)
        lea     0x6000,a0
        movem.w (a0)+,d0
        move.l  d0,0xa0(a5)
        move.l  a0,0xa4(a5)
        move.w  #7,d7
2:      movem.l (a0)+,d0-d6
        add.l   d0,d6
        move.l  d6,0xb0(a5)
        dbra    d7,2b
        move.l  #0x600dc0de,0x3300
3:      bra.s   3b
