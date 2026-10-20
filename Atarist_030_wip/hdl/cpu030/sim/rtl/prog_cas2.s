| [C1] CAS2 regression: update operands go to the right memory operands, back-to-back
| successful CAS2 do not hang, compare failures load Dc1/Dc2, Dn as address, long size.
| Results at $5000.. (expect_cas2.txt).
        .text
        .org 0
        .long 0x00008000
        .long 0x00fc0008
        lea 0x2000,a3
        lea 0x2400,a4
| case 1: both equal, word
        move.w #0x1111,(a3)
        move.w #0x2222,(a4)
        move.l #0x1111,d0
        move.l #0x2222,d1
        moveq #5,d2
        moveq #6,d3
        cas2.w d0:d1,d2:d3,(a3):(a4)
        move.w sr,d7
        move.w (a3),0x5000
        move.w (a4),0x5002
        move.w d7,0x5004
| case 2: three back-to-back successful CAS2 (Dc = Du)
        move.l #5,d0
        move.l #6,d1
        cas2.w d0:d1,d0:d1,(a3):(a4)
        cas2.w d0:d1,d0:d1,(a3):(a4)
        cas2.w d0:d1,d0:d1,(a3):(a4)
        move.w (a3),0x5006
        move.w (a4),0x5008
| case 3: compare 1 fails -> Dc1 = mem1, Dc2 = mem2, no write
        moveq #1,d0
        moveq #2,d1
        cas2.w d0:d1,d2:d3,(a3):(a4)
        move.w sr,d7
        move.w d0,0x500a
        move.w d1,0x500c
        move.w (a3),0x500e
        move.w (a4),0x5010
        move.w d7,0x5012
| case 4: compare 1 ok, compare 2 fails
        moveq #5,d0
        moveq #9,d1
        moveq #7,d2
        moveq #8,d3
        cas2.w d0:d1,d2:d3,(a3):(a4)
        move.w d0,0x5014
        move.w d1,0x5016
        move.w (a3),0x5018
        move.w (a4),0x501a
| case 5: long, data registers as addresses
        move.l #0x2100,d6
        move.l #0x2500,d5
        move.l #0x11112222,0x2100
        move.l #0x33334444,0x2500
        move.l #0x11112222,d0
        move.l #0x33334444,d1
        move.l #0xaaaabbbb,d2
        move.l #0xccccdddd,d3
        cas2.l d0:d1,d2:d3,(d6):(d5)
        move.l 0x2100,0x501c
        move.l 0x2500,0x5020
| case 6: two successful CAS2 then a failing one, back to back
        cas2.l d2:d3,d0:d1,(d6):(d5)
        cas2.l d0:d1,d2:d3,(d6):(d5)
        cas2.l d2:d3,d2:d3,(d6):(d5)
        move.l d2,0x5024
        move.l d3,0x5028
        move.l 0x2100,0x502c
        move.l 0x2500,0x5030
| case 7: flags. CAS2 compare 1 fails with mem1 - Dc1 negative and borrow (N=1 C=1),
| CAS.w fails with mem - Dc = $7fff - $ffff overflow (N=1 V=1 C=1), CAS.w succeeds (Z=1).
        move.w #0x0001,(a3)
        move.w #0x7fff,(a4)
        moveq #5,d0
        moveq #6,d1
        cas2.w d0:d1,d2:d3,(a3):(a4)
        move.w sr,0x5034
        move.l #0xffff,d0
        cas.w d0,d1,(a4)
        move.w sr,0x5036
        move.w #0x7fff,d0
        cas.w d0,d1,(a4)
        move.w sr,0x5038
        move.w (a4),0x503a
        move.l #0x600dc0de,0x3300
h:      bra.s h
