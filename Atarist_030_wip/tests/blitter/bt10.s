| BT10.PRG - TODO 9: TOS 2.06 VT52 scroll blit replica ($E06630-$E06676) with a timeout.
| Non-HOG, src = dst+$500, x/y incr 2, xcount $280, ycount 24, HOP2 OP3, start move.w #$8000,
| restart tas/nop/bmi. Case A: own ST-RAM buffers. Case B: the real screen (Logbase).
| Nothing is printed while a blit runs; results are printed after Blitmode(0).
        .text
        .equ    BLT,0xffff8a00
        clr.l   -(%sp)
        move.w  #0x20,-(%sp)
        trap    #1
        addq.l  #6,%sp
        lea     m_start(%pc),%a0
        bsr     out
        move.w  #3,-(%sp)
        trap    #14                     | Logbase
        addq.l  #2,%sp
        lea     scr(%pc),%a0
        move.l  %d0,(%a0)
        move.w  #1,-(%sp)
        move.w  #64,-(%sp)
        trap    #14                     | Blitmode(1)
        addq.l  #4,%sp
| case A: buffers (fill src with a pattern)
        lea     buf(%pc),%a0
        move.l  %a0,%d0
        addq.l  #2,%d0
        and.l   #-4,%d0
        move.l  %d0,%a0
        move.w  #8000-1,%d1
        move.l  #0x13572468,%d2
1:      move.l  %d2,(%a0)+
        rol.l   #1,%d2
        dbra    %d1,1b
        move.l  %d0,%d6                 | dst = buffer start, src = dst+$500
        lea     resA(%pc),%a3
        bsr     scroll
| case B: real screen
        move.l  scr(%pc),%d6
        lea     resB(%pc),%a3
        bsr     scroll
        clr.w   -(%sp)
        move.w  #64,-(%sp)
        trap    #14                     | Blitmode(0)
        addq.l  #4,%sp
| report
        lea     m_a(%pc),%a0
        bsr     out
        lea     resA(%pc),%a3
        bsr     report
        lea     m_b(%pc),%a0
        bsr     out
        lea     resB(%pc),%a3
        bsr     report
        lea     m_end(%pc),%a0
        bsr     out
        move.l  0x4ba.w,%d0
        add.l   #1000,%d0
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
m_start: .asciz "\r\nBT10 TODO9 scroll blit test (buffer, then screen)\r\n"
m_a:    .asciz  "A buffer: "
m_b:    .asciz  "B screen: "
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
resA:   .space  20
resB:   .space  20
buf:    .space  32004
