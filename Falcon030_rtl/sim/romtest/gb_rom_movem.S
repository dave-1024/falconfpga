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
    movea.l 0xE00000,%a6
    lea     0xE00000,%a6
    moveq   #1,%d2
M0: move.w  #0x27,%d1
M1:
    .rept 8
    movem.l (%a6)+,%d3-%d7/%a1-%a3
    .endr
    dbra    %d1,M1
    dbra    %d2,M0
    move.l  #2,0x404.w
2:  bra.s   2b
cend:
