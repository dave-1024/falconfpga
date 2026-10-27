| [PMMU1] Stage 1 PMMU: PMOVE to/from TC, TT0, TT1, MMUSR (MC68030UM 9.7, 9.8), the TC consistency check
| (9.7.2: E is cleared when PS < 8 or IS+PS+TIx /= 32), unimplemented field masks, addressing modes,
| privilege (9.8 p. 9-65: CpID 0 F-line in user mode = privilege violation; PMOVE is privileged),
| and TT0 cache inhibit (9.3): with CACR ED set and CIMODE=1 a second read of $8000 hits the data cache,
| but with TT0 = $00FF8507 (all addresses, all FC, R and W, CI) both reads of $8010 go to the bus.
| Results are written from $5000 on; check_pmmu.py checks them and the bus reads of $8000/$8010.
        .text
        .org 0
        .long   0x00008000
        .long   0x00fc0008
start:
        move.l  #priv,0x20
        move.l  #fline,0x2c
        move.l  #trap0,0x80
        lea     0x5000,a4
        lea     0x4000,a0
        move.l  #0x12345678,(a0)
        pmove   (a0),tt0                | E=0: stored with the mask $FFFF8777
        pmove   tt0,(a4)+               | -> $12340670
        move.l  #0xffff7fff,(a0)
        pmove   (a0),tt1                | E=0
        pmove   tt1,(a4)+               | -> $FFFF0777
        move.l  #0x80c0aa00,(a0)        | E, PS=4K, IS=0, TIA=TIB=10: 12+20 = 32, valid
        pmove   (a0),tc
        pmove   tc,(a4)+                | -> $80C0AA00
        move.l  #0x80c0a000,(a0)        | 12+10 = 22: invalid, E cleared
        pmove   (a0),tc
        pmove   tc,(a4)+                | -> $00C0A000
        move.l  #0x8070ffff,(a0)        | PS=7 reserved: invalid, E cleared
        pmove   (a0),tc
        pmove   tc,(a4)+                | -> $0070FFFF
        move.l  #0xffffffff,(a0)        | TC unimplemented bits read as 0
        pmove   (a0),tc
        pmove   tc,(a4)+                | -> $03FFFFFF (E cleared: 15+15+... /= 32)
        move.w  #0xffff,(a0)
        pmove   (a0),psr
        pmove   psr,(a4)+               | -> $EE47 (word)
| addressing modes: (An)+, -(An), (d16,An), (xxx).L
        lea     0x4010,a1
        move.l  #0x00ff0000,(a1)
        move.l  #0x11228007,4(a1)
        pmove   (a1)+,tt0
        pmove   (a1)+,tt1
        move.l  a1,(a4)+                | -> $00004018
        pmove   tt1,-(a1)
        move.l  a1,(a4)+                | -> $00004014
        move.l  (a1),(a4)+              | -> $11228007
        pmove   tt0,8(a1)
        move.l  8(a1),(a4)+             | -> $00FF0000
        pmove   tt1,0x4030
        move.l  0x4030,(a4)+            | -> $11228007
| 64-bit CRP/SRP (9.7.1): two long transfers, EA and EA+4; masks $FFFF0003 / $FFFFFFF0
        move.l  #0xffffffff,(a0)
        move.l  #0xffffffff,4(a0)
        pmove   (a0),crp
        pmove   crp,0x4040
        move.l  0x4040,(a4)+            | -> $FFFF0003
        move.l  0x4044,(a4)+            | -> $FFFFFFF0
        move.l  #0x80000002,0x4050
        move.l  #0x0012345f,0x4054
        .long   0xf0394800,0x00004050   | pmove $4050.l,srp (EmuTOS style absolute long)
        lea     0x4060,a5
        pmove   srp,(a5)
        move.l  (a5)+,(a4)+             | -> $80000002
        move.l  (a5)+,(a4)+             | -> $00123450
        pmove   crp,4(a5)               | CRP unchanged by the SRP load
        move.l  4(a5),(a4)+             | -> $FFFF0003
        move.l  8(a5),(a4)+             | -> $FFFFFFF0
        .word   0xf018,0x4c00           | pmove (a0)+,crp: not yet (stage 1 deviation): F-line -> $002C
        clr.l   (a0)
        pmove   (a0),tt0
        pmove   (a0),tt1
        pmove   (a0),tc
| CpID 0 F-line that is not PMOVE (PFLUSHA $F000 $2400, stage 3): F-line trap in supervisor mode
        .word   0xf000,0x2400           | -> $002C
        .word   0xf000,0x4c00           | PMOVE Dn,CRP (Dn is not a PMOVE EA): -> $002C
| user mode: PMOVE and the other CpID 0 F-line take the privilege violation
        lea     0x7000,a2
        move.l  a2,usp
        move.w  #0x0000,sr
        pmove   tc,(a0)                 | -> $0020
        .word   0xf000,0x2400           | -> $0020
        .word   0xf200,0x5c00           | CpID 1 (FPU) in user mode: F-line -> $002C
        trap    #0                      | back to supervisor
| TT0 cache inhibit
        move.l  #0x0100,d0              | ED: data cache on
        movec   d0,cacr
        move.w  0x8000,d1
        move.w  0x8000,d1               | hit: no bus read
        move.l  #0x00ff8507,(a0)
        pmove   (a0),tt0
        move.w  0x8010,d1
        move.w  0x8010,d1               | CIOUT: read again on the bus
        move.l  #0x00ff8506,(a0)        | FC MASK 6, base 0: matches even FCs only, not 5 (supervisor data)
        pmove   (a0),tt0
        move.w  0x8020,d1
        move.w  0x8020,d1               | hit: no bus read
| TT0 CI on a write: the data cache is completely ignored, even in write-allocation mode (6.1.2 p6-8)
        clr.l   (a0)
        pmove   (a0),tt0
        move.l  #0x2100,d0              | WA + ED
        movec   d0,cacr
        move.l  #0x11111111,0x8030      | write allocates the long
        move.l  #0x00ff8507,(a0)
        pmove   (a0),tt0
        move.l  #0x22222222,0x8030      | TT CI: memory only, the cache keeps $1111
        clr.l   (a0)
        pmove   (a0),tt0
        move.w  0x8030,(a4)+            | hit: stale $1111 (the manual's stale-data case)
        move.l  #0x2900,d0              | CD: clear the data cache
        movec   d0,cacr
        move.w  0x8030,(a4)+            | from memory: $2222
        moveq   #0,d0
        movec   d0,cacr
        move.l  #0x600dc0de,0x3300
2:      bra.s   2b

priv:   move.w  6(sp),(a4)+
        addq.l  #4,2(sp)
        rte
fline:  move.w  6(sp),(a4)+
        addq.l  #4,2(sp)
        rte
trap0:  or.w    #0x2000,(sp)
        rte
