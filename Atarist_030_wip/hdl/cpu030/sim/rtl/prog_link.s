| LINK/UNLK right after an instruction that writes back A7 or the frame register
| (same hazard class as F62d JSR). DONE writes $600DC0DE at $3300, or $BAD0nnnn (nnnn = case).
        .text
        .org 0
        .long   0x00008000
        .long   0x00fc0008
        .macro  pre
        lea     0x7000,sp
        lea     0x6800,a5
        movea.l a5,a4
        lea     0x7000,a3
        addq.w  #1,d5
        .endm
        .macro  post
        bsr     chkl
        .endm
start:  moveq   #3,d6
loop:   moveq   #0,d5
        pre
        suba.w  #16,sp
        adda.w  #16,sp
        link    a5,#-8
        post
        pre
        subq.l  #4,sp
        addq.l  #4,sp
        link    a5,#-8
        post
        pre
        lea     -16(sp),sp
        lea     16(sp),sp
        link    a5,#-8
        post
        pre
        movea.l a3,sp
        link    a5,#-8
        post
        pre
        move.l  d0,-(sp)
        move.l  (sp)+,d0
        link    a5,#-8
        post
        pre
        movea.l a4,a5
        link    a5,#-8
        post
        pre
        bsr.s   t7
        bra.s   n7
t7:     movea.l (sp)+,a0
        link    a5,#-8
        bsr     chkl
        unlk    a5
        jmp     (a0)
n7:     pre
        link    a5,#-8
        movea.l a5,a1
        movea.l a1,a5
        unlk    a5
        bsr     chku
        pre
        link    a5,#-8
        adda.w  #16,sp
        unlk    a5
        bsr     chku
        pre
        link    a5,#-8
        move.l  (sp)+,d0
        unlk    a5
        bsr     chku
        dbra    d6,loop
        move.l  #0x600dc0de,0x3300
self:   bra.s   self
| after link: a5 = $6FFC, sp = $6FF4 (+4 for return addr of bsr), ($6FFC) = $6800
chkl:   cmpa.l  #0x6ffc,a5
        bne.s   bad
        cmpa.l  #0x6ff0,sp
        bne.s   bad
        cmpi.l  #0x6800,0x6ffc
        bne.s   bad
        rts
chku:   cmpa.l  #0x6800,a5
        bne.s   bad
        cmpa.l  #0x6ffc,sp
        bne.s   bad
        rts
bad:    move.l  d5,d7
        ori.l   #0xbad00000,d7
        move.l  d7,0x3300
        bra.s   self
