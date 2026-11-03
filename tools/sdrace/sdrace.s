| SDRACE.PRG - FalconFPGA SD write-path test (sd-write branch). PC-relative.
| Mode A: Flopwr (posted FDC SD write) then IMMEDIATELY DMAwrite (ACSI) -> read both back.
| Mode B: same with 0.5 s gap (control).  Mode C: mode A with CACR=0.
| Mode T: Floprd into a TT-RAM buffer (Mxalloc mode 1) -> ST alias check (TOS DMA vs TT-RAM).
        .text
        .equ    N,40
start:  move.l  4(%sp),%a5
        clr.l   -(%sp)
        move.w  #0x20,-(%sp)
        trap    #1
        addq.l  #6,%sp
        lea     m_hi(%pc),%a0
        bsr     cws
        move.w  #0,0x444.w              | _fverify off: maximise the race
        lea     m_A(%pc),%a0
        bsr     cws
        moveq   #0,%d7                  | gap ticks
        bsr     run
        lea     m_B(%pc),%a0
        bsr     cws
        moveq   #100,%d7                | 0.5 s
        bsr     run
        lea     m_C(%pc),%a0
        bsr     cws
        movec   %cacr,%d0
        lea     ocacr(%pc),%a0
        move.l  %d0,(%a0)
        moveq   #0,%d0
        movec   %d0,%cacr
        moveq   #0,%d7
        bsr     run
        move.l  ocacr(%pc),%d0
        movec   %d0,%cacr
        lea     m_D(%pc),%a0
        bsr     cws
        move.l  ocacr(%pc),%d0
        and.l   #0xffffdfff,%d0         | WA off, caches on
        movec   %d0,%cacr
        moveq   #0,%d7
        bsr     run
        move.l  ocacr(%pc),%d0
        movec   %d0,%cacr
        lea     m_E(%pc),%a0
        bsr     cws
        lea     cdflag(%pc),%a0
        st      (%a0)
        moveq   #0,%d7
        bsr     run
        lea     cdflag(%pc),%a0
        sf      (%a0)
        lea     m_cr(%pc),%a0
        bsr     cws
        move.l  ocacr(%pc),%d0
        bsr     hex
        lea     m_nl(%pc),%a0
        bsr     cws
        bsr     ttt
        lea     res(%pc),%a0
        move.l  #0x53445243,(%a0)        | 'SDRC' at offset 0..3 overwritten? keep tag at 508
        lea     res+508(%pc),%a0
        move.l  #0x53445243,(%a0)
        clr.w   -(%sp)                  | DMAwrite results to lba 100
        pea     res(%pc)
        move.w  #1,-(%sp)
        move.l  #100,-(%sp)
        move.w  #43,-(%sp)
        trap    #14
        lea     14(%sp),%sp
        lea     m_end(%pc),%a0
        bsr     cws
        move.w  #-1,0x444.w
        move.l  #6000,%d0               | hold the screen 30 s
        bsr     wait
        clr.w   -(%sp)
        trap    #1

| ---- one mode: N iterations, d7 = gap in 200 Hz ticks
run:    lea     cnt(%pc),%a0
        clr.l   (%a0)+
        clr.l   (%a0)+
        clr.l   (%a0)+
        clr.l   (%a0)+
        moveq   #0,%d6                  | i
1:      lea     bufF(%pc),%a0
        move.l  #0x46000000,%d0         | 'F'
        bsr     fill
        lea     bufH(%pc),%a0
        move.l  #0x48000000,%d0         | 'H'
        bsr     fill
        | Flopwr(bufF,0,dev 0,sect 1+i%9,track 79,side 0,1)
        move.w  #1,-(%sp)
        clr.w   -(%sp)
        move.w  #79,-(%sp)
        move.l  %d6,%d0
        divu    #9,%d0
        swap    %d0
        addq.w  #1,%d0
        move.w  %d0,-(%sp)
        clr.w   -(%sp)
        clr.l   -(%sp)
        pea     bufF(%pc)
        move.w  #9,-(%sp)
        trap    #14
        lea     20(%sp),%sp
        tst.l   %d0
        beq.s   2f
        lea     cnt+12(%pc),%a0
        addq.l  #1,(%a0)
2:      move.l  %d7,%d0
        bsr     wait
        | DMAwrite(lba 64+i%8, 1, bufH, dev 0)
        clr.w   -(%sp)
        pea     bufH(%pc)
        move.w  #1,-(%sp)
        move.l  %d6,%d0
        and.l   #7,%d0
        add.l   #64,%d0
        move.l  %d0,-(%sp)
        move.w  #43,-(%sp)
        trap    #14
        lea     14(%sp),%sp
        lea     dret(%pc),%a0
        move.l  %d0,(%a0)
        tst.l   %d0
        beq.s   3f
        lea     cnt+12(%pc),%a0
        addq.l  #1,(%a0)
