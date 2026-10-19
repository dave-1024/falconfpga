| [C2-C4] memory-indirect addressing regression. Pointers at $2100/$2104, data at $2200/$2300.
| Back-to-back reads (C2), JMP/JSR (C3), RMW and write-only destinations with a pointer that
| changes between uses (C4). Results at $5000.. (expect_memind.txt).
        .text
        .org 0
        .long 0x00008000
        .long 0x00fc0008
        lea 0x2000,a3
        move.l #0x2200,0x2100
        move.l #0x2300,0x2104
        move.l #0x12345678,0x2200
        move.l #0x9abcdef0,0x2204
        move.l #0x0f0e0d0c,0x2300
        move.l #0x0b0a0908,0x2304
        moveq #4,d6
| C2: back-to-back reads, the 3rd went to the stale address on an idle bus
        .balignw 4,0x4e71
        move.w ([0x100,a3]),d0
        move.w ([0x100,a3]),d1
        move.w ([0x100,a3]),d2
        move.w ([0x100,a3]),d3
        move.w ([0x100,a3],2),d4
        move.l ([0x100,a3,d6.w]),d5
        move.w d0,0x5000
        move.w d1,0x5002
        move.w d2,0x5004
        move.w d3,0x5006
        move.w d4,0x5008
        move.l d5,0x500a
        move.l ([0x100,a3],d6.w*1,4),0x500e
        add.w ([0x104,a3]),d0
        move.w d0,0x5012
| C3: JMP/JSR memory indirect, with and without outer displacement, right after a write
        move.l #t1,0x2108
        jmp ([0x108,a3])
        move.w #0xdead,0x5014
t1:     move.w #0x0001,0x5014
        move.l #t2-2,0x2108
        jsr ([0x108,a3],2)
        move.w #0x0003,0x5018
        bra.s c4
t2:     move.w #0x0002,0x5016
        rts
| C4: RMW and write-only destinations; the pointer changes between the two uses
c4:     moveq #1,d0
        sub.w d0,([0x100,a3])
        move.l #0x2300,0x2100
        sub.w d0,([0x100,a3])
        move.w 0x2200,0x501a
        move.w 0x2300,0x501c
        clr.w ([0x100,a3],2)
        move.l #0x2200,0x2100
        st ([0x100,a3],2)
        move.w 0x2302,0x501e
        move.b 0x2202,0x5020
        move.w sr,([0x104,a3],4)
        move.w 0x2304,0x5022
        move.w #0x5555,([0x100,a3])
        move.w 0x2200,0x5024
        addq.l #1,([0x100,a3])
        addq.l #1,([0x100,a3])
        move.l 0x2200,0x5026
        lea ([0x100,a3],8),a0
        pea ([0x104,a3],8)
        move.l a0,0x502a
        move.l (sp)+,0x502e
        move.l #0x600dc0de,0x3300
h:      bra.s h
