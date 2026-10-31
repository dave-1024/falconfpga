| EATEST.PRG: test full-format EA "movea.l (bd.l,Dn.l),An" (base suppressed) as in MiNT text+19c22
        .text
        pea     sup(%pc)
        move.w  #38,-(%sp)
        trap    #14
        addq.l  #6,%sp
        lea     out(%pc),%a5
        pea     (%a5)
        move.w  #9,-(%sp)
        trap    #1
        addq.l  #6,%sp
        move.w  #7,-(%sp)
        trap    #1
        addq.l  #2,%sp
        clr.w   -(%sp)
        trap    #1
sup:    lea     tbl(%pc),%a1
        lea     p1+4(%pc),%a2
        move.l  %a1,(%a2)       | patch bd = &tbl
        lea     p2+4(%pc),%a2
        move.l  %a1,(%a2)
        movec   %cacr,%d0
        or.w    #0x0808,%d0     | clear I and D cache
        movec   %d0,%cacr
        lea     ptr5(%pc),%a2
        move.l  %a2,120(%a1)
        lea     val5(%pc),%a3
        move.l  %a3,(%a2)
        lea     out(%pc),%a5
        moveq   #0,%d7          | fail count
        moveq   #0,%d6          | index
loop:   moveq   #0,%d1
        move.w  %d6,%d1
        move.l  %d1,%d0
        add.l   %d0,%d0
        add.l   %d1,%d0
        lsl.l   #3,%d0          | d0 = idx*24
p1:     .short  0x2070,0x09b0
        .long   0               | movea.l (bd.l,d0.l),a0
        move.l  %a0,%d4         | full-format result
        move.l  %d0,%d2         | idx*24 from add/add/lsl
        move.l  %a1,%a3
        adda.l  %d2,%a3
        move.l  (%a3),%d3       | expected via plain (An)
        move.l  (0,%a1,%d2.l),%a4  | brief-format
        move.b  #'I',(%a5)+
        move.l  %d6,%d0
        bsr     hex8
        move.b  #' ',(%a5)+
        move.l  %d2,%d0
        bsr     hex8
        move.b  #' ',(%a5)+
        move.l  %d4,%d0
        bsr     hex8
        move.b  #' ',(%a5)+
        move.l  %a4,%d0
        bsr     hex8
        move.b  #' ',(%a5)+
        move.l  %d3,%d0
        bsr     hex8
        move.b  #13,(%a5)+
        move.b  #10,(%a5)+
        cmp.l   %d4,%d3
        beq     ok1
        addq.l  #1,%d7
ok1:    addq.w  #1,%d6
        cmp.w   #8,%d6
        bne     loop
| variant 2: same insn immediately after lsl, then movea.l (a0),a0 (kernel sequence) repeated 1000x
        move.w  #999,%d5
v2:     moveq   #5,%d1
        move.l  %d1,%d0
        add.l   %d0,%d0
        add.l   %d1,%d0
        lsl.l   #3,%d0
p2:     .short  0x2070,0x09b0
        .long   0
        movea.l (%a0),%a0
        lea     val5(%pc),%a2
        cmp.l   %a0,%a2
        beq     ok2
        addq.l  #1,%d7
ok2:    dbra    %d5,v2
        move.b  #'E',(%a5)+
        move.b  #'A',(%a5)+
        move.b  #' ',(%a5)+
        move.l  %d7,%d0
        bsr     hex8
        tst.l   %d7
        bne     bad
        lea     okm(%pc),%a0
        bra     cp
bad:    lea     badm(%pc),%a0
cp:     move.b  (%a0)+,(%a5)+
        bne     cp
        rts
hex8:   movem.l %d0-%d3,-(%sp)
        moveq   #7,%d3
h1:     rol.l   #4,%d0
        move.b  %d0,%d1
        and.b   #15,%d1
        add.b   #'0',%d1
        cmp.b   #'9',%d1
        bls     h2
        addq.b  #7,%d1
h2:     move.b  %d1,(%a5)+
        dbra    %d3,h1
        movem.l (%sp)+,%d0-%d3
        rts
okm:    .asciz  " EATEST PASS\r\n"
badm:   .asciz  " EATEST FAIL\r\n"
        .even
tbl:    .long   0x11111100,0,0,0,0,0
        .long   0x22222200,0,0,0,0,0
        .long   0x33333300,0,0,0,0,0
        .long   0x44444400,0,0,0,0,0
        .long   0x55555500,0,0,0,0,0
        .long   0x66666600,0,0,0,0,0
        .long   0x77777700,0,0,0,0,0
        .long   0x88888800,0,0,0,0,0
ptr5:   .long   0
val5:   .long   0
out:    .space  512