3:      move.l  #100,%d0
        bsr     wait
        | read back ACSI into bufR
        lea     bufR(%pc),%a0
        move.w  #127,%d1
4:      clr.l   (%a0)+
        dbra    %d1,4b
        clr.w   -(%sp)
        pea     bufR(%pc)
        move.w  #1,-(%sp)
        move.l  %d6,%d0
        and.l   #7,%d0
        add.l   #64,%d0
        move.l  %d0,-(%sp)
        move.w  #42,-(%sp)
        trap    #14
        lea     14(%sp),%sp
        lea     bufH(%pc),%a1
        bsr     cmpR                    | d0 = 0 ok
        beq.s   5f
        lea     cnt(%pc),%a0
        addq.l  #1,(%a0)
        cmp.b   #0x46,bufR(%pc)         | floppy data landed in ACSI sector
        bne.s   5f
        lea     cnt+8(%pc),%a0
        addq.l  #1,(%a0)
5:      | read back floppy
        lea     bufR(%pc),%a0
        move.w  #127,%d1
6:      clr.l   (%a0)+
        dbra    %d1,6b
        move.w  #1,-(%sp)
        clr.w   -(%sp)
        move.w  #79,-(%sp)
        move.l  %d6,%d0
        divu    #9,%d0
        swap    %d0
        addq.w  #1,%d0
        move.w  %d0,-(%sp)
        clr.w   -(%sp)
        clr.l   -(%sp)
        pea     bufR(%pc)
        move.w  #8,-(%sp)
        trap    #14
        lea     20(%sp),%sp
        tst.b   cdflag(%pc)
        beq.s   61f
        movec   %cacr,%d0
        or.w    #0x0800,%d0             | CD: clear data cache
        movec   %d0,%cacr
61:     move.l  bufR(%pc),%d0
        lea     fdfirst(%pc),%a0
        move.l  %d0,(%a0)
        lea     bufF(%pc),%a1
        bsr     cmpR
        beq.s   7f
        lea     cnt+4(%pc),%a0
        addq.l  #1,(%a0)
        cmp.b   #0x48,bufR(%pc)
        bne.s   7f
        lea     cnt+8(%pc),%a0
        addq.l  #1,(%a0)
7:      addq.l  #1,%d6
        cmp.l   #N,%d6
        bcs     1b
        lea     res(%pc),%a0
        move.l  resp(%pc),%d0
        add.l   %d0,%a0
        lea     cnt(%pc),%a1
        move.l  (%a1)+,(%a0)+
        move.l  (%a1)+,(%a0)+
        move.l  (%a1)+,(%a0)+
        move.l  (%a1)+,(%a0)+
        move.l  dret(%pc),(%a0)+
        move.l  fdfirst(%pc),(%a0)+
        lea     resp(%pc),%a0
        add.l   #32,(%a0)
        | print " hd=xxxxxxxx fd=xxxxxxxx mix=xxxxxxxx rc=xxxxxxxx dw=xxxxxxxx"
        lea     m_hd(%pc),%a0
        bsr     cws
        move.l  cnt(%pc),%d0
        bsr     hex
        lea     m_fd(%pc),%a0
        bsr     cws
        move.l  cnt+4(%pc),%d0
        bsr     hex
        lea     m_mx(%pc),%a0
        bsr     cws
        move.l  cnt+8(%pc),%d0
        bsr     hex
        lea     m_rc(%pc),%a0
        bsr     cws
        move.l  cnt+12(%pc),%d0
        bsr     hex
        lea     m_dw(%pc),%a0
        bsr     cws
        move.l  dret(%pc),%d0
        bsr     hex
        lea     m_nl(%pc),%a0
        bra     cws

| ---- TT-RAM buffer test
ttt:    lea     m_T(%pc),%a0
        bsr     cws
        move.w  #1,-(%sp)
        move.l  #4096,-(%sp)
        move.w  #0x44,-(%sp)
        trap    #1
        addq.l  #8,%sp
        move.l  %d0,%a4
        bsr     hex                     | TT buffer address
        move.l  %a4,%d0
        cmp.l   #0x01000000,%d0
        bcs     9f                      | not TT-RAM: skip
        and.l   #0xfffffe00,%d0
        add.l   #512,%d0
        move.l  %d0,%a4                 | 512-aligned TT buffer
        and.l   #0x00ffffff,%d0
        move.l  %d0,%a3                 | ST alias
        lea     bufS(%pc),%a0           | save alias
        move.l  %a3,%a1
        move.w  #127,%d1
