| Replays FreeMiNT 1.19 mint030 set_mmu on the RTL core: RAM = Hatari snapshot at PC $5CE8E
| (pmove 12(sp),tc with CRP = $7FFF0003 000BC000 already loaded), registers from Hatari.
        .text
start:  move.w  #0x2704,sr
        move.l  #0x00099518,a0
        move.l  a0,usp
        lea     crpv,a0
        pmove   (a0),crp
        move.l  #0x0F000000,d0
        move.l  #0xFE000000,d1
        move.l  #0x00000040,d2
        move.l  #0x0009000E,d3
        move.l  #0x000BC000,d4
        move.l  #0x00000200,d5
        move.l  #0x7FFFFC0B,d6
        move.l  #0x000BC180,d7
        move.l  #0x0008D7F6,a0
        move.l  #0x0008D7F6,a1
        move.l  #0x0009AE64,a2
        move.l  #0x00059AC2,a3
        move.l  #0x0008D7CE,a4
        move.l  #0x0009B7F4,a5
        move.l  #0x000BC1A0,a6
        move.l  #0x0009947E,sp
        jmp     0x5ce8e
        .globl _start
_start = start
        .even
crpv:   .long   0x7fff0003,0x000bc000
