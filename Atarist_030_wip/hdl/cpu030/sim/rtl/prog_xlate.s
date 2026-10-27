| [PMMU2b] Address translation (MC68030UM 9.4, 9.5): ATC, table search, U/M updates, faults.
| TC = $80C84800: PS 4K, IS 8, TIA 4 (A23-A20), TIB 8 (A19-A12), FCL 0, SRE 0 (9.7.2 p9-54).
| CRP: DT 2 (short), table A at $6000 (9.7.1 p9-52).
|   A[$F]: early-termination page $F00000 (9.5.3.3: ROM $FC0000 identity, 1 MB).
|   A[0]: table descriptor -> table B at $6100 (256 short page descriptors).
|   B[n]: identity for n = 0..$F except: B[$A] -> $C000, B[$B] invalid, B[$D] write protected.
| Results from $5000 on.
        .text
        .org 0
        .long   0x00008000
        .long   0x00fc0008
start:
        move.l  #berr,0x08
        clr.w   0x5100
        clr.l   0x400c
        lea     0x5000,a4
        lea     0x6000,a0               | table A: all invalid
        moveq   #15,d0
1:      clr.l   (a0)+
        dbf     d0,1b
        move.l  #0x00006102,0x6000      | A[0] -> table B, DT 2 (short)
        move.l  #0x00f00001,0x603c      | A[$F]: page, early termination
        lea     0x6100,a0               | table B
        move.l  #255,d0
        moveq   #1,d1
2:      cmp.l   #0x10001,d1
        bcc.s   3f
        move.l  d1,(a0)+
        add.l   #0x1000,d1
        dbf     d0,2b
        bra.s   4f
3:      clr.l   (a0)+
        dbf     d0,2b
4:      move.l  #0x0000c001,0x6128      | B[$A] -> $C000
        clr.l   0x612c                  | B[$B] invalid
        move.l  #0x0000d005,0x6134      | B[$D] WP
        move.l  #0x0000cafe,0xc000
        move.l  #0x00001111,0xa000
        move.l  #0x0000e0e0,0xe000
        move.l  #0x7fff0002,0x4000
        move.l  #0x00006000,0x4004
        pmove   0x4000,crp
        move.l  #0x80c84800,0x4008
        pmove   0x4008,tc               | translation on (flushes the ATC)
        move.w  0xa002,(a4)+            | -> $CAFE (logical $A000 -> physical $C000)
        move.w  #0xbeef,0xa002          | write: M set on B[$A]
        pmove   0x400c,tc               | $00000000: off
        move.w  0xc002,(a4)+            | -> $BEEF
        move.l  0x6128,(a4)+            | B[$A] -> $0000C019 (U + M)
        move.l  0x6110,(a4)+            | B[4] ($4000 data read with TC on) -> $00004009 (U)
        move.l  0x6114,(a4)+            | B[5] (results written) -> $00005019
        move.l  0x6000,(a4)+            | A[0] -> $0000610A (U)
        move.l  0x603c,(a4)+            | A[$F] -> $00F00009 (U, read only)
| ATC hit after a table change, then flush by PMOVE TC (FD = 0) (9.4 p9-17)
        pmove   0x4008,tc
        move.w  0xa002,d0               | load the ATC entry
        move.l  #0x0000e001,0x6128      | B[$A] -> $E000 (no flush)
        move.w  0xa002,(a4)+            | -> $BEEF (still the ATC entry)
        pmovefd 0x4008,tc               | FD = 1: no flush
        move.w  0xa002,(a4)+            | -> $BEEF
        pmove   0x4008,tc               | FD = 0: flush
        move.w  0xa002,(a4)+            | -> $E0E0
| invalid descriptor: bus error, handler turns translation off and the read is rerun
        moveq   #0,d3
        move.w  0xb000,d3               | B[$B] invalid -> bus error, retry with TC off
        move.w  d3,(a4)+                | -> $0000 (RAM at $B000 is zero)
| write protect: write to $D000 -> bus error
        pmove   0x4008,tc
        move.w  0xd000,d0               | read OK
        move.w  d0,(a4)+                | -> $0000
        move.w  #0x1234,0xd000          | WP -> bus error, rerun with TC off
        move.w  0xd000,(a4)+            | -> $0000: the 030 reruns a faulted write on RTE (DF, 8.2.1); this core does not yet (stage 3)
        move.w  0x5100,(a4)+            | bus errors: 2
        move.l  0x5104,(a4)+            | fault addresses: $0000B000
        move.l  0x5108,(a4)+            | $0000D000
| ATC replacement (9.4.1): 40 logical pages $10000-$37FFF all map to $C000 (B[$10..$37]), two passes over
| them with TC on: 80 reads, all must give $CAFE (entries replaced by not-recently-used, no stale or merged hit).
        pmove   0x400c,tc
        move.w  #0xcafe,0xc000
        lea     0x6140,a0
        moveq   #39,d0
6:      move.l  #0x0000c001,(a0)+
        dbf     d0,6b
        pmove   0x4008,tc
        moveq   #0,d4
        moveq   #1,d5
7:      move.l  #0x10000,a1
        moveq   #39,d0
8:      cmp.w   #0xcafe,(a1)
        bne.s   9f
        addq.w  #1,d4
9:      add.l   #0x1000,a1
        dbf     d0,8b
        dbf     d5,7b
        pmove   0x400c,tc
        move.w  d4,(a4)+                | -> $0050 (80)
        move.l  #0x600dc0de,0x3300
5:      bra.s   5b
berr:   move.l  a0,-(sp)
        move.w  0x5100,d0
        addq.w  #1,0x5100
        lea     0x5104,a0
        lsl.w   #2,d0
        move.l  4+0x10(sp),0(a0,d0.w)   | data cycle fault address (format $A/$B, +$10)
        move.l  (sp)+,a0
        pmove   0x400c,tc
        rte
