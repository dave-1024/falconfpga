| prog_spr: TTM1's own text (N reduced) copied to its board address 01000104, main called with SP=01FFFFF0
        .text
        .long   0x0100FFF0
        .long   start
start:  move.w  #0x2700,%sr
        lea     bios(%pc),%a0
        move.l  %a0,0xb4.w
        lea     ttm(%pc),%a0
        lea     0x01000104,%a1
        move.w  #(ttmend-ttm)/2-1,%d0
1:      move.w  (%a0)+,(%a1)+
        dbra    %d0,1b
        move.l  #0x01FFFFF4,%sp
        move.l  #0x01FFFFC6,%a6
        jsr     0x01000124
        move.l  %sp,0x1ff8.w
        move.l  #0x600dc0de,0x1ffc.w
9:      bra.s   9b
bios:   movem.l %d0-%d2/%a0-%a2,-(%sp)
        move.w  36(%sp),%d0
        move.l  0x3ff8,%a1
        cmp.l   #0x4000,%a1
        bcc.s   1f
        lea     0x4000,%a1
1:      move.b  %d0,(%a1)+
        move.l  %a1,0x3ff8
        movem.l (%sp)+,%d0-%d2/%a0-%a2
        rte
        .even
ttm:    .incbin "/workspace/ttram_repo/Atarist_030_wip/hdl/cpu030/sim/st/ttm1_small.bin"
ttmend:
