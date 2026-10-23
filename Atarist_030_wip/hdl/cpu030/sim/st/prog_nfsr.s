| BLTMASK tests 6 and 7 in RTL: primer (buffer = a5c33c5a), then
| T6: 9x5 sxinc 2 syinc 4 dxinc 2 dyinc 80 masks 3fff/ffff/fffc skew $4b (NFSR, skew 11) shared, src $10100 dst $21000
| T7: 20x3 2/2 2/60 masks 00ff/0ff0/ff00 skew $c3 (FXSR+NFSR, skew 3) HOG, src $10400 dst $24000
        .text
        .long   0x00008000
        .long   start
start:  move.w  #0x2700,%sr
        lea     0x8000,%sp
        move.b  #0x0a,0xffff8001.w
        lea     0x10000,%a0                | src 2 KB xorshift; dst $21000 and $24000 (2 KB each) = ~src
        lea     0x21000,%a1
        lea     0x24000,%a3
        move.l  #0x12345678,%d1
        move.w  #511,%d7
1:      move.l  %d1,%d2
        lsl.l   #8,%d2
        lsl.l   #5,%d2
        eor.l   %d2,%d1
        move.l  %d1,%d2
        lsr.l   #8,%d2
        lsr.l   #8,%d2
        lsr.l   #1,%d2
        eor.l   %d2,%d1
        move.l  %d1,%d2
        lsl.l   #5,%d2
        eor.l   %d2,%d1
        move.l  %d1,(%a0)+
        not.l   %d1
        move.l  %d1,(%a1)+
        move.l  %d1,(%a3)+
        not.l   %d1
        dbra    %d7,1b
        lea     0xffff8a00.w,%a2
        bsr     primer
        move.w  #2,0x20(%a2)
        move.w  #4,0x22(%a2)
        move.l  #0x10100,0x24(%a2)
        move.w  #0x3fff,0x28(%a2)
        move.w  #0xffff,0x2a(%a2)
        move.w  #0xfffc,0x2c(%a2)
        move.w  #2,0x2e(%a2)
        move.w  #80,0x30(%a2)
        move.l  #0x21000,0x32(%a2)
        move.w  #9,0x36(%a2)
        move.w  #5,0x38(%a2)
        move.b  #2,0x3a(%a2)
        move.b  #3,0x3b(%a2)
        move.b  #0x4b,0x3d(%a2)
        move.b  #0x80,0x3c(%a2)
        bsr     wait
        bsr     primer
        move.w  #2,0x20(%a2)
        move.w  #2,0x22(%a2)
        move.l  #0x10400,0x24(%a2)
        move.w  #0x00ff,0x28(%a2)
        move.w  #0x0ff0,0x2a(%a2)
        move.w  #0xff00,0x2c(%a2)
        move.w  #2,0x2e(%a2)
        move.w  #60,0x30(%a2)
        move.l  #0x24000,0x32(%a2)
        move.w  #20,0x36(%a2)
        move.w  #3,0x38(%a2)
        move.b  #2,0x3a(%a2)
        move.b  #3,0x3b(%a2)
        move.b  #0xc3,0x3d(%a2)
        move.b  #0xc0,0x3c(%a2)
        bsr     wait
        move.l  #0x600dc0de,0x1ffc.w
9:      bra.s   9b
wait:   btst    #7,0x3c(%a2)
        bne.s   wait
        rts
primer: move.l  #0xa5c33c5a,0x18000
        move.w  #2,0x20(%a2)
        move.w  #2,0x22(%a2)
        move.l  #0x18000,0x24(%a2)
        move.w  #-1,0x28(%a2)
        move.w  #-1,0x2a(%a2)
        move.w  #-1,0x2c(%a2)
        move.w  #2,0x2e(%a2)
        move.w  #2,0x30(%a2)
        move.l  #0x18010,0x32(%a2)
        move.w  #2,0x36(%a2)
        move.w  #1,0x38(%a2)
        move.b  #2,0x3a(%a2)
        move.b  #3,0x3b(%a2)
        clr.b   0x3d(%a2)
        move.b  #0xc0,0x3c(%a2)
        bra     wait
