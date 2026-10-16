| [PH2] Bus gap bench (gap.sh): back-to-back transfer mixes, as in RAM_PATH.md.
| rd.l, wr.l, copy (read then write), movem.l, dbra-only loop, then the DONE marker.
        .text
        .org 0
        .long   0x00008000
        .long   0x00fc0008
start:
        lea     0x6000,a0
        lea     0x6800,a1
        move.w  #15,d1
1:      move.l  (a0),d0
        dbra    d1,1b
        move.w  #15,d1
2:      move.l  d0,(a1)
        dbra    d1,2b
        lea     0x6000,a0
        move.w  #15,d1
3:      move.l  (a0)+,(a1)+
        dbra    d1,3b
        lea     0x6000,a0
        move.w  #3,d1
4:      movem.l (a0),d2-d7
        movem.l d2-d7,(a1)
        dbra    d1,4b
        move.w  #15,d1
5:      dbra    d1,5b
        move.l  #0x600dc0de,0x3300
6:      bra.s   6b
