| BT14.PRG - TODO 9: VT52 scroll+clear replica on screen; tas loop also reads (a4).
| Cases: A I/D cache as found + a4=RAM, B CACR=0 + RAM, C cache + a4=ROM $E00000, D CACR=0 + ROM.
        .text
        .equ    BLT,0xffff8a00
        clr.l   -(%sp)
        move.w  #0x20,-(%sp)
        trap    #1
        addq.l  #6,%sp
        lea     m_start(%pc),%a0
        bsr     out
        move.w  #3,-(%sp)
        trap    #14
        addq.l  #2,%sp
        lea     scr(%pc),%a0
        move.l  %d0,(%a0)
        movec   %cacr,%d0
        lea     cacr0(%pc),%a0
        move.l  %d0,(%a0)
        move.w  #1,-(%sp)
        move.w  #64,-(%sp)
        trap    #14                     | Blitmode(1)
        addq.l  #4,%sp
        lea     res(%pc),%a3
        moveq   #0,%d7                  | case 0..3
30:     move.l  cacr0(%pc),%d0
        btst    #0,%d7
        beq.s   31f
        move.l  #0x0808,%d0             | clear caches, disable
31:     movec   %d0,%cacr
        lea     ramv(%pc),%a4
        btst    #1,%d7
        beq.s   32f
        move.l  #0xe00000,%a4
32:     move.l  scr(%pc),%d6
        bsr     scroll
        move.l  scr(%pc),%d6
        bsr     clear
        addq.w  #1,%d7
        cmp.w   #4,%d7
        blo.s   30b
        move.l  cacr0(%pc),%d0
        movec   %d0,%cacr
        clr.w   -(%sp)
        move.w  #64,-(%sp)
        trap    #14                     | Blitmode(0)
        addq.l  #4,%sp
        lea     m_c(%pc),%a0
        bsr     out
        move.l  cacr0(%pc),%d0
        swap    %d0
        bsr     hexw
        swap    %d0
        bsr     hexw
        bsr     crlf
        lea     res(%pc),%a3
        moveq   #0,%d7
33:     lea     m_h(%pc),%a0
        bsr     out
        move.w  %d7,%d0
        bsr     hexw
        bsr     crlf
        lea     m_a(%pc),%a0
        bsr     out
        bsr     report
        lea     18(%a3),%a3
        lea     m_b(%pc),%a0
        bsr     out
        bsr     report
        lea     18(%a3),%a3
        addq.w  #1,%d7
        cmp.w   #4,%d7
        blo.s   33b
        lea     m_end(%pc),%a0
        bsr     out
        move.l  0x4ba.w,%d0
        add.l   #3000,%d0
2:      cmp.l   0x4ba.w,%d0
        bhi.s   2b
        clr.w   -(%sp)
        trap    #1
| scroll: d6 = dst. Results to (a3): .l restarts, .w status (0 ok, 1 timeout), .w y, .w x, .l src, .l dst
scroll: lea     BLT,%a2
        lea     0x3c(%a2),%a5
        move.w  #2,0x20(%a2)
        move.w  #2,0x22(%a2)
        move.l  %d6,%d0
        add.l   #0x500,%d0
        move.l  %d0,0x24(%a2)
        move.w  #-1,0x28(%a2)
        move.w  #-1,0x2a(%a2)
        move.w  #-1,0x2c(%a2)
        move.w  #2,0x2e(%a2)
        move.w  #2,0x30(%a2)
        move.l  %d6,0x32(%a2)
        move.w  #0x280,0x36(%a2)
        move.w  #24,0x38(%a2)
        move.w  #0x0203,0x3a(%a2)
        moveq   #0,%d5
        move.l  #3000000,%d4
        move.w  #0x8000,(%a5)
3:      addq.l  #1,%d5
        cmp.l   %d4,%d5
        bhs.s   4f
        tst.w   (%a4)
        tas     (%a5)
        nop
        bmi.s   3b
        move.l  %d5,(%a3)+
        clr.w   (%a3)+
        bra.s   5f
4:      move.l  %d5,(%a3)+
        move.w  #1,(%a3)+
        clr.w   (%a5)                   | stop it
5:      move.w  0x38(%a2),(%a3)+
        move.w  0x36(%a2),(%a3)+
        move.l  0x24(%a2),(%a3)+
        move.l  0x32(%a2),(%a3)+
        rts
| clear: d6 = screen; bottom char row (offset 24*1280), plane 0 then plane 1; results of the last plane
clear:  lea     BLT,%a2
        lea     0x3c(%a2),%a5
        move.w  #-1,0x28(%a2)
        move.w  #-1,0x2a(%a2)
        move.w  #-1,0x2c(%a2)
        move.w  #4,0x2e(%a2)
        move.w  #4,0x30(%a2)
        move.w  #40,0x36(%a2)
        move.l  %d6,%a1
        add.l   #24*1280,%a1
        moveq   #1,%d3
20:     move.l  %a1,0x32(%a2)
        move.w  #8,0x38(%a2)
        clr.b   0x3b(%a2)               | OP 0 (as scs -1(a5) with colour bit 0)
        moveq   #0,%d5
        move.l  #3000000,%d4
        move.w  #0x8000,(%a5)
