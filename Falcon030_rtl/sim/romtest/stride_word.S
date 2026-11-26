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
    lea     0xE00000,%a1
    moveq   #2,%d2
L0: moveq   #8,%d1
    movea.l %a1,%a0
L1:
    .rept 33
    move.w  (%a0),%d0
    adda.l  #260,%a0
    .endr
    dbf     %d1,L1
    dbf     %d2,L0
    move.l  #2,0x404.w
2:  bra.s   2b
cend:
