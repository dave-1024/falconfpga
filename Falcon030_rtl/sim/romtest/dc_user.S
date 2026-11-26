| BLI-11g: user/supervisor aliasing (MC68030UM 6.1.2 p6-8). The user program pushes a GEMDOS-style
| parameter (FC=1 write) and traps; the handler reads it through USP (FC=5 read). Tags include FC, so
| the FC=1 write misses the FC=5 line read by the previous trap: without write allocation (CACR WA)
| the handler reads the stale value. TOS 4.04 sets CACR WA ($3111) for this.
| BLI-11g: FAILS with the board setting WA_ADR_HI=1 (stale 7,7,7..); PASSES with MC68030 WA (WAHI=-1) or
| proposed_BLI11g_wa_stram.diff (WAHI=0 WALIM=14680064).
    .text
    .org 0
    .long 0x00010000
    .long 0x00E00010
    .org 0x10
    lea     0xE00100,%a0
    lea     0x10A14,%a1
    move.w  #(cend-cstart)/2-1,%d0
1:  move.w  (%a0)+,(%a1)+
    dbf     %d0,1b
    move.l  #0x3919,%d0
    movec   %d0,%cacr
    jmp     0x10A14
    .org 0x100
cstart:
    move.l  #1,0x400.w
    move.l  #0x10A14+(htrap-cstart),0x84.w
    lea     0x3000,%a5
    lea     0x5080,%a0           | $507C: D-cache line 7, away from the SSP frame at $FFF8 (line 15)
    move.l  %a0,%usp
    moveq   #7,%d5
    move.w  #0x0000,%sr         | user mode
U:  move.l  %d5,-(%sp)          | FC=1 write
    trap    #1
    addq.l  #4,%sp
    dbf     %d5,U
    trap    #1                  | d5 = -1: back to supervisor for the end marker
htrap: move.l %usp,%a0
    move.l  (%a0),%d0           | FC=5 read of the user stack
    move.l  %d0,(%a5)+
    cmp.l   #-1,%d5
    beq.s   9f
    rte
9:  move.l  #2,0x404.w
2:  bra.s   2b
cend:
