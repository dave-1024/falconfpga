# [F157t] ADDX after a 2-clock ADD that sets X. Phase-B combinational RESULT
# used to recompute ADDX in WRITEBACK with the already-updated (cleared) X
# and write dest without the extend bit (0x10 instead of 0x11).
        .text
        .long 0x00002F00
        .long 0x00FC0008
start:  moveq #1,d7
        movec d7,cacr
        move.w #0x2700,sr
        move.l #0x00000001,d0
        move.l #0x00000002,d1
        move.l #0x00000003,d2
        move.l #0x00000004,d3
        move.l #0x00000005,d4
        move.l #0x00000006,d5
        move.l #0x00000007,d6
        move.l #0x00000008,d7
        add.l d4,d5
        add.l d6,d7
        add.l d4,d5
        add.l d6,d7
        move.l #0x80000000,d0
        move.l #0x00000000,d1
        move.l #0x00000010,d2
        add.l d0,d0
        addx.l d1,d2
        cmpi.l #0x00000011,d2
        beq.s ok
        move.w #0xDEAD,0x3400
        bra.s hang
ok:     movem.l d0-d7/a0-a6,0x5000
        move.w sr,0x5040
        move.w #0xFFFF,0x3400
hang:   bra.s hang
