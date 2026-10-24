| BT17.PRG - TODO 9: BT16 split with a watchdog. SR=$2500 (VBL/HBL masked, MFP IPL6 on).
| MFP timer A (~48 Hz) watchdog: if the iteration counter stalls ~1 s it records the blitter
| state and the interrupted PC, stops the blitter and resumes at wdx. Stages:
|  A: restart loop in RAM x50   B: TOS ROM loop $E06670 x50   C: ROM loop entered at $E06672 x50
| (C: start write done from RAM). Result printed after Blitmode(0).
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
        move.l  %d0,%d6
        move.w  #1,-(%sp)
        move.w  #64,-(%sp)
        trap    #14
        addq.l  #4,%sp
        lea     V(%pc),%a6              | a6 = variables
        move.w  %sr,-(%sp)
        move.w  #0x2700,%sr
        move.l  0x134.w,OLDV(%a6)
        lea     wdog(%pc),%a0
        move.l  %a0,0x134.w
        clr.b   0xfffffa19.w
        move.b  #255,0xfffffa1f.w
        move.b  #7,0xfffffa19.w         | /200
        bset    #5,0xfffffa07.w
        bset    #5,0xfffffa13.w
        lea     fake(%pc),%a4
        lea     ret(%pc),%a0
        move.l  %a0,140(%a4)
        move.w  #0x2500,%sr
| stage A
        move.w  #1,STG(%a6)
        moveq   #49,%d7
1:      addq.l  #1,ITER(%a6)
        bsr     setup
2:      tas     (%a5)
        nop
        bmi.s   2b
        tst.w   WD(%a6)
        bne     done
        dbra    %d7,1b
| stage B
        move.w  #2,STG(%a6)
        moveq   #49,%d7
3:      addq.l  #1,ITER(%a6)
        bsr     setup
        lea     fake(%pc),%a4
        move.l  #0xe06670,%a0
        jmp     (%a0)
ret:    tst.w   WD(%a6)
        bne     done
        cmp.w   #3,STG(%a6)
        beq.s   4f
        dbra    %d7,3b
| stage C
        move.w  #3,STG(%a6)
        moveq   #50,%d7
4:      subq.w  #1,%d7
        beq.s   done
        addq.l  #1,ITER(%a6)
        bsr     setup
        lea     fake(%pc),%a4
        move.w  %d2,(%a5)
        move.l  #0xe06672,%a0
        jmp     (%a0)
done:   move.w  #0x2700,%sr
        bclr    #5,0xfffffa07.w
        bclr    #5,0xfffffa13.w
        clr.b   0xfffffa19.w
        move.l  OLDV(%a6),0x134.w
        move.w  (%sp)+,%sr
        clr.w   -(%sp)
        move.w  #64,-(%sp)
        trap    #14
        addq.l  #4,%sp
        lea     m_r(%pc),%a0
        bsr     cws
        lea     V(%pc),%a3
        moveq   #(VEND-V)/2-1,%d4
5:      move.w  (%a3)+,%d0
        bsr     hexw
        dbra    %d4,5b
        lea     m_end(%pc),%a0
        bsr     cws
        move.l  0x4ba.w,%d0
        add.l   #4000,%d0
6:      cmp.l   0x4ba.w,%d0
        bhi.s   6b
        clr.w   -(%sp)
        trap    #1
| watchdog (timer A, IPL6)
wdog:   movem.l %d0/%a0-%a1,-(%sp)
        lea     V(%pc),%a0
        addq.l  #1,TICKS(%a0)
        move.l  ITER(%a0),%d0
        cmp.l   LASTI(%a0),%d0
        beq.s   7f
        move.l  %d0,LASTI(%a0)
        clr.w   STALL(%a0)
        bra.s   8f
7:      addq.w  #1,STALL(%a0)
        cmp.w   #48,STALL(%a0)
        blo.s   8f
        tst.w   WD(%a0)
        bne.s   8f
        move.w  #1,WD(%a0)
        lea     BLT,%a1
        move.w  0x3c(%a1),WCTL(%a0)
        move.w  0x36(%a1),WXC(%a0)
        move.w  0x38(%a1),WYC(%a0)
        move.l  0x32(%a1),WDST(%a0)
        move.l  0x24(%a1),WSRC(%a0)
        move.l  14(%sp),WPC(%a0)        | stacked PC (frame: SR at 12(sp) after movem 12 bytes)
        clr.w   0x3c(%a1)               | stop blitter
        lea     done(%pc),%a1
        move.l  %a1,14(%sp)
8:      bclr    #5,0xfffffa0f.w         | ISRA (software EOI)
        movem.l (%sp)+,%d0/%a0-%a1
        rte
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
        cmp.w   #3,STG(%a6)
        beq.s   9f
        move.w  %d2,(%a5)
9:      rts
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
hbuf:   .asciz  "$0000 "
m_start: .asciz "\r\nBT17 A RAM loop, B ROM $E06670, C ROM $E06672; watchdog timer A\r\n"
m_r:    .asciz  "\r\nSTG WD ITERhi lo TICKShi lo LASTI.. STALL CTL XC YC DST.. SRC.. PC.. OLDV..\r\n"
m_end:  .asciz  "\r\nDone.\r\n"
        .even
        .equ    STG,0
        .equ    WD,2
        .equ    ITER,4
        .equ    TICKS,8
        .equ    LASTI,12
        .equ    STALL,16
        .equ    WCTL,18
        .equ    WXC,20
        .equ    WYC,22
        .equ    WDST,24
        .equ    WSRC,28
        .equ    WPC,32
        .equ    OLDV,36
V:      .space  40
VEND:
        .space  64
fake:   .space  160
