        .text
        .org 0
        .long   0x00008000
        .long   0x00fc0008
start:
        moveq   #1,d0
        movec   d0,sfc
        move.l  #0x9100,0x9000
        move.w  #0x1234,0x9100
        lea     0x9000,a0
        moves.w ([a0]),d1
        move.w  d1,0x5000
        lea     -32(a0),a1
        moves.w ([32,a1]),d2
        move.w  d2,0x5002
        move.l  #0x600dc0de,0x3300
1:      bra.s   1b
