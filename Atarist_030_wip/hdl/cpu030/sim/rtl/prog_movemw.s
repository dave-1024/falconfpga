| [OPTION-A] MOVEM register-to-memory coverage for the overlapped ALU load:
| long/word, (An), -(An) with An in the list, d16(An), abs.w, (d8,An,Xn), sparse and
| single-register masks, then re-read and store a checksum. All writes compared by cmp_wr.sh.
        .text
        .org 0
        .long   0x00008000
        .long   0x00fc0008
start:
        moveq   #1,d0
        move.l  #0x11112222,d1
        move.l  #0x33334444,d2
        move.l  #0x55556666,d3
        move.l  #0x77778888,d4
        move.l  #0x9999aaaa,d5
        move.l  #0xbbbbcccc,d6
        move.l  #0xddddeeee,d7
        lea     0x6000,a0
        lea     0x6100,a1
        lea     0x6200,a2
        move.l  #0xa3a3a3a3,a3
        move.l  #0xa4a4a4a4,a4
        move.l  #0xa5a5a5a5,a5
        lea     0x6400,a6
        movem.l d0-d7/a0-a6,(a0)
        movem.w d0-d7/a0-a6,(a1)
        movem.l d0-d7/a0-a6,-(a6)
        move.l  a6,0x6500
        lea     0x6600,a6
        movem.w d1/d3/d5/a2/a4,-(a6)
        move.l  a6,0x6504
        movem.l d2/d6/a3,8(a2)
        movem.w d7,0x6700
        movem.l d4,0x6704
        moveq   #4,d0
        movem.l d1-d3,(2,a2,d0.w)
        movem.w a0-a2,0x6710
        lea     0x6800,a1
        movem.l a1,-(a1)
        move.l  a1,0x6508
        move.w  #7,d0
1:      movem.l d1-d7,-(a6)
        movem.l (a6)+,d1-d7
        dbra    d0,1b
        lea     0x6000,a0
        moveq   #0,d0
        move.w  #0x1ff,d1
2:      add.l   (a0)+,d0
        dbra    d1,2b
        move.l  d0,0x5000
        move.l  #0x600dc0de,0x3300
3:      bra.s   3b
