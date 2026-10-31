| [SL1] MiNT xaaes env loop with the PMMU on: d0 = dest ptr; jsr strlen (other page, ends move.l a0,d0; rts);
| lea (1,a2,d0.l),a2. Results (a2 - buf, expect 6) as words from $5000. Variants flush the ATC (pflusha) before.
        .text
        .org 0
        .long   0x00008000
        .long   0x00fc0008
start:
        lea     0x5000,a4
        lea     0x6000,a0
        moveq   #15,d0
1:      clr.l   (a0)+
        dbf     d0,1b
        move.l  #0x00006102,0x6000
        move.l  #0x00f00001,0x603c
        lea     0x6100,a0
        move.l  #255,d0
        moveq   #1,d1
2:      move.l  d1,(a0)+
        add.l   #0x1000,d1
        dbf     d0,2b
        move.l  #0x7fff0002,0x4000
        move.l  #0x00006000,0x4004
        pmove   0x4000,crp
        move.l  #0x80c84800,0x4008
        move.l  #0,0x400c
| copy strlen to $3000 (own page)
        lea     sl(%pc),a0
        lea     0x3000,a1
        moveq   #15,d0
3:      move.w  (a0)+,(a1)+
        dbf     d0,3b
        move.l  #0x68656c6c,0x2000      | "hell"
        move.l  #0x6f000000,0x2004      | "o\0"
        clr.l   0x2008
        pmove   0x4008,tc
        moveq   #11,d6
lp:     btst    #0,d6
        beq.s   4f
        pflusha
4:      btst    #1,d6
        beq.s   5f
        movec   cacr,d0
        or.w    #0x0808,d0
        movec   d0,cacr
5:      lea     0x2000,a2
        btst    #2,d6
        beq.s   6f
        lea     0x2006,a2               | empty string (byte $00 at $2006... see below)
6:
        move.l  a2,d0
        pea     (a2)
        lea     0x3000,a0
        jsr     (a0)
        lea     (1,a2,d0.l),a2
        addq.l  #4,sp
        sub.l   #0x2000,a2
        move.w  a2,(a4)+
        dbf     d6,lp
        pmove   0x400c,tc
        move.l  #0x600dc0de,0x3300
h:      bra.s   h
sl:     move.l  (4,sp),a0
        addq.l  #1,a0
        move.l  a0,d0
        tst.b   (-1,a0)
        beq.s   s2
s1:     addq.l  #1,a0
        tst.b   (-1,a0)
        bne.s   s1
s2:     suba.l  d0,a0
        move.l  a0,d0
        rts
