.ifndef MFPT
.equ MFPT,0
.endif
.ifndef CACR
.equ CACR,0
.endif
.ifndef SRV
.equ SRV,0x2700
.endif
.ifndef LOOPS
.equ LOOPS,20
.endif
| Blitter shared mode with 030 ST-RAM traffic (BLTTEST test 4): 13x9 copy
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
        move.w  #2,0x20(%a2)
        move.w  #2,0x22(%a2)
        move.l  #0x10000,0x24(%a2)
        move.w  #-1,0x28(%a2)
        move.w  #-1,0x2a(%a2)
        move.w  #-1,0x2c(%a2)
        move.w  #2,0x2e(%a2)
        move.w  #136,0x30(%a2)
        move.l  #0x20000,0x32(%a2)
        move.w  #13,0x36(%a2)
        move.w  #9,0x38(%a2)
        move.b  #2,0x3a(%a2)
        move.b  #3,0x3b(%a2)
        clr.b   0x3d(%a2)
        clr.l   0x1004.w
        moveq   #0,%d5
        move.b  #0x80,0x3c(%a2)
        lea     0x30000,%a3
        moveq   #0,%d4
1:      addq.l  #1,%d5
        move.l  %d5,0x1000.w
        cmp.l   #LOOPS,%d5
        bhi.s   fail
        move.l  %a3,%a4
        move.w  #255,%d1
2:      move.l  %d4,(%a4)+
        addq.l  #3,%d4
        dbra    %d1,2b
        sub.l   #256*3,%d4
        move.l  %a3,%a4
        move.w  #255,%d1
3:      cmp.l   (%a4)+,%d4
        beq.s   4f
        addq.l  #1,0x1004.w
4:      addq.l  #3,%d4
        dbra    %d1,3b
        btst    #7,0x3c(%a2)
        bne.s   1b
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
