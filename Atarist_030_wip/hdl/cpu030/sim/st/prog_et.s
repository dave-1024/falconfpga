| EmuTOS 1.4 TT-RAM probe replica (memory.S detect_32bit_address_bus + memory2.c detect_ttram_size)
| Results: $1300 is_bus32, $1304 ttram size, $1308 bus errors, $1ffc done
        .text
        .long   0x00008000
        .long   start
start:  move.w  #0x2700,%sr
        lea     0x8000,%sp
        move.b  #0x0a,0xffff8001.w
        clr.l   0x1308.w
| detect_32bit_address_bus
        move.l  %sp,%a2
        lea     busdet(%pc),%a0
        move.l  %a0,0x8.w
        lea     0x0000000c.w,%a3
        lea     0x0100000c,%a4
        move.l  #0x12345678,%d2
        move.l  %d2,(%a3)
        cmp.l   (%a4),%d2
        bne.s   busdet
        not.l   %d2
        move.l  %d2,(%a3)
        cmp.l   (%a4),%d2
        bne.s   busdet
        moveq   #0,%d0
        bra.s   enddet
busdet: moveq   #1,%d0
enddet: move.l  %a2,%sp
        move.l  %d0,0x1300.w
| detect_ttram_size
        lea     berr(%pc),%a0
        move.l  %a0,0x8.w
        move.l  #0x010fffff,%a1
1:      move.l  %sp,%a5
        tst.b   (%a1)
        move.b  #0x12,(%a1)
        move.b  #0x34,-1(%a1)
        cmp.b   #0x12,(%a1)
        bne.s   2f
        cmp.b   #0x34,-1(%a1)
        bne.s   2f
        add.l   #0x100000,%a1
        bra.s   1b
berr:   addq.l  #1,0x1308.w
        move.l  %a5,%sp
2:      move.l  %a1,%d0
        and.l   #0xfff00000,%d0
        sub.l   #0x01000000,%d0
        move.l  %d0,0x1304.w
        move.l  #0x600dc0de,0x1ffc.w
9:      bra.s   9b
