| BT12.PRG - TODO 9: real TOS console scroll with blitter on.
| Part 1: Blitmode(1), 100 numbered lines via Cconws (interrupts live).
| Part 2: same, SR IPL 7, each char via BIOS Bconout(2) (VT52 path, no interrupts).
| Heartbeat: line number digits + CR LF to MFP USART UDR directly (polled, timeout),
| plus colour 0 register cycled per line.
        .text
        .equ    UDR,0xfffffa2f
        .equ    TSR,0xfffffa2d
        clr.l   -(%sp)
        move.w  #0x20,-(%sp)
        trap    #1                      | Super
        addq.l  #6,%sp
        move.w  #1,-(%sp)
        move.w  #64,-(%sp)
        trap    #14                     | Blitmode(1)
        addq.l  #4,%sp
        lea     m_p1(%pc),%a0
        bsr     cws
        moveq   #1,%d7
1:      lea     line(%pc),%a0
        move.b  #'1',1(%a0)
        bsr     fmt
        bsr     hb
        lea     line(%pc),%a0
        bsr     cws
        addq.w  #1,%d7
        cmp.w   #100,%d7
        bls.s   1b
        lea     m_p2(%pc),%a0
        bsr     cws
        move.w  %sr,-(%sp)
        or.w    #0x0700,%sr             | IPL 7
        moveq   #1,%d7
2:      lea     line(%pc),%a0
        move.b  #'2',1(%a0)
        bsr     fmt
        bsr     hb
        lea     line(%pc),%a3
3:      moveq   #0,%d0
        move.b  (%a3)+,%d0
        beq.s   4f
        move.l  %a3,-(%sp)
        move.w  %d0,-(%sp)
        move.w  #2,-(%sp)
        move.w  #3,-(%sp)
        trap    #13                     | Bconout(CON)
        addq.l  #6,%sp
        move.l  (%sp)+,%a3
        bra.s   3b
4:      addq.w  #1,%d7
        cmp.w   #100,%d7
        bls.s   2b
        move.w  (%sp)+,%sr
        clr.w   -(%sp)
        move.w  #64,-(%sp)
        trap    #14                     | Blitmode(0)
        addq.l  #4,%sp
        lea     m_end(%pc),%a0
        bsr     cws
        move.l  0x4ba.w,%d0
        add.l   #3000,%d0
5:      cmp.l   0x4ba.w,%d0
        bhi.s   5b
        clr.w   -(%sp)
        trap    #1
| fmt: d7 -> 3 decimal digits at line+4
fmt:    lea     line+7(%pc),%a0
        move.w  %d7,%d0
        moveq   #2,%d2
6:      ext.l   %d0
        divu    #10,%d0
        swap    %d0
        add.b   #'0',%d0
        move.b  %d0,-(%a0)
        swap    %d0
        dbra    %d2,6b
        rts
| hb: colour 0 cycle + "Pn Lnnn\r\n" to UDR
hb:     move.w  %d7,%d0
        and.w   #7,%d0
        add.w   %d0,%d0
        move.w  hcol(%pc,%d0.w),0xffff8240.w
        lea     line(%pc),%a2
        moveq   #6,%d3
7:      move.b  (%a2)+,%d0
        bsr     tx
        dbra    %d3,7b
        moveq   #13,%d0
        bsr     tx
        moveq   #10,%d0
        bra     tx
hcol:   .word   0x777,0x770,0x707,0x077,0x775,0x757,0x577,0x666
tx:     move.l  #20000,%d1
8:      btst    #7,TSR.w
        bne.s   9f
        subq.l  #1,%d1
        bne.s   8b
9:      move.b  %d0,UDR.w
        rts
cws:    movem.l %d0-%d2/%a0-%a2,-(%sp)
        move.l  %a0,-(%sp)
        move.w  #9,-(%sp)
        trap    #1
        addq.l  #6,%sp
        movem.l (%sp)+,%d0-%d2/%a0-%a2
        rts
line:   .asciz  "P1 L000 the quick brown fox jumps over the lazy dog 0123456789\r\n"
m_p1:   .asciz  "\r\nBT12 part 1: Blitmode(1), Cconws x100, IRQs on\r\n"
m_p2:   .asciz  "BT12 part 2: IPL7, Bconout(2) x100\r\n"
m_end:  .asciz  "BT12 DONE. Blitmode(0). exit in 5 s.\r\n"
