| BT18.PRG - TODO 9: which ROM access kills the restart loop? Restart loop in RAM, IPL7, scroll x50 per stage.
| Border (colour 0) = stage: red S1 tst.l $E00000 (long data read from ROM) caches off,
| blue S2 jsr $E06600 (ROM rts: opcode fetch from ROM) caches off, yellow S3 S2 with CACR as found,
| magenta S4 tst.l $E00002 (misaligned-to-long ROM read) caches off. White = all OK.
        .text
        .equ    BLT,0xffff8a00
        .equ    C0,0xffff8240
        clr.l   -(%sp)
        move.w  #0x20,-(%sp)
        trap    #1
        addq.l  #6,%sp
        lea     m_start(%pc),%a0
        bsr     cws
        move.w  #3,-(%sp)
        trap    #14
        addq.l  #2,%sp
        move.l  %d0,%d6
        movec   %cacr,%d0
        move.l  %d0,%d4
        move.w  #1,-(%sp)
        move.w  #64,-(%sp)
        trap    #14
        addq.l  #4,%sp
        move.w  %sr,-(%sp)
        or.w    #0x0700,%sr
        move.l  #0x0808,%d0
        movec   %d0,%cacr
        move.l  #0xe00000,%a4
        move.w  #0x700,C0.w
        moveq   #49,%d7
1:      bsr     setup
2:      tst.l   (%a4)
        tas     (%a5)
        nop
        bmi.s   2b
        dbra    %d7,1b
        move.w  #0x007,C0.w
        move.l  #0xe06600,%a3
        moveq   #49,%d7
3:      bsr     setup
4:      jsr     (%a3)
        tas     (%a5)
        nop
        bmi.s   4b
        dbra    %d7,3b
        move.w  #0x770,C0.w
        movec   %d4,%cacr
        moveq   #49,%d7
5:      bsr     setup
6:      jsr     (%a3)
        tas     (%a5)
        nop
        bmi.s   6b
        dbra    %d7,5b
        move.w  #0x707,C0.w
        move.l  #0x0808,%d0
        movec   %d0,%cacr
        addq.l  #2,%a4
        moveq   #49,%d7
7:      bsr     setup
8:      tst.l   (%a4)
        tas     (%a5)
        nop
        bmi.s   8b
        dbra    %d7,7b
        movec   %d4,%cacr
        move.w  #0x777,C0.w
        move.w  (%sp)+,%sr
        clr.w   -(%sp)
        move.w  #64,-(%sp)
        trap    #14
        addq.l  #4,%sp
        lea     m_end(%pc),%a0
        bsr     cws
        move.l  0x4ba.w,%d0
        add.l   #3000,%d0
9:      cmp.l   0x4ba.w,%d0
        bhi.s   9b
        clr.w   -(%sp)
        trap    #1
setup:  lea     BLT+0x20,%a2
        moveq   #2,%d0
        move.w  %d0,(%a2)+
        move.w  %d0,(%a2)+
        move.l  %d6,%d1
        add.l   #0x500,%d1
        move.l  %d1,(%a2)+
        moveq   #-1,%d1
        move.l  %d1,(%a2)+
        move.w  %d1,(%a2)+
        move.w  %d0,(%a2)+
        move.w  %d0,(%a2)+
        move.l  %d6,(%a2)+
        move.w  #0x280,(%a2)+
        move.w  #24,(%a2)+
        move.w  #0x0203,(%a2)+
        move.l  %a2,%a5
        move.w  #0x8000,(%a5)
        rts
cws:    movem.l %d0-%d2/%a0-%a2,-(%sp)
        move.l  %a0,-(%sp)
        move.w  #9,-(%sp)
        trap    #1
        addq.l  #6,%sp
        movem.l (%sp)+,%d0-%d2/%a0-%a2
        rts
m_start: .asciz "\r\nBT18 border: red tst.l ROM, blue jsr ROM rts, yellow same+cache, magenta tst.l ROM+2\r\n"
m_end:  .asciz  "BT18 DONE all 4 stages OK\r\n"
