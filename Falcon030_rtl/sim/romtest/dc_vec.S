| BLI-11g: TOS $E02CD2 pattern: read vector 8, write new vector 8, bus error -> which handler runs?
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
    move.l  #0x10A14+(hbad-cstart),0x8.w
    moveq   #3,%d5
L:  moveal  %sp,%a1
    moveal  0x8.w,%a2
    move.l  #0x10A14+(hgood-cstart),0x8.w
    tst.b   0xE80001
    move.l  #0xEEEEEEEE,0x410.w
back: moveal %a1,%sp
    move.l  %a2,0x8.w
    dbf     %d5,L
    move.l  #2,0x404.w
2:  bra.s   2b
hgood: move.l #0x600D600D,0x408.w
    bra.s   back
hbad: move.l #0x0BAD0BAD,0x40C.w
    bra.s   back
cend:
