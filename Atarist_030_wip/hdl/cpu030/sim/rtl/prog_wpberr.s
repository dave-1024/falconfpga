| [PH2-WP] Posted writes and bus errors on writes (option b). A write that bus-errors is never
| posted; posted RAM writes right before it must not change its frame. Each case runs a RAM
| write followed by a faulting write to $20000 (BERR in tb030) or across the RAM end ($10000).
| The handler copies the frame (format/vector, SSW, fault address, DOB, PC, SR) to $5000+,
| restores SP and resumes at (a2). cmp_wr.sh against the pre-posting core must give SAME.
        .text
        .org 0
        .long   0x00008000
        .long   0x00fc0008
start:
        move.l  #berr,0x08
        lea     0x5000,a4
        movea.l sp,a6
        moveq   #0,d7
        lea     0x3000,a3
        move.l  #0x11112222,d0
        move.l  #0x33334444,d1
        move.l  #0x55556666,d2
        move.l  #0x77778888,d3
| 1: posted long write, then word write fault
        lea     1f(pc),a2
        move.l  d0,(a3)
        move.w  d1,0x20000
1:      move.l  (a3),(a4)+
| 2: byte write fault after a posted byte write
        lea     1f(pc),a2
        move.b  d2,(a3)
        move.b  d3,0x20001
1:
| 3: long write fault on its first portion
        lea     1f(pc),a2
        move.w  d0,(a3)
        move.l  d2,0x20000
1:
| 4: long write across the RAM end: first portion posted? no (not last); second faults
        lea     1f(pc),a2
        move.l  d3,0xfffe
1:      move.w  0xfffe,(a4)+
| 5: movem to RAM running into the BERR area: two posted writes, then a fault
        lea     1f(pc),a2
        lea     0xfff8,a0
        movem.l d0-d3,(a0)
1:      move.l  0xfff8,(a4)+
        move.l  0xfffc,(a4)+
| 6: movem predecrement from the BERR area down
        lea     1f(pc),a2
        lea     0x20008,a0
        movem.l d0-d1,-(a0)
1:      move.l  a0,(a4)+
| 7: push sequence then a faulting write
        lea     1f(pc),a2
        move.l  d0,-(sp)
        move.l  d1,-(sp)
        move.w  d2,0x20002
1:
| 8: clr (read-free write) and addq to memory (read then write) faulting
        lea     1f(pc),a2
        clr.l   0x20004
1:      lea     1f(pc),a2
        addq.w  #1,0x20006
1:
| 9: posted write chain without fault, results checked
        move.l  d0,(a3)+
        move.l  d1,(a3)+
        move.w  d2,(a3)+
        move.b  d3,(a3)+
        lea     0x3000,a3
        move.l  (a3)+,(a4)+
        move.l  (a3)+,(a4)+
        move.l  (a3)+,(a4)+
        move.l  d7,(a4)+
        move.l  #0x444f4e45,0x3300
2:      bra     2b
berr:   addq.l  #1,d7
        move.w  6(sp),(a4)+             | format/vector
        move.w  10(sp),(a4)+            | SSW
        move.l  16(sp),(a4)+            | fault address
        move.l  24(sp),(a4)+            | DOB
        move.l  2(sp),(a4)+             | PC
        move.w  (sp),(a4)+              | SR
        movea.l a6,sp
        jmp     (a2)
