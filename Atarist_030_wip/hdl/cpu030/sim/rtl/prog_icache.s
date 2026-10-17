| [IC] 68030 instruction cache (ICACHE_DESIGN.md). tb030 CIMODE=1: CIIN negated for ROM $FD0000-
| (the loops) and RAM $8000-$FFFF; the driver code at $FC0000 stays uncached, so it cannot evict the
| loop lines. CIMODE=0: CIIN asserted everywhere (as the ST bridge, nothing cached).
| Each case writes its number to $3600, then runs a 2-instruction loop (8 passes) in its own
| 16-byte line. check_icache.py counts program-space bus cycles inside the loop's line per case.
| Results at $5000: case 14 D0 values (stale code until CI), CACR read-back, case 19 bus error
| count. DONE at $3300. Cases 21-25: CIIN asserted mid-run (tb $3502) keeps hits, stops fills.
        .text
        .org 0
        .long   0x00007000
        .long   0x00fc0008
start:
        lea     0x5000,a4
        lea     0x08,a0
        moveq   #9,d0
1:      move.l  #errh,(a0)+
        dbra    d0,1b
        move.l  #trh,0x80
        moveq   #0,d0
        movec   d0,cacr                 | EI off
| 1: EI off: every pass fetches
        move.w  #1,0x3600
        bsr     runa
| 2: clear all + enable: the first pass fills
        moveq   #9,d0                   | CI | EI
        movec   d0,cacr
        move.w  #2,0x3600
        bsr     runa
| 3: warm: no bus cycles in the loop line
        move.w  #3,0x3600
        bsr     runa
| 4: EI off: no hits
        moveq   #0,d0
        movec   d0,cacr
        move.w  #4,0x3600
        bsr     runa
| 5: EI on again without CI: the entries were kept
        moveq   #1,d0
        movec   d0,cacr
        move.w  #5,0x3600
        bsr     runa
| 6/7: freeze: loop B is not filled, loop A still hits
        moveq   #3,d0                   | FI | EI
        movec   d0,cacr
        move.w  #6,0x3600
        bsr     runb
        move.w  #7,0x3600
        bsr     runa
| 8: clear entry: CAAR = loop A, CEI: one long word refetched
        moveq   #1,d0
        movec   d0,cacr
        lea     lpa,a0
        movec   a0,caar
        moveq   #5,d0                   | CEI | EI
        movec   d0,cacr
        move.w  #8,0x3600
        bsr     runa
| 9: clear all: refill
        moveq   #9,d0
        movec   d0,cacr
        move.w  #9,0x3600
        bsr     runa
| 10: user mode: the supervisor entries do not hit (tag FC2)
        lea     0x6800,a0
        move.l  a0,usp
        move.w  #0x0000,sr
        move.w  #10,0x3600
        bsr     runa
        trap    #0                      | back to supervisor
| 11: supervisor again: the user fill replaced the line
        move.w  #11,0x3600
        bsr     runa
| 12/13: CDIS asserted: no hits; negated: the contents were kept
        move.w  #1,0x3500
        move.w  #12,0x3600
        bsr     runa
        move.w  #0,0x3500
        move.w  #13,0x3600
        bsr     runa
| 14: no snooping: code in RAM $8000 rewritten, the old code runs until CI
        move.w  #14,0x3600
        moveq   #9,d0
        movec   d0,cacr
        move.l  #0x70014e75,0x8040      | moveq #1,d0; rts
        jsr     0x8040
        move.l  d0,(a4)+
        move.l  #0x70024e75,0x8040      | moveq #2,d0; rts
        jsr     0x8040
        move.l  d0,(a4)+                | CIMODE=1: 1 (stale), CIMODE=0: 2
        moveq   #9,d0
        movec   d0,cacr
        jsr     0x8040
        move.l  d0,(a4)+                | 2
| 15: CACR read-back
        move.w  #15,0x3600
        moveq   #-1,d0
        movec   d0,cacr
        movec   cacr,d1
        move.l  d1,(a4)+                | $3313
| 16: loop at 4n+2, entered by a branch (F62 misaligned stream): its first long word
| is never read in full, so each pass refetches it (2 cycles); the rest hits
        moveq   #9,d0
        movec   d0,cacr
        move.w  #16,0x3600
        moveq   #8,d1
        jmp     lpc
ret16:
| 17: loop at 4n+2 entered from the aligned word before it: the long is filled, no refetch
        move.w  #17,0x3600
        moveq   #8,d1
        jmp     lpd0
ret17:
| 18: same loop as 16, EI off (reference)
        moveq   #0,d0
        movec   d0,cacr
        move.w  #18,0x3600
        moveq   #8,d1
        jmp     lpc
| 19: a bus error on a cacheable prefetch fills nothing: the second jump faults again
retc:   move.w  #19,0x3600
        moveq   #9,d0
        movec   d0,cacr
        move.l  #berrh,0x08
        moveq   #0,d6
        movea.l sp,a3
        lea     4f,a2
        jmp     0x20000
4:      lea     5f,a2
        jmp     0x20000
5:      move.l  #errh,0x08
        move.l  d6,(a4)+                | 2
| 21-25: CIIN is per bus cycle and only stops fills (MC68030UM 5.7.1, 6.1): with CIIN asserted on
| every cycle (tb $3502), loop A filled before still hits; loop B is never filled; after CIIN is
| negated again loop B fills on its first pass
        moveq   #9,d0
        movec   d0,cacr
        move.w  #21,0x3600
        bsr     runa
        move.w  #1,0x3502
        move.w  #22,0x3600
        bsr     runa
        move.w  #23,0x3600
        bsr     runb
        move.w  #24,0x3600
        bsr     runb
        move.w  #0,0x3502
        move.w  #25,0x3600
        bsr     runb
        moveq   #0,d0
        movec   d0,cacr
        move.w  #20,0x3600
        move.l  #0x600DC0DE,0x3300
2:      bra.s   2b

runa:   moveq   #8,d1
        jmp     lpa
runb:   moveq   #8,d1
        jmp     lpb
berrh:  addq.l  #1,d6
        movea.l a3,sp
        jmp     (a2)
trh:    ori.w   #0x2000,(sp)
        rte
errh:   move.l  #0xEEEE,(a4)+
        move.l  #0xBADBAD,0x3300
3:      bra.s   3b
        .org    0x10000                 | $FD0000: cacheable in CIMODE=1, line 0
lpa:    subq.l  #1,d1
        bne.s   lpa
        rts
        .org    0x10020                 | line 2
lpb:    subq.l  #1,d1
        bne.s   lpb
        rts
        .org    0x10042                 | line 4, 4n+2
lpc:    subq.l  #1,d1
        bne.s   lpc
        movec   cacr,d0
        tst.l   d0
        bne.s   1f
        jmp     retc
1:      jmp     ret16
        .org    0x10080                 | line 8
lpd0:   nop
lpd:    subq.l  #1,d1                   | 4n+2
        bne.s   lpd
        jmp     ret17
