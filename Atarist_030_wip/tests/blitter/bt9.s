| BT9.PRG - TODO 9 board test: TOS 2.06 $E065D6-style HOG font blit, RAM source first, then ROM source.
| No keyboard input. Screen (Cconws) + AUX (Bconout 1) output. Polling timeout on BUSY.
        .text
        .equ    FONT,0x00e33774
        .equ    BLT,0xffff8a00
        clr.l   -(%sp)
        move.w  #0x20,-(%sp)
        trap    #1                      | Super(0)
        addq.l  #6,%sp
        lea     m_start(%pc),%a0
        bsr     out
        move.w  #1,-(%sp)
        move.w  #64,-(%sp)
        trap    #14                     | Blitmode(1)
        addq.l  #4,%sp
        move.w  #-1,-(%sp)
        move.w  #64,-(%sp)
        trap    #14
        addq.l  #4,%sp
        lea     m_bm(%pc),%a0
        bsr     out
        bsr     hexw
        bsr     crlf
| copy 8 font rows (stride 256) from ROM into the RAM copy, same layout
        lea     FONT,%a0
        lea     fcopy(%pc),%a1
        move.w  #8*128-1,%d0
1:      move.w  (%a0)+,(%a1)+
        dbra    %d0,1b
| ---- step 1: RAM source
        lea     fcopy(%pc),%a0
        move.l  %a0,%d6
        lea     m_s1(%pc),%a4
        bsr     test
        lea     res_ram(%pc),%a1
        bsr     saveres
| ---- step 2: ROM source
        move.l  #FONT,%d6
        lea     m_s2(%pc),%a4
        bsr     test
| compare ROM results with RAM results
        lea     res_ram(%pc),%a1
        lea     res(%pc),%a0
        moveq   #15,%d0
        moveq   #0,%d1
2:      cmp.w   (%a0)+,(%a1)+
        beq.s   3f
        addq.w  #1,%d1
3:      dbra    %d0,2b
        lea     m_cmp(%pc),%a0
        bsr     out
        move.w  %d1,%d0
        bsr     hexw
        bsr     crlf
        clr.w   -(%sp)
        move.w  #64,-(%sp)
        trap    #14                     | Blitmode(0)
        addq.l  #4,%sp
        lea     m_drop(%pc),%a0
        bsr     out
        move.w  auxdrop(%pc),%d0
        bsr     hexw
        bsr     crlf
        lea     m_end(%pc),%a0
        bsr     out
        move.l  0x4ba.w,%d0
        add.l   #600,%d0                | 3 s
4:      cmp.l   0x4ba.w,%d0
        bhi.s   4b
        clr.w   -(%sp)
        trap    #1                      | Pterm0

| test: d6 = source, a4 = step name. Two blits: ctrl $C000 then $C008. Results -> res (16 words)
test:   lea     res(%pc),%a3
        move.w  #0xc000,%d7
        bsr     blit1
        move.w  #0xc008,%d7
        bsr     blit1
        rts
| one blit with ctrl d7; 8 dest words -> (a3)+
blit1:  move.l  %a4,%a0
        bsr     out
        lea     m_ctl(%pc),%a0
        bsr     out
        move.w  %d7,%d0
        bsr     hexw
        lea     m_go(%pc),%a0
        bsr     out                     | progress marker before the blit
        lea     dst(%pc),%a0
        move.w  #8*80-1,%d0
5:      move.w  #0xaaaa,(%a0)+
        dbra    %d0,5b
        lea     BLT,%a2
        move.w  #1,0x36(%a2)
        move.w  #0xff00,0x28(%a2)
        move.w  #0xffff,0x2a(%a2)
        move.w  #0xffff,0x2c(%a2)
        move.w  #0,0x20(%a2)
        move.w  #0x100,0x22(%a2)
        move.w  #2,0x2e(%a2)
        move.w  #0xa0,0x30(%a2)
        move.l  %d6,0x24(%a2)
        lea     dst(%pc),%a0
        move.l  %a0,0x32(%a2)
        move.w  #8,0x38(%a2)
        move.w  #0x0203,0x3a(%a2)
        move.l  #2000000,%d5
        move.w  %d7,0x3c(%a2)           | start (HOG)
6:      tst.w   0x3c(%a2)
        bpl.s   7f
        subq.l  #1,%d5
        bne.s   6b
        clr.w   0x3c(%a2)
        lea     m_tmo(%pc),%a0
        bra.s   8f
7:      lea     m_ok(%pc),%a0
8:      bsr     out
        lea     dst(%pc),%a0
        moveq   #7,%d4
9:      move.w  (%a0),%d0
        move.w  %d0,(%a3)+
        bsr     hexw
        lea     m_sp(%pc),%a1
        exg     %a0,%a1
        bsr     out
        exg     %a0,%a1
        lea     160(%a0),%a0
        dbra    %d4,9b
        bsr     crlf
| exact check for $C000 (skew 0): (src & $FF00) | ($AAAA & $00FF)
        cmp.w   #0xc000,%d7
        bne.s   12f
        move.l  %d6,%a0
        lea     -16(%a3),%a1
        moveq   #7,%d4
        moveq   #0,%d1
10:     move.w  (%a0),%d0
        and.w   #0xff00,%d0
        or.w    #0x00aa,%d0
        cmp.w   (%a1)+,%d0
        beq.s   11f
        addq.w  #1,%d1
11:     lea     256(%a0),%a0
        dbra    %d4,10b
        lea     m_chk(%pc),%a0
        bsr     out
        move.w  %d1,%d0
        bsr     hexw
        bsr     crlf
12:     rts
saveres: lea    res(%pc),%a0
        moveq   #15,%d0
13:     move.w  (%a0)+,(%a1)+
        dbra    %d0,13b
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
m_start: .asciz "\r\nBT9 TODO9 blitter test (RAM then ROM)\r\n"
m_bm:   .asciz  "Blitmode(-1) = "
m_s1:   .asciz  "STEP1 RAM "
m_s2:   .asciz  "STEP2 ROM "
m_ctl:  .asciz  "ctrl "
m_go:   .asciz  " go... "
m_ok:   .asciz  "OK  "
m_tmo:  .asciz  "TIMEOUT  "
m_sp:   .asciz  " "
m_chk:  .asciz  "  check errors (C000 exact): "
m_cmp:  .asciz  "ROM vs RAM result differences: "
m_end:  .asciz  "Blitmode(0). Done, exit in 3 s.\r\n"
m_nl:   .asciz  "\r\n"
m_drop: .asciz  "AUX chars dropped: "
        .even
auxdrop: .word 0
res:    .space  32
res_ram: .space 32
fcopy:  .space  2048
dst:    .space  1280
