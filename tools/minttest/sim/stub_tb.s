| MiNT 1.19 mint030 (mint_mp2.st, MP on): MMU table build on the RTL core from Hatari PC $5A4A6
| (before the C/D-level loop that writes $BC180..; TC = 0, CRP not loaded yet), up to set_mmu at $5CE8E.
        .text
start:  move.w  #0x2700,%sr
        move.l  #0x00099518,%a0
        move.l  %a0,%usp
        move.l  #0x000BC180,%d0
        move.l  #0xF0000000,%d1
        move.l  #0x00000200,%d2
        move.l  #0x00090000,%d3
        moveq   #0,%d4
        moveq   #0,%d5
        move.l  #0x00400000,%d6
        move.l  #0x000BC180,%d7
        move.l  #0x000BC200,%a0
        move.l  #0x000BC100,%a1
        move.l  #0x000BC000,%a2
        move.l  #0x0005F29E,%a3
        move.l  #0x0002D7E4,%a4
        move.l  #0x0002D856,%a5
        move.l  #0x000BC180,%a6
        move.l  #0x0009948E,%sp
        move.w  #0x0000,-(%sp)
        move.l  #0x0005A4A6,-(%sp)
        move.w  #0x2300,-(%sp)
        rte
        .globl _start
_start = start
