.ifndef NOAUX
.equ NOAUX,1
.endif
| BLTTEST.PRG - cursory STE blitter copy integrity test for the falconfpga 030 ST core.
| HOP=2 (source), OP=3 (source); ST-RAM -> ST-RAM; every word of the 192 KB destination
| buffer is compared against a CPU reference model (incl. guard areas outside the blit).
| Output to screen (Cconws) and serial (Bconout AUX). Position independent, no relocation.
| Build: ./build.sh  (GNU m68k binutils, /workspace/tools/bin)
        .equ    BUFSZ, 196608
        .equ    BLT, 0xffff8a00
        .text
start:  move.l  4(sp),a0                | basepage
        lea     stktop(pc),sp           | own stack (the TPA top is given back below)
        lea     vars(pc),a6
        move.l  #0x100+progend-start,-(sp)
        move.l  a0,-(sp)
        clr.w   -(sp)
        move.w  #0x4a,-(sp)             | Mshrink(0, basepage, size)
        trap    #1
        lea     12(sp),sp
        clr.l   -(sp)
        move.w  #0x20,-(sp)             | Super(0)
        trap    #1
        addq.l  #6,sp
        move.l  d0,0(a6)
        move.w  #1,-(sp)                | Setscreen(-1,-1,1): ST medium, 80 columns
        move.l  #-1,-(sp)
        move.l  #-1,-(sp)
        move.w  #5,-(sp)
        trap    #14
        lea     12(sp),sp
        bsr     ppal                    | palette as Setscreen left it
        move.w  #0x000,-(sp)            | 1.3: Setcolor(3, black): medium-res text is pen 3
        move.w  #3,-(sp)
        move.w  #7,-(sp)
        trap    #14
        addq.l  #6,sp
        bsr     ppal
        lea     m_title(pc),a0
        bsr     print
        move.w  #-1,-(sp)
        move.w  #64,-(sp)               | Blitmode(-1): bit1 = TOS found a blitter, bit0 = TOS uses it
        trap    #14
        addq.l  #4,sp
        lea     m_bm(pc),a0
        move.w  d0,54(a6)
        bsr     print
        moveq   #0,d0
        move.w  54(a6),d0
        bsr     phex2
        lea     m_nl(pc),a0
        bsr     print
| blitter present? probe with a bus error trap
        move.l  0x8.w,4(a6)
        move.l  sp,8(a6)
        lea     noblt(pc),a0
        move.l  a0,0x8.w
        tst.w   BLT
        move.l  4(a6),0x8.w
| buffers: src, dst, ref (ST-RAM only), scratch 4 KB
        moveq   #3,d7
        lea     12(a6),a3
1:      clr.w   -(sp)                   | Mxalloc(size, 0 = ST-RAM)
        move.l  #BUFSZ,-(sp)
        move.w  #0x44,-(sp)
        trap    #1
        addq.l  #8,sp
        cmp.l   #-32,d0
        bne.s   2f
        move.l  #BUFSZ,-(sp)            | TOS 1.x: Malloc
        move.w  #0x48,-(sp)
        trap    #1
        addq.l  #6,sp
2:      tst.l   d0
        ble     nomem
        addq.l  #1,d0
        and.w   #0xfffe,d0
        move.l  d0,(a3)+
        dbra    d7,1b
| pass 1: test 4 masked; pass 2: whole suite masked; pass 3: test 4 unmasked (control, last)
        clr.l   30(a6)
        clr.l   34(a6)
        lea     m_p1(pc),a0
        bsr     print
        move.w  #1,56(a6)
        lea     tests+3*32(pc),a5
        move.w  #3,28(a6)
        moveq   #1,d7
        bsr     suite
        lea     m_p2(pc),a0
        bsr     print
        move.w  #1,56(a6)
        lea     tests(pc),a5
        clr.w   28(a6)
        moveq   #99,d7
        bsr     suite
        lea     m_p3(pc),a0
        bsr     print
        clr.w   56(a6)
        lea     tests+3*32(pc),a5
        move.w  #3,28(a6)
        moveq   #1,d7
        bsr     suite
        bra     done
| suite: a5 = first table entry, d7 = max tests, 56(a6) = mask flag
suite:  move.l  d7,60(a6)
nextt:  tst.w   (a5)
        beq     sdone
        tst.l   60(a6)
        beq     sdone
        subq.l  #1,60(a6)
        addq.w  #1,28(a6)
        lea     m_run(pc),a0
        bsr     print
        move.w  28(a6),d0
        bsr     phex2
        lea     m_um(pc),a0
        tst.w   56(a6)
        beq.s   0f
        lea     m_mk(pc),a0
0:      bsr     print
        bsr     prep
        bsr     model
        bsr     primer
        bsr     blit
        lea     m_end(pc),a0
        bsr     print
        bsr     compare
        lea     m_t(pc),a0
        bsr     print
        move.w  28(a6),d0
        bsr     phex2
        lea     m_mis(pc),a0
        bsr     print
        move.l  d6,d0
        bsr     phex8
        lea     m_cpu(pc),a0
        bsr     print
        move.l  38(a6),d0
        bsr     phex8
        tst.l   d6
        bne.s   3f
        tst.l   38(a6)
        bne.s   3f
        addq.l  #1,30(a6)
        lea     m_ok(pc),a0
        bra.s   4f
3:      addq.l  #1,34(a6)
        lea     m_bad(pc),a0
4:      bsr     print
        lea     32(a5),a5
        bra     nextt
sdone:  rts
done:   bsr     ppal
        lea     m_sum(pc),a0
        bsr     print
        move.l  30(a6),d0
        bsr     phex2
        lea     m_sum2(pc),a0
        bsr     print
        move.l  34(a6),d0
        bsr     phex2
        lea     m_nl(pc),a0
        bsr     print
        tst.l   34(a6)
        bne.s   exit
        lea     m_allok(pc),a0
        bsr     print
exit:   move.w  #7,-(sp)                | Crawcin: wait for a key
        trap    #1
        addq.l  #2,sp
        move.l  0(a6),-(sp)
        move.w  #0x20,-(sp)
        trap    #1
        addq.l  #6,sp
        clr.w   -(sp)
        trap    #1
noblt:  move.l  8(a6),sp
        move.l  4(a6),0x8.w
        lea     m_noblt(pc),a0
        bsr     print
        bra     exit
nomem:  lea     m_nomem(pc),a0
        bsr     print
        bra     exit

| ---- prep: fill src/dst with pseudo-random words, ref = copy of dst ----
prep:   move.l  12(a6),a0        | src
        move.l  16(a6),a1      | dst
        move.l  20(a6),a2      | ref
        move.w  28(a6),d0
        mulu    #0x9e37,d0
        add.l   #0x12345678,d0
        move.l  #BUFSZ/4-1,d1
1:      move.l  d0,d2                   | xorshift32
        lsl.l   #8,d2
        lsl.l   #5,d2
        eor.l   d2,d0
        move.l  d0,d2
        lsr.l   #8,d2
        lsr.l   #8,d2
        lsr.l   #1,d2
        eor.l   d2,d0
        move.l  d0,d2
        lsl.l   #5,d2
        eor.l   d2,d0
        move.l  d0,(a0)+
        move.l  d0,d2
        not.l   d2
        swap    d2
        move.l  d2,(a1)+
        move.l  d2,(a2)+
        subq.l  #1,d1
        bpl.s   1b
        rts

| ---- reference model (STE blitter, HOP=2 OP=3) into ref ----
| d0 32-bit source buffer, d1 x count, d2 y count, d3 skew, d6 internal NFSR, a0 src, a1 ref dst
model:  move.l  12(a6),a0
        add.l   24(a5),a0
        move.l  20(a6),a1
        add.l   28(a5),a1
        move.l  #0xa5c33c5a,d0          | buffer after the primer blit (P0:P1)
        moveq   #15,d3
        and.b   19(a5),d3
        move.w  2(a5),d2
ml:     moveq   #0,d6
        move.w  (a5),d1
mw:     moveq   #0,d5                   | fetched flag
| end mask
        move.w  12(a5),d4
        cmp.w   (a5),d1
        beq.s   1f
        cmp.w   #1,(a5)
        beq.s   1f
        move.w  16(a5),d4
        cmp.w   #1,d1
        beq.s   1f
        move.w  14(a5),d4
1:
| FXSR on the first word
        cmp.w   (a5),d1
        bne.s   2f
        btst    #7,19(a5)
        beq.s   2f
        bsr     sfetch
        add.w   4(a5),a0
2:      tst.w   d6
        bne.s   3f
        bsr     sfetch
        moveq   #1,d5
| NFSR on the last word of a line (any xcount, as the STE blitter, Hatari and stBlitter.sv do): the last
| bus word is shifted into the buffer before the word is made (RMW dest read if masked, else the previous write),
| and the written word is shifted in after it.
3:      cmp.w   #1,d1
        bne.s   13f
        btst    #6,19(a5)
        beq.s   13f
        cmp.w   #-1,d4
        beq.s   10f
        move.w  (a1),64(a6)
10:     move.w  64(a6),d7
        bsr     sin
13:     move.l  d0,d7
        lsr.l   d3,d7                   | source word = buffer >> skew
        and.w   d4,d7
        not.w   d4
        and.w   (a1),d4
        or.w    d4,d7
        move.w  d7,(a1)
        move.w  d7,64(a6)               | last bus word = this write
        cmp.w   #1,d1
        bne.s   14f
        btst    #6,19(a5)
        beq.s   14f
        bsr     sin
14:
| internal NFSR set when x goes 2 -> 1
        cmp.w   #2,d1
        bne.s   4f
        btst    #6,19(a5)
        beq.s   4f
        moveq   #1,d6
4:      tst.w   d5
        beq.s   6f
        cmp.w   #1,d1
        beq.s   5f
        tst.w   d6
        bne.s   5f
        add.w   4(a5),a0
        bra.s   6f
5:      add.w   6(a5),a0
6:      cmp.w   #1,d1
        beq.s   7f
        subq.w  #1,d1
        add.w   8(a5),a1
        bra     mw
7:      add.w   10(a5),a1
        subq.w  #1,d2
        bne     ml
        rts
| ppal: print "PAL $FF8240-46: c0 c1 c2 c3"
ppal:   lea     m_pal(pc),a0
        bsr     print
        lea     0xffff8240.w,a4
        moveq   #3,d5
1:      moveq   #0,d0
        move.w  (a4)+,d0
        and.w   #0x0fff,d0
        move.l  d0,-(sp)
        moveq   #3,d2
        bsr     ph
        lea     m_sp(pc),a0
        bsr     print
        move.l  (sp)+,d0
        dbra    d5,1b
        lea     m_nl(pc),a0
        bra     print
| sin: shift word d7 into the source buffer d0 (direction from the source x increment)
sin:    tst.w   4(a5)
        bmi.s   1f
        swap    d0
        move.w  d7,d0
        rts
1:      move.w  d7,d0
        swap    d0
        rts
sfetch: tst.w   4(a5)
        bmi.s   1f
        swap    d0                      | buf = buf << 16 | w
        move.w  (a0),d0
        rts
1:      move.w  (a0),d0                 | buf = buf >> 16 | w << 16
        swap    d0
        rts

| ---- primer: 2-word blit so the hardware source buffer is P0:P1 ----
primer: move.l  24(a6),a0
        move.l  #0xa5c33c5a,(a0)
        lea     BLT,a2
        move.w  #2,0x20(a2)
        move.w  #2,0x22(a2)
        move.l  a0,0x24(a2)
        move.w  #-1,0x28(a2)
        move.w  #-1,0x2a(a2)
        move.w  #-1,0x2c(a2)
        move.w  #2,0x2e(a2)
        move.w  #2,0x30(a2)
        pea     16(a0)
        move.l  (sp)+,0x32(a2)
        move.w  #2,0x36(a2)
        move.w  #1,0x38(a2)
        move.b  #2,0x3a(a2)
        move.b  #3,0x3b(a2)
        clr.b   0x3d(a2)
        move.b  #0xc0,0x3c(a2)          | busy + HOG
1:      btst    #7,0x3c(a2)
        bne.s   1b
        rts

| ---- the blit under test ----
blit:   lea     BLT,a2
        move.w  4(a5),0x20(a2)
        move.w  6(a5),0x22(a2)
        move.l  12(a6),d0
        add.l   24(a5),d0
        move.l  d0,0x24(a2)
        move.w  12(a5),0x28(a2)
        move.w  14(a5),0x2a(a2)
        move.w  16(a5),0x2c(a2)
        move.w  8(a5),0x2e(a2)
        move.w  10(a5),0x30(a2)
        move.l  16(a6),d0
        add.l   28(a5),d0
        move.l  d0,0x32(a2)
        move.w  (a5),0x36(a2)
        move.w  2(a5),0x38(a2)
        move.b  #2,0x3a(a2)
        move.b  #3,0x3b(a2)
        move.b  19(a5),0x3d(a2)
        clr.l   38(a6)
        move.b  21(a5),d0
        or.b    #0x80,d0
        move.w  sr,58(a6)
        tst.w   56(a6)
        beq.s   0f
        or.w    #0x0700,sr              | IPL 7 from go to BUSY clear
0:      move.b  d0,0x3c(a2)             | go (HOG bit from the table)
        tst.w   22(a5)
        bne.s   busy
1:      btst    #7,0x3c(a2)
        bne.s   1b
        move.w  58(a6),sr
        rts
| CPU memory traffic in ST-RAM while the blitter runs (shared mode): write/read-back 256 longs
busy:   move.l  24(a6),a3
        lea     256(a3),a3
        moveq   #0,d4
1:      move.l  a3,a4
        move.w  #255,d1
2:      move.l  d4,(a4)+
        addq.l  #3,d4
        dbra    d1,2b
        sub.l   #256*3,d4
        move.l  a3,a4
        move.w  #255,d1
3:      cmp.l   (a4)+,d4
        beq.s   4f
        addq.l  #1,38(a6)
4:      addq.l  #3,d4
        dbra    d1,3b
        btst    #7,0x3c(a2)
        bne.s   1b
        move.w  58(a6),sr
        rts

| ---- compare dst with ref: d6 = mismatching words ----
compare: move.l 16(a6),a0
        move.l  20(a6),a1
        move.l  #BUFSZ/2-1,d1
        moveq   #0,d6
1:      cmpm.w  (a0)+,(a1)+
        beq.s   2f
        addq.l  #1,d6
2:      subq.l  #1,d1
        bpl.s   1b
        rts

| ---- output to screen and serial ----
print:  move.l  a0,-(sp)
        move.l  a0,-(sp)
        move.w  #9,-(sp)
        trap    #1
        addq.l  #6,sp
        move.l  (sp)+,a3
.if NOAUX
        rts                             | 1.1: screen only (AUX Bconout stalled after pass 1 on tt22)
.endif
1:      moveq   #0,d0
        move.b  (a3)+,d0
        beq.s   2f
        move.w  d0,-(sp)
        move.w  #1,-(sp)                | AUX
        move.w  #3,-(sp)                | Bconout
        trap    #13
        addq.l  #6,sp
        bra.s   1b
2:      rts
phex8:  moveq   #7,d2
        bra.s   ph
phex2:  moveq   #1,d2
ph:     lea     51(a6),a0
        clr.b   (a0)
        move.l  d2,d3
        addq.l  #1,d3
1:      move.b  d0,d1
        and.b   #15,d1
        add.b   #'0',d1
        cmp.b   #'9',d1
        bls.s   2f
        addq.b  #7,d1
2:      move.b  d1,-(a0)
        lsr.l   #4,d0
        subq.l  #1,d3
        bne.s   1b
        bra     print

