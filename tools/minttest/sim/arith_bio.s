| F87: the bio-cache resize arithmetic from MiNT (mint030 $15090..$150EC) with Hatari's operands, results to $1000.
        .text
        .globl _start
_start: lea     0x1000,%a6
        move.l  #0x00008000,0x660fe     | block size (Hatari)
        move.l  #0x00000040,0x66102
        clr.l   0x66106
        move.l  #0x80,%d0               | 15090: moveq #10,d2; lsl.l d2,d0
        moveq   #10,%d2
        lsl.l   %d2,%d0
        move.l  %d0,(%a6)+              | expect 00020000
        move.l  %d0,%d7
        .word   0x4C79,0x7007           | divul.l $660FE.l,d7 (exact encoding from mint030)
        .long   0x000660FE
        move.l  %d7,(%a6)+              | expect 00000004
        move.w  %sr,(%a6)+
        move.l  0x66102,%d0             | a3 = $40 << 3
        lsl.l   #3,%d0
        move.l  %d0,%a3
        move.l  %d7,%d1                 | (a7,$32) + $66106
        add.l   0x66106,%d1
        moveq   #0x14,%d0
        add.l   %a3,%d0
        .word   0x4C00,0x1800           | muls.l d0,d1
        move.l  %d1,(%a6)+              | expect 00000850
        move.w  %sr,(%a6)+
        move.l  %d7,%d0
        .word   0x4C39,0x0800           | muls.l $660FE.l,d0
        .long   0x000660FE
        move.l  %d0,(%a6)+              | expect 00020000
        move.l  #0x0009C000,%d0
        .word   0xE8C0,0x0704           | bftst d0{28:4}
        move.w  %sr,(%a6)+              | expect Z=1 (xxx4)
        move.l  #0x0009C008,%d0
        .word   0xE8C0,0x0704
        move.w  %sr,(%a6)+              | expect Z=0, N=1 (xxx8)
| extra forms
        move.l  #0x12345678,%d3         | divu.l #7,d3 (32/32)
        divu.l  #7,%d3
        move.l  %d3,(%a6)+              | 0299C335
        move.l  #0x00000001,%d4         | divu.l #3,d4:d5 (64/32): d4:d5 = 1:00000000
        move.l  #0x00000000,%d5
        divu.l  #3,%d4:%d5
        move.l  %d5,(%a6)+              | 55555555
        move.l  %d4,(%a6)+              | 00000001
        move.l  #-100000,%d3
        divs.l  #7,%d3
        move.l  %d3,(%a6)+              | FFFFC835
        move.l  #0x10000,%d4
        mulu.l  #0x30000,%d5:%d4        | 64-bit: 3_0000_0000
        move.l  %d4,(%a6)+              | 00000000
        move.l  %d5,(%a6)+              | 00000003
        move.l  #-3,%d4
        muls.l  #0x40000000,%d5:%d4
        move.l  %d4,(%a6)+              | 40000000
        move.l  %d5,(%a6)+              | FFFFFFFF
        move.l  #0xF0F0F0F0,%d0
        moveq   #33,%d2
        lsl.l   %d2,%d0                 | count mod 64 = 33 -> 0
        move.l  %d0,(%a6)+              | 00000000
        move.w  %sr,(%a6)+              | X=C=0? (last bit out beyond width: C=0) Z=1
        move.l  #0x80000001,%d0
        moveq   #32,%d2
        lsl.l   %d2,%d0                 | 0, C=X=1 (bit 0 shifted out last)
        move.l  %d0,(%a6)+
        move.w  %sr,(%a6)+
        move.l  #0x80000001,%d0
        moveq   #31,%d2
        asl.l   %d2,%d0
        move.l  %d0,(%a6)+              | 80000000, V=1
        move.w  %sr,(%a6)+
        move.w  #1,0x3300
1:      bra     1b
