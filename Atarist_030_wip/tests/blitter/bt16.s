| BT16.PRG - TODO 9: VT52 scroll blit with the restart loop executed from TOS ROM ($E06670).
| Border colour 0 = stage: red A RAM loop x50, blue B ROM loop x50 (cache as found),
| yellow C ROM loop x50 (CACR=0), white = done. IPL7 throughout. A hang shows the stage colour.
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
        lea     cacr0(%pc),%a0
        move.l  %d0,(%a0)
        move.w  #1,-(%sp)
        move.w  #64,-(%sp)
        trap    #14
        addq.l  #4,%sp
        lea     ret(%pc),%a0            | fake line-A var block: a4@(140) -> back
        lea     fake(%pc),%a4
        move.l  %a0,140(%a4)
        move.w  %sr,-(%sp)
        or.w    #0x0700,%sr
        move.w  #0x700,C0.w
        moveq   #49,%d7
1:      bsr     setup
2:      tas     (%a5)
        nop
        bmi.s   2b
        dbra    %d7,1b
        move.w  #0x007,C0.w
        moveq   #49,%d7
3:      bsr     setup
        move.l  #0xe06670,%a0
        jmp     (%a0)                   | ROM: move.w d2,(a5); tas; nop; bmi; ... jmp a4@(140)
ret:    lea     fake(%pc),%a4
        dbra    %d7,3b
        move.w  #0x770,C0.w
        move.l  #0x0808,%d0
        movec   %d0,%cacr
        moveq   #49,%d7
4:      bsr     setup
        move.l  #0xe06670,%a0
        lea     ret2(%pc),%a1
        lea     fake(%pc),%a4
        move.l  %a1,140(%a4)
        jmp     (%a0)
ret2:   lea     fake(%pc),%a4
        dbra    %d7,4b
        move.l  cacr0(%pc),%d0
        movec   %d0,%cacr
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
5:      cmp.l   0x4ba.w,%d0
        bhi.s   5b
        clr.w   -(%sp)
        trap    #1
| setup: scroll regs as TOS, leaves a5=$FF8A3C, d2=$8000; for RAM case also starts it
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
        move.w  #0x8000,%d2
        move.w  %d2,(%a5)
        rts
cws:    movem.l %d0-%d2/%a0-%a2,-(%sp)
        move.l  %a0,-(%sp)
        move.w  #9,-(%sp)
        trap    #1
        addq.l  #6,%sp
        movem.l (%sp)+,%d0-%d2/%a0-%a2
        rts
m_start: .asciz "\r\nBT16 scroll restart loop from ROM. border: red RAM, blue ROM, yellow ROM nocache\r\n"
m_end:  .asciz  "BT16 DONE all 3 stages OK\r\n"
        .even
cacr0:  .long   0
        .space  64
fake:   .space  160
