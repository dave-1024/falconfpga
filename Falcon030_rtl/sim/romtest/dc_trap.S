| BLI-11g: exception stack frame writes vs cached stack, RTE from cached frame
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
    move.l  #0x10A14+(htrap-cstart),0x80.w
    move.l  #0x10A14+(hbad-cstart),0x10.w
    move.l  #0x10A14+(hbad-cstart),0x0C.w
    move.l  #0x10A14+(hbad-cstart),0x08.w
    lea     0x3000,%a5
    moveq   #15,%d5
L:  lea     -16(%sp),%a0
    movem.l (%a0),%d0-%d3      | pull stale stack longs into the D-cache
    move.l  %d0,(%a5)+
    move.w  %d5,%d4
    andi.w  #0x1F,%d4
    move.w  %d4,%ccr
    trap    #0
    move.w  %sr,%d6
    move.w  %d6,(%a5)+
    move.l  %d7,(%a5)+
    dbf     %d5,L
    move.l  #2,0x404.w
2:  bra.s   2b
htrap: move.l 2(%sp),%d7      | read the stacked PC
    move.w  (%sp),%d6
    move.w  %d6,(%a5)+
    movem.l %d0-%d3,-(%sp)
    addq.l  #1,%d0
    movem.l (%sp)+,%d0-%d3
    rte
hbad: move.l #0x0BAD0BAD,0x40C.w
3:  bra.s   3b
cend:
