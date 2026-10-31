| [F98] two back-to-back pending writes to the same Dn, then an indexed EA (strlen pattern).
| xaaes env loop: jsr strlen (move.l a0,d0 ... suba.l d0,a0; move.l a0,d0; rts); lea (1,a2,d0.l),a2.
| Every case must give a2-$4000 = 6 (string length 5). Results words at $5000.. (expect_dw2.txt).
        .text
        .org 0
        .long 0x00008000
        .long 0x00fc0008
        lea 0x2100,a0
        move.l #0x41424344,(a0)
        move.w #0x4500,4(a0)
        lea 0x5000,a5
        moveq #3,d6
loop:
| C1 inline strlen
        lea 0x4000,a2
        lea 0x2100,a0
        addq.l #1,a0
        move.l a0,d0
1:      tst.b -1(a0)
        beq.s 2f
        addq.l #1,a0
        bra.s 1b
2:      suba.l d0,a0
        move.l a0,d0
        lea (1,a2,d0.l),a2
        bsr res
| C2 two moves back to back
        lea 0x4000,a2
        move.l #0x2101,a0
        move.l #5,a1
        move.l a0,d0
        move.l a1,d0
        lea (1,a2,d0.l),a2
        bsr res
| C3 moveq twice
        lea 0x4000,a2
        moveq #9,d0
        moveq #5,d0
        lea (1,a2,d0.l),a2
        bsr res
| C4 RMW after move
        lea 0x4000,a2
        move.l #0x2106,a0
        move.l a0,d0
        sub.l #0x2101,d0
        lea (1,a2,d0.l),a2
        bsr res
| C5 subroutine strlen with rts in between
        lea 0x4000,a2
        pea 0x2100
        bsr sl
        lea (1,a2,d0.l),a2
        addq.l #4,sp
        bsr res
| C6 subroutine via jsr (a0)
        lea 0x4000,a2
        pea 0x2100
        lea sl(pc),a0
        jsr (a0)
        lea (1,a2,d0.l),a2
        addq.l #4,sp
        bsr res
| C7 move then suba then move, full format bd.l
        lea 0x4000,a2
        move.l #0x2106,a0
        move.l a0,d0
        suba.l #0x2101,a0
        move.l a0,d0
        lea (1.l,a2,d0.l),a2
        bsr res
| C8 word index
        lea 0x4000,a2
        move.l #0x12340009,d0
        move.w #5,d0
        lea (1,a2,d0.w),a2
        bsr res
        dbra d6,loop
        move.l #0x600dc0de,0x3300
h:      bra.s h
| result: a2-$4000 as word
res:    move.l a2,d7
        sub.l #0x4000,d7
        move.w d7,(a5)+
        rts
| kernel strlen
sl:     move.l (4,sp),a0
        addq.l #1,a0
        move.l a0,d0
        tst.b (-1,a0)
        beq.s 4f
3:      addq.l #1,a0
        tst.b (-1,a0)
        bne.s 3b
4:      suba.l d0,a0
        move.l a0,d0
        rts
