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
    moveq   #3,%d2
    lea     0x2000,%a5
C0: lea     0xE00100,%a6
    move.l  (%a6),%d0
    move.l  %d0,(%a5)+
    move.w  #7,%d1
C1: movem.l (%a6)+,%d3-%d7/%a1-%a3
    movem.l %d3-%d7/%a1-%a3,(%a5)
    lea     32(%a5),%a5
    move.l  -4(%a6),%d0
    move.l  %d0,(%a5)+
    move.w  -6(%a6),%d0
    move.w  %d0,(%a5)+
    dbra    %d1,C1
    dbra    %d2,C0
    move.l  #2,0x404.w
2:  bra.s   2b
cend:
