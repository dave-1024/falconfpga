.ifndef MFPT
.equ MFPT,0
.endif
.ifndef CACR
.equ CACR,0
.endif
.ifndef SRV
.equ SRV,0x2700
.endif
.ifndef SRCA
.equ SRCA,0xe00000
.endif
.ifndef LOOPS
.equ LOOPS,20
.endif
| TOS 2.06 VDI style: start with move.w #$8000 then restart with tas (a5) / nop / bmi (TODO 9). Based on prog_blt.s: 13x9 copy
| $10000 -> $20000 (dst stride 136), no HOG; CPU writes/reads 256 longs at $30000
| while BUSY. Code runs from ST-RAM $4000; CACR/SR/LOOPS set with --defsym. $1000 = loops, $1004 = cpu errs, $1008 = dst checksum.
        .text
        .long   0x00008000
        .long   start
start:  move.w  #0x2700,%sr
        lea     0x8000,%sp
        move.b  #0x0a,0xffff8001.w
        lea     vbl(%pc),%a0
        move.l  %a0,0x70.w
        lea     body(%pc),%a0
        lea     0x4000,%a1
        move.w  #(bend-body)/2-1,%d7
0:      move.w  (%a0)+,(%a1)+
        dbra    %d7,0b
        lea     tmra(%pc),%a0
        move.l  %a0,0x134.w
        lea     hbl(%pc),%a0
        move.l  %a0,0x68.w
.if MFPT
        move.b  #0x40,0xfffffa17.w      | VR: vectors $40.., auto EOI
        move.b  #MFPT,0xfffffa1f.w      | TADR
        move.b  #1,0xfffffa19.w         | TACR: delay /4
        bset    #5,0xfffffa07.w         | IERA timer A
        bset    #5,0xfffffa13.w         | IMRA timer A
.endif
        move.l  #CACR,%d0
        movec   %d0,%cacr
        move.w  #SRV,%sr
        jmp     0x4000
vbl:    addq.l  #1,0x100c.w
        move.l  0x1000.w,0x1010.w
        rte
tmra:   addq.l  #1,0x1014.w
        rte
hbl:    addq.l  #1,0x1018.w
        rte
body:
        lea     0x10000,%a0
        move.l  #0x12345678,%d1
        move.w  #255,%d7
1:      move.l  %d1,(%a0)+
        rol.l   #3,%d1
        add.l   #0x01020305,%d1
        dbra    %d7,1b
        lea     0xffff8a00.w,%a2
| TOS 2.06 VDI text/icon blit replica ($E065D6 loop, Hatari trace): HOG, 1 word x 8 lines,
| source in ROM (system font), 8 blits, tst.w/bmi poll as TOS does.
        lea     0x3c(%a2),%a5
        move.w  #1,0x36(%a2)
        move.w  #0xff00,0x28(%a2)
        move.w  #0,0x20(%a2)
        move.w  #0x100,0x22(%a2)
        move.w  #0xa0,0x30(%a2)
        move.w  #2,0x2e(%a2)
        move.l  #SRCA,%a0
        move.l  #0x20000,%a3
        move.w  #7,%d2
        clr.l   0x1004.w
        moveq   #0,%d5
7:      move.l  %a0,0x24(%a2)
        move.l  %a3,0x32(%a2)
        move.w  #8,0x38(%a2)
        move.w  #0x0203,0x3a(%a2)
        move.w  #0xc000,(%a5)
        addq.l  #2,%a3
8:      addq.l  #1,%d5
        move.l  %d5,0x1000.w
        cmp.l   #LOOPS,%d5
        bhi.s   fail
        tst.w   (%a5)
        bmi.s   8b
        dbf     %d2,7b
        lea     0x20000,%a0
        moveq   #0,%d2
        move.w  #8,%d7
5:      moveq   #12,%d6
6:      add.w   (%a0)+,%d2
        dbra    %d6,6b
        lea     134(%a0),%a0
        dbra    %d7,5b
        move.l  %d2,0x1008.w
        move.l  #0x600dc0de,0x1ffc.w
9:      bra.s   9b
fail:   move.l  #0xbadbad00,0x1ffc.w
        bra.s   9b
bend:
