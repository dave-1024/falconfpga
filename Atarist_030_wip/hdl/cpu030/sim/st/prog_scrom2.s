.ifndef MFPT
.equ MFPT,0
.endif
.ifndef CACR
.equ CACR,0
.endif
.ifndef SRV
.equ SRV,0x2700
.endif
.ifndef SRC
.equ SRC,0x3f8500
.endif
.ifndef DST
.equ DST,0x3f8000
.endif
.ifndef YC
.equ YC,2
.endif
.ifndef LOOPS
.equ LOOPS,20
.endif
| TODO 9 ROM variant (exact TOS loop): body runs from ROM (TOS executes its tas loop from ROM). TOS 2.06 VDI style: start with move.w #$8000 then restart with tas (a5) / nop / bmi (TODO 9). Based on prog_blt.s: 13x9 copy
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
        jmp     body(%pc)
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
| TOS 2.06 VT52 scroll replica ($E06630..$E06676, Hatari trace, Blitmode(1)):
| src SRC -> dst DST, x/y incr 2, xcount $280, ycount YC (TOS: 24), HOP 2 OP 3, non-HOG,
| started with move.w #$8000 and restarted with tas/nop/bmi.
        lea     0x3c(%a2),%a5
        move.w  #2,0x20(%a2)
        move.w  #2,0x22(%a2)
        move.l  #SRC,0x24(%a2)
        move.l  #-1,0x28(%a2)
        move.w  #-1,0x2c(%a2)
        move.w  #2,0x2e(%a2)
        move.w  #2,0x30(%a2)
        move.l  #DST,0x32(%a2)
        move.w  #0x280,0x36(%a2)
        move.w  #YC,0x38(%a2)
        move.w  #0x0203,0x3a(%a2)
        clr.l   0x1004.w
        move.w  #0x8000,%d2
        bra.w   0f
| exact TOS 2.06 $E06670 loop and alignment: move.w d2,(a5) at 4n, tas at 4n+2 (sim TIMEOUT = hang)
        .balign 4
0:      move.w  %d2,(%a5)
1:      tas     (%a5)
        nop
        bmi.s   1b
        lea     DST,%a0
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