1:      move.l  (%a1)+,(%a0)+
        dbra    %d1,1b
        move.w  %sr,-(%sp)
        move.l  %a3,%a1
        move.l  %a4,%a2
        move.w  #127,%d1
2:      move.l  #0x55aa55aa,(%a1)+      | marker in alias
        move.l  #0x33cc33cc,(%a2)+      | marker in TT buffer
        dbra    %d1,2b
        move.w  #1,-(%sp)               | Floprd(tt, ..., sect 1, track 79)
        clr.w   -(%sp)
        move.w  #79,-(%sp)
        move.w  #1,-(%sp)
        clr.w   -(%sp)
        clr.l   -(%sp)
        move.l  %a4,-(%sp)
        move.w  #8,-(%sp)
        trap    #14
        lea     20(%sp),%sp
        move.l  %d0,%d5
        move.l  (%a4),%d4               | first long TT
        move.l  (%a3),%d3               | first long alias
        lea     bufS(%pc),%a0           | restore alias
        move.l  %a3,%a1
        move.w  #127,%d1
3:      move.l  (%a0)+,(%a1)+
        dbra    %d1,3b
        move.w  (%sp)+,%sr
        lea     res+224(%pc),%a0
        move.l  %a4,(%a0)+
        move.l  %d4,(%a0)+
        move.l  %d3,(%a0)+
        move.l  %d5,(%a0)+
        lea     m_tt(%pc),%a0
        bsr     cws
        move.l  %d4,%d0
        bsr     hex
        lea     m_al(%pc),%a0
        bsr     cws
        move.l  %d3,%d0
        bsr     hex
        lea     m_rc(%pc),%a0
        bsr     cws
        move.l  %d5,%d0
        bsr     hex
9:      lea     m_nl(%pc),%a0
        bra     cws

| fill a0 with 128 longs: d0 | i<<16 | k
fill:   move.l  %d6,%d1
        swap    %d1
        clr.w   %d1
        or.l    %d1,%d0
        moveq   #0,%d1
1:      move.l  %d0,%d2
        or.w    %d1,%d2
        move.l  %d2,(%a0)+
        addq.w  #1,%d1
        cmp.w   #128,%d1
        bcs.s   1b
        rts
| compare bufR with a1, Z=1 equal
cmpR:   lea     bufR(%pc),%a0
        move.w  #127,%d1
1:      cmpm.l  (%a0)+,(%a1)+
        dbne    %d1,1b
        rts
| wait d0 ticks of _hz_200
wait:   add.l   0x4ba.w,%d0
1:      cmp.l   0x4ba.w,%d0
        bhi.s   1b
        rts
| print hex long d0
hex:    movem.l %d0-%d4/%a0-%a2,-(%sp)
        move.l  %d0,%d4
        moveq   #7,%d3
1:      rol.l   #4,%d4
        move.w  %d4,%d0
        and.w   #15,%d0
        add.w   #0x30,%d0
        cmp.w   #0x3a,%d0
        bcs.s   2f
        addq.w  #7,%d0
2:      move.w  %d0,-(%sp)
        move.w  #2,-(%sp)
        move.w  #3,-(%sp)
        trap    #13
        addq.l  #6,%sp
        dbra    %d3,1b
        movem.l (%sp)+,%d0-%d4/%a0-%a2
        rts
cws:    movem.l %d0-%d2/%a0-%a2,-(%sp)
        move.l  %a0,-(%sp)
        move.w  #9,-(%sp)
        trap    #1
        addq.l  #6,%sp
        movem.l (%sp)+,%d0-%d2/%a0-%a2
        rts
m_hi:   .asciz  "\r\nSDRACE (FalconFPGA sd-write) N=40\r\n"
m_A:    .asciz  "A no gap  "
m_B:    .asciz  "B 0.5s gap"
m_C:    .asciz  "C nogap c0"
m_D:    .asciz  "D WA off  "
m_E:    .asciz  "E CD flush"
m_cr:   .asciz  "CACR="
m_T:    .asciz  "T ttbuf="
m_hd:   .asciz  " hd="
m_fd:   .asciz  " fd="
m_mx:   .asciz  "\r\n   mix="
m_rc:   .asciz  " rc="
m_dw:   .asciz  " dw="
m_tt:   .asciz  " tt="
m_al:   .asciz  " al="
m_nl:   .asciz  "\r\n"
m_end:  .asciz  "SDRACE DONE\r\n"
        .even
ocacr:  .long   0
fdfirst: .long  0
cdflag: .byte   0
        .even
resp:   .long   32
dret:   .long   0
cnt:    .long   0,0,0,0
bufF:   .space  512
bufH:   .space  512
bufR:   .space  512
bufS:   .space  512
res:    .space  512
