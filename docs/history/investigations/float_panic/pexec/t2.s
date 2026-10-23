| Pexec(5)+Pexec(4) child that trashes D3-D7/A3-A6 and Pterm()s; check the parent's regs survive.
        .text
start:  move.l  #0x5157ab1e,d0
        movea.l 4(sp),a0
        lea     stk_end(pc),sp
        move.l  #0x10000,-(sp)          | Mshrink(self, 64K)
        move.l  a0,-(sp)
        clr.w   -(sp)
        move.w  #0x4a,-(sp)
        trap    #1
        lea     12(sp),sp
        clr.l   -(sp)                   | Pexec(5, NULL, "", NULL)
        pea     nul(pc)
        clr.l   -(sp)
        move.w  #5,-(sp)
        move.w  #0x4b,-(sp)
        trap    #1
        lea     16(sp),sp
        movea.l d0,a0
        lea     256(a0),a1
        move.l  a1,8(a0)                | p_tbase
        lea     child(pc),a2
        moveq   #(child_end-child)/2-1,d1
cp:     move.w  (a2)+,(a1)+
        dbra    d1,cp
        move.l  #0x33333333,d3
        move.l  #0x44444444,d4
        move.l  #0x55555555,d5
        move.l  #0x66666666,d6
        move.l  #0x77777777,d7
        lea     0x3a3a0,a3
        lea     0x4a4a0,a4
        lea     0x5a5a0,a5
        lea     0x6a6a0,a6
        clr.l   -(sp)                   | Pexec(4, NULL, bp, NULL)
        move.l  a0,-(sp)
        clr.l   -(sp)
        move.w  #4,-(sp)
        move.w  #0x4b,-(sp)
        trap    #1
here:   lea     16(sp),sp
        moveq   #1,d1
        cmpa.l  #0x5a5a0,a5
        bne.s   bad
        moveq   #2,d1
        cmpa.l  #0x4a4a0,a4
        bne.s   bad
        moveq   #3,d1
        cmpa.l  #0x3a3a0,a3
        bne.s   bad
        moveq   #4,d1
        cmpa.l  #0x6a6a0,a6
        bne.s   bad
        moveq   #5,d1
        cmp.l   #0x33333333,d3
        bne.s   bad
        cmp.l   #0x77777777,d7
        bne.s   bad
        moveq   #6,d1
        lea     stk_end(pc),a0
        cmpa.l  a0,sp
        bne.s   bad
        move.l  #0x600dc0de,d1
        bra.s   fin
bad:    ori.l   #0xbad00000,d1
fin:    move.l  #0xf1f1f1f1,d2
        lea     res(pc),a0
        move.l  d1,(a0)
self:   bra.s   self
child:  move.l  #0x13579bdf,d3
        move.l  d3,d4
        move.l  d3,d5
        move.l  d3,d6
        move.l  d3,d7
        clr.l   -(sp)
        move.w  #0x20,-(sp)
        trap    #1
        move.l  d0,2(sp)
        move.w  #0x20,(sp)
        trap    #1
        addq.l  #6,sp
        lea     0x55718,a5
        lea     0x58d78,a4
        movea.l a4,a3
        movea.l a4,a6
        move.w  #0,-(sp)
        move.w  #0x4c,-(sp)
        trap    #1
child_end:
nul:    .word   0
res:    .long   0

        .space  2048
stk_end:
