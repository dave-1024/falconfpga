| [DC] 68030 data cache unit test (docs/DCACHE_DESIGN.md §5). tb030 CIMODE=1: CIIN negated for RAM
| $8000-$FFFF and the BERR range $20000-$2FFFF; the code ($FC0000), the results ($5080, lines 8-11),
| the stack ($7000) and the tb controls ($35xx) are not cachable. The test lines are 2-7 ($8020-$807F)
| and their aliases at $8120-$817F / $20020 (same index, other tag). RAM $8000-$81FF holds its own
| address in every long word. Each case writes its number to $36C0 (line 12), then runs its reads and
| writes; check_dcache.py counts the data read and write cycles at $8000-$FFFF/$20000-$2FFFF per case.
| The tb controls are written with WA clear: with WA set a word write miss clears a valid bit (6.1.2.1).
        .text
        .org 0
        .long   0x00007000
        .long   0x00fc0008
start:
        lea     0x5080,a4
        lea     0x08,a0
        moveq   #9,d0
1:      move.l  #errh,(a0)+
        dbra    d0,1b
        move.l  #berrh,0x08
        move.l  #trh,0x80
        moveq   #0,d6
        moveq   #0,d0
        movec   d0,cacr
        lea     0x8000,a0
        move.w  #127,d0
1:      move.l  a0,(a0)+
        dbra    d0,1b
| 1: ED off: every read is a bus read
        move.w  #1,0x36c0
        move.l  0x8020,d0
        move.l  0x8020,d0
        move.l  0x8020,d0
| 2: CD + ED: the first read fills (two words), then hits
        move.l  #0x900,d0
        movec   d0,cacr
        move.w  #2,0x36c0
        move.l  0x8020,d0
        move.l  0x8020,d0
        move.l  0x8020,d0
        move.l  d0,(a4)+
| 3: byte at $8033: the byte cycle ($8032 word), a fill cycle at $8030 (Figure 6-6), then hits
        move.w  #3,0x36c0
        moveq   #0,d0
        move.b  0x8033,d0
        move.b  0x8033,d0
        move.b  0x8033,d0
        move.l  0x8030,d1
        move.l  d0,(a4)+
        move.l  d1,(a4)+
| 4: misaligned long at $8046: $8046, $8048, fills $8044, $804A (Figure 6-9), then hits on both entries
        move.w  #4,0x36c0
        move.l  0x8046,d0
        move.l  0x8046,d0
        move.l  0x8044,d1
        move.l  0x8048,d2
        move.l  d0,(a4)+
        move.l  d1,(a4)+
        move.l  d2,(a4)+
| 5: write-through: a write hit goes to the bus and updates the cache
        move.w  #5,0x36c0
        move.w  #0xbeef,0x8022
        move.l  0x8020,d0
        move.l  d0,(a4)+
| 6: WA = 0: a write miss leaves the cache alone (the next read misses and fills)
        move.w  #6,0x36c0
        move.l  #0x12345678,0x8050
        move.l  0x8050,d0
        move.l  0x8050,d0
        move.l  d0,(a4)+
| 7: WA = 1: aligned long write misses allocate; a tag miss replaces the tag, the line's others invalid
        move.l  #0x2100,d0
        movec   d0,cacr
        move.w  #7,0x36c0
        move.l  #0xcafef00d,0x8058
        move.l  0x8058,d0
        move.l  #0x0badf00d,0x8158
        move.l  0x8158,d1
        move.l  0x8050,d2
        move.l  d0,(a4)+
        move.l  d1,(a4)+
        move.l  d2,(a4)+
| 8: WA = 1: a word write miss (alias $8160) clears the valid bit of the entry ($8060 refetched)
        move.w  #8,0x36c0
        move.l  0x8060,d0
        move.w  #0x1111,0x8160
        move.l  0x8060,d0
        move.l  d0,(a4)+
| 9: WA = 0: the same word write miss changes nothing ($8064 still hits)
        move.l  #0x100,d0
        movec   d0,cacr
        move.w  #9,0x36c0
        move.l  0x8064,d0
        move.w  #0x2222,0x8164
        move.l  0x8064,d0
        move.l  d0,(a4)+
| 10: FD: a read miss does not fill; a write hit still updates
        move.l  #0x300,d0
        movec   d0,cacr
        move.w  #10,0x36c0
        move.l  0x8070,d0
        move.l  0x8070,d0
        move.w  #0x3333,0x8020
        move.l  0x8020,d1
        move.l  d1,(a4)+
| 11: CED with CAAR = $8020: only that long word is cleared
        move.l  #0x100,d0
        movec   d0,cacr
        lea     0x8020,a0
        movec   a0,caar
        move.l  #0x500,d0
        movec   d0,cacr
        move.w  #11,0x36c0
        move.l  0x8020,d0
        move.l  0x8030,d1
        move.l  d0,(a4)+
| 12: ED off: no hits; ED on again: the entries were kept
        moveq   #0,d0
        movec   d0,cacr
        move.w  #12,0x36c0
        move.l  0x8030,d0
        move.l  #0x100,d0
        movec   d0,cacr
        move.l  0x8030,d0
| 13: CDIS asserted: no hits; negated: kept
        move.w  #1,0x3500
        move.w  #13,0x36c0
        move.l  0x8030,d0
        move.w  #0,0x3500
        move.l  0x8030,d0
| 14: FC is in the tag: user data (FC 1) misses the supervisor entry, fills, hits; supervisor misses again
        lea     0x6800,a0
        move.l  a0,usp
        move.w  #14,0x36c0
        move.w  #0x0000,sr
        move.l  0x8030,d0
        move.l  0x8030,d0
        trap    #0
        move.l  0x8030,d0
| 15: CIIN asserted on every cycle (tb $3502): hits still work, misses do not fill, WA writes allocate
        move.w  #15,0x36c0
        move.w  #1,0x3502
        move.l  0x8030,d0
        move.l  0x8070,d0
        move.l  0x8070,d0
        move.l  #0x2100,d0
        movec   d0,cacr
        move.l  #0x77777777,0x8078
        move.l  0x8078,d1
        move.l  #0x100,d0
        movec   d0,cacr
        move.w  #0,0x3502
        move.l  d1,(a4)+
| 16: TAS: the read is forced to miss, the write updates the entry
        move.w  #16,0x36c0
        tas     0x8031
        move.l  0x8030,d0
        move.l  d0,(a4)+
| 17: CAS.L: the read is forced to miss, the write updates the entry
        move.w  #17,0x36c0
        move.l  0x8030,d1
        move.l  #0x55555555,d2
        cas.l   d1,d2,0x8030
        move.l  0x8030,d0
        move.l  d0,(a4)+
| 18: bus error on the operand (cachable $20020): an exception each time, no entry; the read cleared
|     the valid bit of the indexed entry ($8020, refetched)
        move.w  #18,0x36c0
        lea     0x20020,a0
        lea     1f,a2
        movea.l sp,a3
        move.l  (a0),d0
1:      lea     1f,a2
        move.l  (a0),d0
1:      move.l  0x8020,d0
        move.l  d6,(a4)+
| 19: bus error on a fill-only cycle ($8042): no exception, the entry stays invalid
        move.w  #0x8042,0x3504
        move.w  #19,0x36c0
        moveq   #0,d0
        lea     9f,a2
        movea.l sp,a3
        move.b  0x8041,d0
        move.b  0x8041,d0
        move.w  #0,0x3504
        move.l  d0,(a4)+
        move.l  d6,(a4)+
| 20: CPU space (MOVES, SFC = 7) is never cached
        moveq   #7,d0
        movec   d0,sfc
        move.w  #20,0x36c0
        moves.l 0x8030,d1
        moves.l 0x8030,d1
| 21: MOVES with SFC = 1: user data, cached with that FC
        moveq   #1,d0
        movec   d0,sfc
        move.w  #21,0x36c0
        moves.l 0x8074,d1
        moves.l 0x8074,d1
        move.l  d1,(a4)+
| 22: WA = 1, misaligned long write: E0 ($8030) hit updated, E1 ($8034) miss invalid; the long read
|     misses on E1 and refills both entries (operand $8032, $8034, fills $8030, $8036)
        move.l  #0x2100,d0
        movec   d0,cacr
        move.w  #22,0x36c0
        move.l  #0xa1b2c3d4,0x8032
        move.l  #0x100,d0
        movec   d0,cacr
        move.w  0x8032,d0
        move.l  0x8032,d1
        move.l  0x8034,d2
        move.l  d0,(a4)+
        move.l  d1,(a4)+
        move.l  d2,(a4)+
| 23: CD clears every entry
        move.l  #0x900,d0
        movec   d0,cacr
        move.w  #23,0x36c0
        move.l  0x8030,d0
| 24: CACR read-back (CD, CED read as zero)
        move.w  #24,0x36c0
        movec   cacr,d0
        move.l  d0,(a4)+
        moveq   #0,d0
        movec   d0,cacr
        move.w  #25,0x36c0
        move.l  #0x600DC0DE,0x3300
2:      bra.s   2b
9:      move.l  #0xDEAD0019,(a4)+       | case 19 must not take an exception
        move.l  #0xBADBAD,0x3300
3:      bra.s   3b
berrh:  addq.l  #1,d6
        movea.l a3,sp
        jmp     (a2)
trh:    ori.w   #0x2000,(sp)
        rte
errh:   move.l  #0xEEEE,(a4)+
        move.l  #0xBADBAD,0x3300
3:      bra.s   3b
