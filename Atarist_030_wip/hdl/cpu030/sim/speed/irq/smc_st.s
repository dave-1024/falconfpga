| smc: load code into cacheable RAM ($8000), run it, load other code there, flush the I-cache (CACR CI), run again.
        .org 0
        dc.l    0x2000, start
start:  move.w  #0x2700,%sr
        lea     0x1000,%sp
        move.l  #0x0919,%d0      | I+D cache on, clear both
        movec   %d0,%cacr
        moveq   #0,%d7
        moveq   #9,%d6
again:  lea     0x8000,%a0
        lea     codeA(%pc),%a1
        move.w  #(codeAe-codeA)/2-1,%d0
1:      move.w  (%a1)+,(%a0)+
        dbf     %d0,1b
        move.l  #0x0919,%d0
        movec   %d0,%cacr
        jsr     0x8000
        add.l   %d1,%d7
        lea     0x8000,%a0
        lea     codeB(%pc),%a1
        move.w  #(codeBe-codeB)/2-1,%d0
1:      move.w  (%a1)+,(%a0)+
        dbf     %d0,1b
        move.l  #0x0919,%d0
        movec   %d0,%cacr
        jsr     0x8000
        add.l   %d1,%d7
        rol.l   #3,%d7
        dbf     %d6,again
        move.l  %d7,0x3300
1:      bra.s   1b
codeA:  moveq   #1,%d1
        moveq   #20,%d2
2:      add.l   %d1,%d1
        addq.l  #3,%d1
        subq.l  #1,%d2
        bne.s   2b
        rts
codeAe:
codeB:  move.l  #0x55,%d1
        moveq   #11,%d2
2:      eor.l   %d2,%d1
        lsl.l   #1,%d1
        dbf     %d2,2b
        nop
        nop
        rts
codeBe:
