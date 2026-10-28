| MiNT 1.19 mint030 (mint_mp2.st, MP on) restart on the RTL core just after the FAT/VFAT banner
| (Hatari snapshot at PC $466F2, after Dgetdrv, VBL 8905). Registers, CRP and TC from Hatari.
        .text
start:  move.w  #0x2700,%sr
        move.l  #0x00099518,%a0
        move.l  %a0,%usp
        lea     crpv(%pc),%a0
        pmove   (%a0),%crp
        lea     tcv(%pc),%a0
        pmove   (%a0),%tc
        move.l  #0x00000000,%d0
        move.l  #0x0000001F,%d1
        move.l  #0x00000020,%d2
        move.l  #0x0009001F,%d3
        move.l  #0x0009643E,%d4
        moveq   #0,%d5
        moveq   #0,%d6
        moveq   #0,%d7
        move.l  #0x0008BE3A,%a0
        move.l  #0x0008BE3A,%a1
        move.l  #0x0009950E,%a2
        move.l  #0x00056B82,%a3
        move.l  #0x0002C36C,%a4
        move.l  #0x0009643E,%a5
        move.l  #0x0005F29E,%a6
        move.l  #0x000994F0,%sp
        move.w  #0x0000,-(%sp)
        move.l  #0x000466F2,-(%sp)
        move.w  #0x2300,-(%sp)
        rte
        .even
crpv:   .long   0x7fff0003,0x000bc000
tcv:    .long   0x80d04447
        .globl _start
_start = start
