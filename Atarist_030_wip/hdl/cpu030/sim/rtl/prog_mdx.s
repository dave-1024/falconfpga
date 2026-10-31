| [F117] Grok 5.1-5.4 + remainder and bfffo variants: a multi-clock Dn writer (divu/divs/muls.l/bf*)
| directly followed by an EA that indexes with that Dn. Each result is stored as a long at $5000+.
| Pass 1 caches off, pass 2 with CACR = I+D enabled (d7 = pass).
        .text
        .org 0
        .long 0x00008000
        .long 0x00fc0008
        lea 0x5000,a5
        moveq #0,d7
pass:   lea 0x2000,a2
| 5.1 divul.l -> brief lea
        move.l #100,d0
        move.l #7,d1
        divul.l d1,d0
        lea (10,a2,d0.l),a0
        move.l a0,(a5)+
| 5.1r divul.l remainder (Dr:Dq) -> brief lea on Dr
        move.l #100,d0
        divul.l d1,d2:d0
        lea (10,a2,d2.l),a0
        move.l a0,(a5)+
| 5.1s divsl.l remainder and quotient, negative dividend
        move.l #-100,d0
        divsl.l d1,d2:d0
        lea (0,a2,d2.l),a0
        move.l a0,(a5)+
        lea (0,a2,d0.l),a0
        move.l a0,(a5)+
| 5.1f divu.l -> full-format pea
        move.l #100,d0
        divu.l d1,d0
        pea (0x1000.l,d0.l)
        move.l (a7)+,(a5)+
| 5.2 divs.w -> full pea (.l index = rem:quot, .w index = quot)
        move.l #100,d3
        divs.w #7,d3
        pea (0x1000.l,d3.l)
        move.l (a7)+,(a5)+
        move.l #100,d3
        divs.w #7,d3
        pea (0x1000.l,d3.w)
        move.l (a7)+,(a5)+
| 5.3 muls.l -> brief lea, and -> full pea
        lea 0x3000,a2
        moveq #6,d0
        muls.l #8,d0
        lea (4,a2,d0.l),a0
        move.l a0,(a5)+
        moveq #6,d0
        muls.l #8,d0
        pea (0x1000.l,d0.l)
        move.l (a7)+,(a5)+
| 5.4 bfextu -> indexed lea; bfffo -> indexed lea
        lea 0x4000,a2
        move.l #0x00ff0000,d0
        bfextu d0{8:8},d1
        lea (0,a2,d1.l),a0
        move.l a0,(a5)+
        bfffo d0{0:32},d1
        lea (0,a2,d1.l),a0
        move.l a0,(a5)+
        bfextu d0{8:8},d1
        pea (0x1000.l,d1.l)
        move.l (a7)+,(a5)+
        addq.l #1,d7
        cmp.l #2,d7
        beq done
        move.l #0x0101,d0
        movec d0,cacr
        bra pass
done:   move.l #0x600dc0de,0x3300
h:      bra.s h
