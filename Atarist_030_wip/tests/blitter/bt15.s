| BT15.PRG - TODO 9: TOS console sequence back to back at IPL7:
| per iteration: 2 HOG font blits (ROM src, ctrl $C008/$C000, tst/bmi poll), then
| the VT52 scroll (non-HOG, tas restart), then 2 plane clears (OP0 via scs, tas restart).
| Each wait has a timeout. Stops at the first timeout; prints iteration, step after Blitmode(0).
        .text
        .equ    BLT,0xffff8a00
        clr.l   -(%sp)
        move.w  #0x20,-(%sp)
        trap    #1
        addq.l  #6,%sp
        lea     m_start(%pc),%a0
        bsr     cws
        move.w  #3,-(%sp)
        trap    #14
        addq.l  #2,%sp
        move.l  %d0,%d6                 | d6 = screen
        move.w  #1,-(%sp)
        move.w  #64,-(%sp)
        trap    #14
        addq.l  #4,%sp
        move.w  %sr,-(%sp)
        or.w    #0x0700,%sr
        lea     BLT+0x3c,%a5
        moveq   #0,%d7                  | iteration
10:     moveq   #1,%d3                  | step 1/2 font
        move.l  #0xe20000,%a0
        move.l  %d6,%a1
        add.l   #24*1280+40,%a1
        bsr     font
        bne     90f
        moveq   #2,%d3
        move.l  #0xe20101,%a0
        addq.l  #2,%a1
        bsr     font
        bne     90f
        moveq   #3,%d3                  | step 3 scroll
        bsr     scroll
        bne.s   90f
        moveq   #4,%d3
        move.l  %d6,%a1
        add.l   #24*1280,%a1
        bsr     clear
        bne.s   90f
        moveq   #5,%d3
        addq.l  #2,%a1
        bsr     clear
        bne.s   90f
        addq.w  #1,%d7
        cmp.w   #300,%d7
        blo     10b
        moveq   #0,%d3
90:     move.w  (%sp)+,%sr
        lea     res(%pc),%a0
        move.w  %d7,(%a0)+
        move.w  %d3,(%a0)+
        move.w  0x38-0x3c(%a5),(%a0)+
        move.w  0x36-0x3c(%a5),(%a0)+
        move.w  (%a5),(%a0)+
        clr.w   -(%sp)
        move.w  #64,-(%sp)
        trap    #14
        addq.l  #4,%sp
        lea     m_r(%pc),%a0
        bsr     cws
        lea     res(%pc),%a3
        moveq   #4,%d4
11:     move.w  (%a3)+,%d0
        bsr     hexw
        dbra    %d4,11b
        lea     m_end(%pc),%a0
        bsr     cws
        move.l  0x4ba.w,%d0
        add.l   #3000,%d0
12:     cmp.l   0x4ba.w,%d0
        bhi.s   12b
        clr.w   -(%sp)
        trap    #1
| font: a0 src, a1 dst. like TOS $E06594..$E065FC, 1 plane. Z set = ok
font:   move.w  #1,-6(%a5)              | xcount
        clr.w   -28(%a5)                | src x inc
        move.w  #256,-26(%a5)           | src y inc
        move.w  #0xff00,-20(%a5)        | endmask1
        move.w  #160,-12(%a5)           | dst y inc
        move.l  %a0,-24(%a5)
        move.l  %a1,-10(%a5)
        move.w  #8,-4(%a5)              | ycount
        move.w  #0x0203,-2(%a5)
        move.w  #0xc008,%d0
        btst    #0,%d3
        bne.s   1f
        move.w  #0xc000,%d0
1:      move.w  %d0,(%a5)
        move.l  #300000,%d5
2:      tst.w   (%a5)
        bpl.s   3f
        subq.l  #1,%d5
        bne.s   2b
        clr.w   (%a5)
        moveq   #1,%d0
        rts
3:      moveq   #0,%d0
        rts
| scroll: exactly TOS $E06628..$E06676 order, src = screen+$500 (medium 8 lines*160)
scroll: lea     BLT+0x20,%a2
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
        move.w  #0x8000,(%a2)
        bra.s   tasw
| clear: like TOS $E06708..$E0678E one plane: endmasks, dst x inc 4, dst y inc, dst, xcount, ycount
clear:  lea     BLT+0x28,%a2
        moveq   #-1,%d1
        move.w  %d1,(%a2)+
        move.w  %d1,(%a2)+
        move.w  %d1,(%a2)+
        move.w  #4,(%a2)+
        move.w  #4,(%a2)+
        move.l  %a1,(%a2)+
        move.w  #40,(%a2)+
        move.w  #8,(%a2)
        or.b    #1,%ccr                 | C set -> scs gives $FF? TOS: lsr colour; use 0
        and.b   #0xfe,%ccr
        scs     -1(%a5)
        move.w  #0x8000,(%a5)
tasw:   move.l  #3000000,%d5
4:      tas     (%a5)
        nop
        bpl.s   5f
        subq.l  #1,%d5
        bne.s   4b
        clr.w   (%a5)
        moveq   #1,%d0
        rts
5:      moveq   #0,%d0
        rts
hexw:   movem.l %d0-%d2/%a0,-(%sp)
        lea     hbuf+5(%pc),%a0
        moveq   #3,%d2
16:     move.w  %d0,%d1
        and.w   #15,%d1
        move.b  hdig(%pc,%d1.w),-(%a0)
        lsr.w   #4,%d0
        dbra    %d2,16b
        lea     hbuf(%pc),%a0
        bsr     cws
        movem.l (%sp)+,%d0-%d2/%a0
        rts
cws:    movem.l %d0-%d2/%a0-%a2,-(%sp)
        move.l  %a0,-(%sp)
        move.w  #9,-(%sp)
        trap    #1
        addq.l  #6,%sp
        movem.l (%sp)+,%d0-%d2/%a0-%a2
        rts
hdig:   .ascii  "0123456789ABCDEF"
hbuf:   .asciz  "$0000\r\n"
m_start: .asciz "\r\nBT15 font+scroll+clear back to back x300, IPL7\r\n"
m_r:    .asciz  "\r\niter step(0=all ok) ycnt xcnt ctrl: "
m_end:  .asciz  "\r\nDone, exit 15 s.\r\n"
        .even
res:    .space  10
