| F62d regression: an instruction that writes A7 through the ALU writeback (ADDA, SUBA,
| ADDQ/SUBQ, LEA d(SP),SP, MOVEA) directly followed by one that pushes (JSR in all modes, BSR,
| PEA, MOVE -(SP)), also with the pair at an RTE/RTS/BRA target (prefetch queue refill; case 13
| is the TOS 2.06 AES Pexec wrapper, E21C0C ADDA.W #16,SP / E21C10 JSR). The SP seen after the
| push must be the expected one. DONE writes $600DC0DE, or $BAD0nnnn (nnnn = case) on a failure.
        .text
        .org 0
        .long   0x00008000
        .long   0x00fc0008
start:
        lea     0x7000,sp
        lea     sub(pc),a0
        moveq   #0,d0
        moveq   #3,d6
        moveq   #0,d5
loop:
        movea.l sp,a2
        | 1 adda.w + jsr (d16,pc)
        addq.w  #1,d5
        suba.w  #16,sp
        adda.w  #16,sp
        jsr     sub(pc)
        bsr     chk0
        | 2 adda.w + jsr abs.l
        addq.w  #1,d5
        suba.w  #16,sp
        adda.w  #16,sp
        jsr     sub
        bsr     chk0
        | 3 adda.w + jsr (d16,a0)
        addq.w  #1,d5
        suba.w  #16,sp
        adda.w  #16,sp
        jsr     0(a0)
        bsr     chk0
        | 4 adda.w + jsr (d8,a0,d0)
        addq.w  #1,d5
        suba.w  #16,sp
        adda.w  #16,sp
        jsr     0(a0,d0.w)
        bsr     chk0
        | 5 adda.w + jsr (a0)
        addq.w  #1,d5
        suba.w  #16,sp
        adda.w  #16,sp
        jsr     (a0)
        bsr     chk0
        | 6 addq.l + jsr (d16,pc)
        addq.w  #1,d5
        subq.l  #8,sp
        addq.l  #8,sp
        jsr     sub(pc)
        bsr     chk0
        | 7 lea + jsr abs.l
        addq.w  #1,d5
        lea     -12(sp),sp
        lea     12(sp),sp
        jsr     sub
        bsr     chk0
        | 8 adda + bsr
        addq.w  #1,d5
        suba.w  #16,sp
        adda.w  #16,sp
        bsr     sub
        bsr     chk0
        | 9 adda + pea (d16,pc) ; pop
        addq.w  #1,d5
        suba.w  #16,sp
        adda.w  #16,sp
        pea     sub(pc)
        move.l  sp,d1
        addq.l  #4,sp
        bsr     chk0
        | 10 adda + pea abs.l
        addq.w  #1,d5
        suba.w  #16,sp
        adda.w  #16,sp
        pea     0x1234
        move.l  sp,d1
        addq.l  #4,sp
        bsr     chk0
        | 11 adda + move.l d0,-(sp)
        addq.w  #1,d5
        suba.w  #16,sp
        adda.w  #16,sp
        move.l  d0,-(sp)
        move.l  sp,d1
        addq.l  #4,sp
        bsr     chk0
        | 12 movea.l + jsr (d16,pc)
        addq.w  #1,d5
        movea.l a2,a3
        lea     -20(a3),sp
        movea.l a3,sp
        jsr     sub(pc)
        bsr     chk0
        | 13 rte lands on adda + jsr (d16,pc)
        addq.w  #1,d5
        suba.w  #16,sp
        clr.w   -(sp)
        pea     r13(pc)
        move.w  sr,-(sp)
        rte
r13:    adda.w  #16,sp
        jsr     sub(pc)
        bsr     chk0
        | 14 rts lands on adda + jsr abs.l
        addq.w  #1,d5
        suba.w  #16,sp
        pea     r14(pc)
        rts
r14:    adda.w  #16,sp
        jsr     sub
        bsr     chk0
        | 15 bra lands on adda + jsr (d16,a0)
        addq.w  #1,d5
        suba.w  #16,sp
        bra.s   r15
        nop
r15:    adda.w  #16,sp
        jsr     0(a0)
        bsr     chk0
        | 16 rte lands on adda + jsr (d8,a0,d0)
        addq.w  #1,d5
        suba.w  #16,sp
        clr.w   -(sp)
        pea     r16(pc)
        move.w  sr,-(sp)
        rte
r16:    adda.w  #16,sp
        jsr     0(a0,d0.w)
        bsr     chk0
        | 17 rte lands on adda + pea (d16,pc)
        addq.w  #1,d5
        suba.w  #16,sp
        clr.w   -(sp)
        pea     r17(pc)
        move.w  sr,-(sp)
        rte
r17:    adda.w  #16,sp
        pea     sub(pc)
        move.l  sp,d1
        addq.l  #4,sp
        bsr     chk0
        dbra    d6,loop
        move.l  #0x600dc0de,0x3300
self:   bra.s   self

| d1 = SP seen inside sub (or after the push); expected a2-4
chk0:   movea.l a2,a1
        subq.l  #4,a1
        cmpa.l  d1,a1
        bne.s   bad
        rts
bad:    move.l  d5,d7
        ori.l   #0xbad00000,d7
        move.l  d7,0x3300
        bra.s   self
sub:    move.l  sp,d1
        rts