21:     addq.l  #1,%d5
        cmp.l   %d4,%d5
        bhs.s   22f
        tst.w   (%a4)
        tas     (%a5)
        nop
        bmi.s   21b
        moveq   #0,%d0
        bra.s   23f
22:     clr.w   (%a5)
        moveq   #1,%d0
23:     addq.l  #2,%a1
        tst.w   %d0
        dbne    %d3,20b
        move.l  %d5,(%a3)+
        move.w  %d0,(%a3)+
        move.w  0x38(%a2),(%a3)+
        move.w  0x36(%a2),(%a3)+
        move.l  0x24(%a2),(%a3)+
        move.l  0x32(%a2),(%a3)+
        rts
report: move.w  4(%a3),%d0
        lea     m_ok(%pc),%a0
        beq.s   6f
        lea     m_tmo(%pc),%a0
6:      bsr     out
        lea     m_r(%pc),%a0
        bsr     out
        move.w  (%a3),%d0
        bsr     hexw
        move.w  2(%a3),%d0
        bsr     hexw
        lea     m_y(%pc),%a0
        bsr     out
        move.w  6(%a3),%d0
        bsr     hexw
        lea     m_x(%pc),%a0
        bsr     out
        move.w  8(%a3),%d0
        bsr     hexw
        lea     m_s(%pc),%a0
        bsr     out
        move.w  10(%a3),%d0
        bsr     hexw
        move.w  12(%a3),%d0
        bsr     hexw
        lea     m_d(%pc),%a0
        bsr     out
        move.w  14(%a3),%d0
        bsr     hexw
        move.w  16(%a3),%d0
        bsr     hexw
        bsr     crlf
        rts
| out: print string a0 on screen, then AUX
out:    movem.l %d0-%d2/%a0-%a2,-(%sp)
        move.l  %a0,-(%sp)
        move.l  %a0,-(%sp)
        move.w  #9,-(%sp)
        trap    #1
        addq.l  #6,%sp
        move.l  (%sp)+,%a2
14:     moveq   #0,%d0
        move.b  (%a2)+,%d0
        beq.s   15f
        move.w  %d0,%d2
        lea     auxdrop(%pc),%a0
        tst.w   (%a0)
        beq.s   19f
        addq.w  #1,(%a0)                | AUX already found stuck: drop
        bra.s   14b
19:     move.l  #20000,%d1
17:     movem.l %d1-%d2/%a2,-(%sp)
        move.w  #1,-(%sp)
        move.w  #8,-(%sp)
        trap    #13                     | Bcostat(AUX)
        addq.l  #4,%sp
        movem.l (%sp)+,%d1-%d2/%a2
        tst.w   %d0
        bne.s   18f
        subq.l  #1,%d1
        bne.s   17b
        lea     auxdrop(%pc),%a0
        addq.w  #1,(%a0)              | AUX not ready: drop the char (TODO 9 stall shows as drops)
        bra.s   14b
18:     move.l  %a2,-(%sp)
        move.w  %d2,-(%sp)
        move.w  #1,-(%sp)
        move.w  #3,-(%sp)
        trap    #13                     | Bconout(AUX)
        addq.l  #6,%sp
        move.l  (%sp)+,%a2
        bra.s   14b
15:     movem.l (%sp)+,%d0-%d2/%a0-%a2
        rts
crlf:   move.l  %a0,-(%sp)
        lea     m_nl(%pc),%a0
        bsr     out
        move.l  (%sp)+,%a0
        rts
| hexw: print d0.w as $XXXX
hexw:   movem.l %d0-%d2/%a0,-(%sp)
        lea     hbuf+5(%pc),%a0
        moveq   #3,%d2
16:     move.w  %d0,%d1
        and.w   #15,%d1
        move.b  hdig(%pc,%d1.w),-(%a0)
        lsr.w   #4,%d0
        dbra    %d2,16b
        lea     hbuf(%pc),%a0
        bsr     out
        movem.l (%sp)+,%d0-%d2/%a0
        rts
hdig:   .ascii  "0123456789ABCDEF"
hbuf:   .asciz  "$0000"
m_start: .asciz "\r\nBT14 scroll+clear replica, loop reads (a4): A cache on/RAM B off/RAM C on/ROM D off/ROM\r\n"
m_a:    .asciz  "scroll: "
m_b:    .asciz  "clear:  "
m_c:    .asciz  "CACR was "
m_h:    .asciz  "-- case "
m_ok:   .asciz  "OK      "
m_tmo:  .asciz  "TIMEOUT "
m_r:    .asciz  "restarts "
m_y:    .asciz  " y="
m_x:    .asciz  " x="
m_s:    .asciz  " src="
m_d:    .asciz  " dst="
m_end:  .asciz  "Blitmode(0). Done, exit in 5 s.\r\n"
m_nl:   .asciz  "\r\n"
        .even
auxdrop: .word 0
scr:    .long   0
cacr0:  .long 0
ramv:   .long 0
res:    .space  160
