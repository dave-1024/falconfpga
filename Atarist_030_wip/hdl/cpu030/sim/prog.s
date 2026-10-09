| 68030 bridge unit test program, ROM at $FC0000
        .text
        .org 0
        .long   0x00001000              | initial SSP
        .long   0x00fc0008              | initial PC
start:
        move.w  #0x2700,sr
        move.l  #0x12345678,d0
        move.l  d0,0x2000               | long write -> 2 word writes
        move.w  #0xabcd,0x2004          | word write
        move.b  #0x11,0x2006            | even byte write
        move.b  #0x22,0x2007            | odd byte write
        move.l  0x2000,d1               | long read
        move.w  0x2004,d2               | word read
        move.b  0x2006,d3               | even byte read
        move.b  0x2007,d4               | odd byte read
        move.l  #0xa5a55a5a,0x2009      | misaligned long write
        move.l  0x2009,d5               | misaligned long read
        move.w  0xfc0000,d6             | ROM word read
        movem.l d0-d6,0x3000
        move.b  0xfffc00,d0             | ACIA status read (VPA/E)
        move.b  d0,0x3100
        move.b  #0x96,0xfffc02          | ACIA data write (VPA/E)
        move.l  #berr_handler,0x8
        move.w  0xf00000,d0             | nothing there -> BERR
back_from_berr:
        move.l  #vbl_handler,0x70       | level 4 autovector
        move.l  #mfp_handler,0x118      | MFP vector 0x46
        move.b  #1,0x3400               | tell the bench: raise IPLs
        move.w  #0x2300,sr
wait:   move.b  0x3201,d0
        and.b   0x3202,d0
        beq.s   wait
        move.w  #0x2700,sr
        move.l  0x3000,d7
        move.l  #0x600dc0de,0x3300      | done marker
halt:   bra.s   halt

berr_handler:
        move.b  #1,0x3104
        move.w  (6,sp),0x3106           | frame format/vector offset
        lea     0x1000,sp
        jmp     back_from_berr

vbl_handler:
        move.b  #1,0x3201
        rte
mfp_handler:
        move.b  #1,0x3202
        rte