m_title: .asciz "\r\nBLTMASK 1.3 (no AUX, NFSR model fixed, pen 3 black) - BLTTEST with IPL masked (SR $2700) around each blit\r\n"
m_t:    .asciz  "test $"
m_pal:  .asciz  "PAL $FF8240-46: "
m_sp:   .asciz  " "
m_p1:   .asciz  "== PASS 1: test 4, IPL masked ==\r\n"
m_p2:   .asciz  "== PASS 2: all tests, IPL masked ==\r\n"
m_p3:   .asciz  "== PASS 3: test 4, NOT masked (control) ==\r\n"
m_run:  .asciz  "> run $"
m_mk:   .asciz  " masked ... "
m_um:   .asciz  " unmasked ... "
m_end:  .asciz  "blit done\r\n"
m_bm:   .asciz  "TOS Blitmode(-1) = $"
m_mis:  .asciz  "  bad words $"
m_cpu:  .asciz  "  cpu errs $"
m_ok:   .asciz  "  PASS\r\n"
m_bad:  .asciz  "  FAIL\r\n"
m_sum:  .asciz  "RESULT pass $"
m_sum2: .asciz  " fail $"
m_nl:   .asciz  "\r\n"
m_allok: .asciz "ALL PASS\r\n"
m_noblt: .asciz "No blitter at $FF8A00 (bus error)\r\n"
m_nomem: .asciz "Out of ST-RAM\r\n"
        .even
| test table, 32 bytes each:
| xcnt ycnt sxinc syinc dxinc dyinc em1 em2 em3 skew(FXSR=80,NFSR=40) ctrl(HOG=40) busy srcoff.l dstoff.l
        .equ    MID, 98304
tests:
        .word   1,1,     2,2,     2,2,      -1,-1,-1, 0x00, 0x40, 0
        .long   16, 16                                  | 1 word, HOG
        .word   7,1,     2,2,     2,2,      -1,-1,-1, 0x00, 0x00, 0
        .long   2, 6                                    | 7 words, shared
        .word   13,9,    2,2,     2,136,    -1,-1,-1, 0x00, 0x40, 0
        .long   100, 2002                               | 13x9 odd, screen stride, HOG
        .word   13,9,    2,2,     2,136,    -1,-1,-1, 0x00, 0x00, 1
        .long   100, 2002                               | same, shared + CPU busy
        .word   10,7,    2,4,     2,100,    0x07ff,-1,0xf800, 0x85, 0x40, 0
        .long   300, 4000                               | skew 5 FXSR, masks
        .word   9,5,     2,4,     2,80,     0x3fff,-1,0xfffc, 0x4b, 0x00, 1
        .long   502, 8000                               | skew 11 NFSR, shared + busy
        .word   20,3,    2,2,     2,60,     0x00ff,0x0ff0,0xff00, 0xc3, 0x40, 0
        .long   1000, 12000                             | skew 3 FXSR+NFSR, all masks
        .word   33,4,    -2,-2,   -2,-34,   -1,-1,-1, 0x07, 0x40, 0
        .long   MID, MID                                | negative increments, skew 7
        .word   33,4,    -2,-6,   -2,-40,   0x1fff,-1,0xe000, 0x8a, 0x00, 0
        .long   MID+1000, MID+2000                      | negative, FXSR skew 10, shared
        .word   40,10,   8,8,     8,8,      -1,-1,-1, 0x00, 0x00, 1
        .long   6, 20000                                | bitplane stride 8, shared + busy
        .word   1,33,    2,158,   2,158,    0x0ff0,-1,-1, 0x84, 0x40, 0
        .long   40000, 60000                            | 1 word x 33 lines, FXSR skew 4
        .word   256,130, 2,2,     2,2,      -1,-1,-1, 0x00, 0x40, 0
        .long   16, 16                                  | 66560 bytes, HOG
        .word   4096,9,  2,2,     2,2,      -1,-1,-1, 0x00, 0x00, 1
        .long   16, 32                                  | 73728 bytes, shared + busy
        .word   0
        .even
textend:
        .bss
vars:
oldssp: .long   0
oldberr: .long  0
savsp:  .long   0
bufs:   .long   0,0,0,0
tno:    .word   0
npass:  .long   0
nfail:  .long   0
cpuerr: .long   0
hbuf:   .space  12
bmode:  .word   0
maskf:  .word   0
savsr:  .word   0
tleft:  .long   0
busw:   .word   0
        .even
stack:  .space  4096
stktop:
progend:
