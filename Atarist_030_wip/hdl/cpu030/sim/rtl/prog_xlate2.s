| [PMMU2c] Long-format tables, limits, indirect descriptors, S pages and SRE (MC68030UM 9.5.1 pp9-20..28,
| 9.5.3, 9.5.5, Table 9-2). Run with ST=1 (4 MB RAM). TC = $82C84800: SRE, PS 4K, IS 8, TIA 4, TIB 8.
| Supervisor tree (SRP, DT 3): long table A at $6000; A[0] -> long table B at $6100 with upper limit $0F;
|   A[$F] long early-termination page $F00000. B[n] = identity, B[$A] -> $C000.
| User tree (CRP, DT 3): long table A' at $7000; A'[0] -> long table B' at $7100 (no limit);
|   A'[$F] page $F00000. B'[n] identity, B'[4] = indirect (DT 3) -> long page descriptor at $7900 (-> $C000),
|   B'[8] page with S = 1 (supervisor only).
        .text
        .org 0
        .long   0x00008000
        .long   0x00fc0008
start:
        move.l  #berr,0x08
        move.l  #trap0,0x80
        clr.w   0x5100
        clr.l   0x400c
        lea     0x5000,a4
| tables: d1 = page, a0 = table
        lea     0x6000,a0               | A: 16 long, invalid
        moveq   #31,d0
1:      clr.l   (a0)+
        dbf     d0,1b
        lea     0x7000,a0
        moveq   #31,d0
2:      clr.l   (a0)+
        dbf     d0,2b
        move.l  #0x000f0003,0x6000      | A[0]: L/U 0, LIMIT $0F, DT 3 (long table)
        move.l  #0x00006100,0x6004
        move.l  #0x80800003,0x6008      | A[1]: L/U 1 (lower limit), LIMIT $80 -> table B
        move.l  #0x00006100,0x600c
        move.l  #0x000f0002,0x6010      | A[2]: long descriptor, LIMIT $0F, DT 2: next table is SHORT ($6900)
        move.l  #0x00006900,0x6014
        move.l  #0x7fff0001,0x6078      | A[$F]: page (early termination)
        move.l  #0x00f00000,0x607c
        move.l  #0x7fff0003,0x7000      | A'[0]: long table, no limit
        move.l  #0x00007100,0x7004
        move.l  #0x7fff0001,0x7078
        move.l  #0x00f00000,0x707c
        lea     0x6100,a0               | B and B': 16 identity long pages, rest invalid
        lea     0x7100,a1
        moveq   #0,d1
        move.l  #255,d0
3:      cmp.l   #0x10000,d1
        bcc.s   4f
        move.l  #0x7fff0001,(a0)+
        move.l  d1,(a0)+
        move.l  #0x7fff0001,(a1)+
        move.l  d1,(a1)+
        bra.s   5f
4:      clr.l   (a0)+
        clr.l   (a0)+
        clr.l   (a1)+
        clr.l   (a1)+
5:      add.l   #0x1000,d1
        dbf     d0,3b
        move.l  #0x0000c000,0x6154      | B[$A] -> $C000
        move.l  #0x00000003,0x7120      | B'[4]: indirect, DT 3 (to a long descriptor)
        move.l  #0x00007900,0x7124
        move.l  #0x7fff0001,0x7900      | its page: $C000
        move.l  #0x0000c000,0x7904
        move.l  #0x7fff0101,0x7140      | B'[8]: S = 1
        move.l  #0x0000cafe,0xc000
        move.l  #0x7fff0003,0x4000      | SRP
        move.l  #0x00006000,0x4004
        pmove   0x4000,srp
        move.l  #0x7fff0003,0x4010      | CRP
        move.l  #0x00007000,0x4014
        pmove   0x4010,crp
        move.l  #0x82c84800,0x4008
        pmove   0x4008,tc
| supervisor: long tree
        move.w  0xa002,(a4)+            | -> $CAFE
| limit: TIB index $10 > LIMIT $0F -> bus error (handler: TC off, rerun)
        move.w  0x10000,(a4)+           | -> $0000 (physical $10000 after the rerun)
        pmove   0x4008,tc
| PTEST from supervisor mode with user FCs
        ptestr  #1,0x4000,#7
        pmove   psr,(a4)+               | indirect: N = 3 -> $0003
        ptestr  #1,0x8000,#7
        pmove   psr,(a4)+               | S page, user FC: S, N = 2 -> $2002
        ptestr  #5,0x10000,#7
        pmove   psr,(a4)+               | limit: L, I, N = 1 -> $4401
        ptestr  #5,0x8000,#7
        pmove   psr,(a4)+               | supervisor tree, no S: N = 2 -> $0002
        ptestr  #5,0x17f000,#7
        pmove   psr,(a4)+               | lower limit: index $7F < $80: L, I, N = 1 -> $4401
        ptestr  #5,0x180000,#7
        pmove   psr,(a4)+               | index $80 passes the limit, B[$80] invalid: I, N = 2 -> $0402
        ptestr  #5,0x21f000,#7
        pmove   psr,(a4)+               | long descriptor's limit on a short table: L, I, N = 1 -> $4401
| user mode: CRP tree
        lea     0x7800,a2
        move.l  a2,usp
        move.w  #0x0000,sr
        move.w  0x4002,d2               | indirect -> $C000: $CAFE
        move.w  0x8000,d3               | S page -> bus error, handler: TC off, rerun
        trap    #0
        move.w  d2,(a4)+                | -> $CAFE
        move.w  d3,(a4)+                | -> $0000
        pmove   0x400c,tc
        move.l  0x7900,(a4)+            | indirect target page: U -> $7FFF0009
        move.l  0x6150,(a4)+            | B[$A]: U -> $7FFF0009
        move.w  0x5100,(a4)+            | bus errors: 2
        move.l  0x5104,(a4)+            | $00010000
        move.l  0x5108,(a4)+            | $00008000
        move.l  #0x600dc0de,0x3300
6:      bra.s   6b
berr:   move.l  a0,-(sp)
        move.l  d0,-(sp)
        move.w  0x5100,d0
        addq.w  #1,0x5100
        lea     0x5104,a0
        lsl.w   #2,d0
        move.l  8+0x10(sp),0(a0,d0.w)
        move.l  (sp)+,d0
        move.l  (sp)+,a0
        pmove   0x400c,tc
        rte
trap0:  or.w    #0x2000,(sp)
        rte
