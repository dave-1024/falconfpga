| BLI-11g: CACR CD clear vs cached lines and pending fills. A MOVES write with FC=1 changes memory behind
| an FC=5 entry (no update, as the 68030: tags include FC); after CD the FC=5 read must see memory.
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
    lea     0x3000,%a5
    lea     0x2000,%a0
    moveq   #1,%d0
    movec   %d0,%dfc
    moveq   #7,%d5
L:  move.l  %d5,(%a0)
    move.l  #0x11112222,4(%a0)
    move.w  2(%a0),%d1          | word read: fill pending for the other word
    move.l  (%a0),%d1           | FC=5 entry now valid
    move.l  #0xABCD0000,%d2
    add.l   %d5,%d2
    moves.l %d2,(%a0)           | FC=1 write: memory changes, FC=5 entry not updated
    move.w  6(%a0),%d3          | word read with fill, then flush straight away
    movec   %cacr,%d0
    bset    #11,%d0
    movec   %d0,%cacr
    move.l  (%a0),(%a5)+        | must be $ABCD000n
    move.l  4(%a0),(%a5)+
    dbf     %d5,L
    move.l  #2,0x404.w
2:  bra.s   2b
cend:
