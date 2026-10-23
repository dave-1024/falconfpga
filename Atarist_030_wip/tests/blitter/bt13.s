| BT13.PRG - TODO 9: where does TOS console output hang with blitter on?
| Stage colour (colour 0): S0 red, S1 blue (after Blitmode(1)), S2 yellow/magenta per line
| (IPL7, Bconout(2)), S3 cyan/white per line (IPL restored, Cconws), end grey.
        .text
        .equ    C0,0xffff8240
        clr.l   -(%sp)
        move.w  #0x20,-(%sp)
        trap    #1
        addq.l  #6,%sp
        move.w  #0x700,C0.w
        lea     m_s0(%pc),%a0
        bsr     cws
        bsr     dly
        move.w  #1,-(%sp)
        move.w  #64,-(%sp)
        trap    #14                     | Blitmode(1)
        addq.l  #4,%sp
        move.w  #0x007,C0.w
        bsr     dly
        move.w  %sr,-(%sp)
        or.w    #0x0700,%sr
        moveq   #1,%d7
2:      move.w  #0x770,%d0
        btst    #0,%d7
        beq.s   1f
        move.w  #0x707,%d0
1:      move.w  %d0,C0.w
        lea     line(%pc),%a0
        move.b  #'2',1(%a0)
        bsr     fmt
        lea     line(%pc),%a3
3:      moveq   #0,%d0
        move.b  (%a3)+,%d0
        beq.s   4f
        move.l  %a3,-(%sp)
        move.w  %d0,-(%sp)
        move.w  #2,-(%sp)
        move.w  #3,-(%sp)
        trap    #13
        addq.l  #6,%sp
        move.l  (%sp)+,%a3
        bra.s   3b
4:      addq.w  #1,%d7
        cmp.w   #30,%d7
        bls.s   2b
        move.w  (%sp)+,%sr
        moveq   #1,%d7
5:      move.w  #0x077,%d0
        btst    #0,%d7
        beq.s   6f
        move.w  #0x777,%d0
6:      move.w  %d0,C0.w
        lea     line(%pc),%a0
        move.b  #'3',1(%a0)
        bsr     fmt
        lea     line(%pc),%a0
        bsr     cws
        addq.w  #1,%d7
        cmp.w   #30,%d7
        bls.s   5b
        move.w  #0x555,C0.w
        clr.w   -(%sp)
        move.w  #64,-(%sp)
        trap    #14
        addq.l  #4,%sp
        lea     m_end(%pc),%a0
        bsr     cws
        move.l  0x4ba.w,%d0
        add.l   #3000,%d0
7:      cmp.l   0x4ba.w,%d0
        bhi.s   7b
        move.w  #0x777,C0.w
        clr.w   -(%sp)
        trap    #1
dly:    move.l  #400000,%d0
8:      subq.l  #1,%d0
        bne.s   8b
        rts
fmt:    lea     line+7(%pc),%a0
        move.w  %d7,%d0
        moveq   #2,%d2
9:      ext.l   %d0
        divu    #10,%d0
        swap    %d0
        add.b   #'0',%d0
        move.b  %d0,-(%a0)
        swap    %d0
        dbra    %d2,9b
        rts
cws:    movem.l %d0-%d2/%a0-%a2,-(%sp)
        move.l  %a0,-(%sp)
        move.w  #9,-(%sp)
        trap    #1
        addq.l  #6,%sp
        movem.l (%sp)+,%d0-%d2/%a0-%a2
        rts
line:   .asciz  "S2 L000 the quick brown fox\r\n"
m_s0:   .asciz  "\r\nBT13 S0 blitter off, text OK\r\n"
m_end:  .asciz  "BT13 DONE\r\n"
