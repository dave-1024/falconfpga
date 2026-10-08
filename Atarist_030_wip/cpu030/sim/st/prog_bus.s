| F61 bus test ROM (E00000): RAM/IO/ROM read timing, bus error, blitter handover
        .text
        .long   0x00008000
        .long   start
start:  move.w  #0x2700,%sr
        lea     0x8000,%sp
        lea     berr(%pc),%a0
        move.l  %a0,0x8.w
        clr.l   0x1200.w
| fill 1 KB at $10000
        lea     0x10000,%a0
        move.l  #0x12345678,%d1
        move.w  #255,%d7
1:      move.l  %d1,(%a0)+
        rol.l   #3,%d1
        add.l   #0x01020305,%d1
        dbra    %d7,1b
| long read loop
        lea     0x10000,%a0
        moveq   #0,%d2
        move.w  #255,%d7
2:      add.l   (%a0)+,%d2
        dbra    %d7,2b
        move.l  %d2,0x1000.w
| unrolled long reads (back-to-back data cycles)
        lea     0x10000,%a0
        movem.l (%a0)+,%d0-%d6/%a1-%a6
        add.l   %d0,%d1
        add.l   %d1,%d2
        add.l   %d2,%d3
        add.l   %d3,%d4
        add.l   %d4,%d5
        add.l   %d5,%d6
        move.l  %d6,0x1004.w
        move.l  %a6,0x1008.w
| word reads
        lea     0x10000,%a0
        moveq   #0,%d3
        move.w  #511,%d7
3:      add.w   (%a0)+,%d3
        dbra    %d7,3b
        move.w  %d3,0x100c.w
| byte reads (odd/even)
        lea     0x10001,%a0
        moveq   #0,%d4
        move.w  #255,%d7
4:      add.b   (%a0),%d4
        add.b   -1(%a0),%d4
        rol.w   #1,%d4
        addq.l  #4,%a0
        dbra    %d7,4b
        move.w  %d4,0x100e.w
| misaligned long reads
        lea     0x10001,%a0
        moveq   #0,%d5
        move.w  #127,%d7
5:      add.l   (%a0),%d5
        addq.l  #6,%a0
        dbra    %d7,5b
        move.l  %d5,0x1010.w
| ROM data reads
        lea     0xe00000,%a0
        moveq   #0,%d6
        move.w  #255,%d7
6:      add.l   (%a0)+,%d6
        dbra    %d7,6b
        move.l  %d6,0x1014.w
| I/O reads
        lea     0x1100.w,%a1
        move.b  0xfffffa01.w,(%a1)+     | MFP GPIP
        move.b  0xfffffa03.w,(%a1)+     | MFP AER
        move.b  0xfffffa07.w,(%a1)+     | IERA
        move.b  #0x55,0xfffffa07.w
        move.b  0xfffffa07.w,(%a1)+     | IERA readback 55
        move.b  #0xa3,0xfffffa1f.w      | TADR
        move.b  0xfffffa1f.w,(%a1)+     | a3
        clr.b   0xfffffa07.w
        move.w  #0x0123,0xffff8240.w
        move.w  0xffff8240.w,(%a1)+     | palette 0123
        move.w  #0x0f0f,0xffff825e.w
        move.w  0xffff825e.w,(%a1)+     | 0f0f
        move.b  0xffff8201.w,(%a1)+     | video base hi
        move.b  0xffff8260.w,(%a1)+     | shifter mode
        move.b  0xfffffc00.w,(%a1)+     | ACIA status (VPA)
        move.b  0xffff8800.w,(%a1)+     | PSG
        move.w  #0x1234,0xffff8a20.w    | blitter src xinc
        move.w  0xffff8a20.w,(%a1)+     | 1234
        move.w  #0xbeef,0xffff8a00.w    | halftone 0
        move.w  0xffff8a00.w,(%a1)+     | beef
        move.w  0xffff8604.w,%d0        | DMA/FDC
        move.w  0xffff8606.w,(%a1)+     | DMA status
        move.l  %a1,0x11fc.w
| bus error on an unmapped address
        move.l  %sp,%a5
        tst.w   0xf00000
        move.w  #0xbad1,0x1204.w
after_berr:
        move.l  %a5,%sp
| blitter copy $10000 -> $20000, 256 words, shared bus (no HOG)
        move.w  #2,0xffff8a20.w
        move.w  #2,0xffff8a22.w
        move.l  #0x10000,0xffff8a24.w
        move.w  #0xffff,0xffff8a28.w
        move.w  #0xffff,0xffff8a2a.w
        move.w  #0xffff,0xffff8a2c.w
        move.w  #2,0xffff8a2e.w
        move.w  #2,0xffff8a30.w
        move.l  #0x20000,0xffff8a32.w
        move.w  #256,0xffff8a36.w
        move.w  #1,0xffff8a38.w
        move.b  #2,0xffff8a3a.w
        move.b  #3,0xffff8a3b.w
        move.b  #0,0xffff8a3d.w
        move.b  #0x80,0xffff8a3c.w
        moveq   #0,%d1
7:      addq.l  #1,%d1
        btst    #7,0xffff8a3c.w
        bne.s   7b
        move.l  %d1,0x1018.w
        lea     0x20000,%a0
        moveq   #0,%d2
        move.w  #127,%d7
8:      add.l   (%a0)+,%d2
        dbra    %d7,8b
        move.l  %d2,0x101c.w
        move.l  #0x600dc0de,0x1ffc.w
9:      bra.s   9b
berr:   addq.l  #1,0x1200.w
        move.l  2(%sp),0x1208.w          | 030 frame: PC
        move.w  6(%sp),0x120c.w          | format/vector
        move.l  16(%sp),0x1210.w         | fault address
        move.l  %a5,%sp
        jmp     after_berr
