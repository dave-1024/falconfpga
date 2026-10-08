| F62 TOS 2.06 vblank-sync loop timing (E013F0-E013FA): 616 iterations of
| cmp.b (a0),d4 / bne / dbf with the loop target at a 4n+2 address, as in TOS.
        .text
        .org 0
        .long   0x00008000
        .long   0x00fc0008
start:
        lea     0x7000,a0
        clr.b   (a0)
        moveq   #0,d4
        bra.s   l0
        .balign 4
l0:     move.b  (a0),d4                 | 4n
        move.w  #615,d3
l1:     cmp.b   (a0),d4                 | loop target, 4n+2
        bne.s   l0
        dbf     d3,l1
        move.b  #0x10,(a0)
        move.l  #0x600dc0de,0x3300
1:      bra.s   1b
