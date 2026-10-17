| [FAULT] Data bus error timing and frame format (FAULT_FIXES.md). Each case faults on $20000+ (BERR in tb030),
| the handler copies format/vector, SSW, fault address, DOB, PC, SR to $5000+ and resumes at (a2).
| After a faulting write the next instruction reads a marker address $4xx0: with fix 1 that read must not appear on
| the bus before the exception stacking (checked in the bus log by fault_chk.sh).
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
| 1: word write fault, last cycle of the instruction, next instruction reads $4010
        lea     1f(pc),a2
        move.w  d1,0x20000
        move.l  0x4010,d3
1:      move.l  d3,(a4)+
| 2: long write fault, next instruction is register-only, then a read of $4020
        lea     1f(pc),a2
        move.l  d0,0x20004
        moveq   #5,d4
        move.l  0x4020,d3
1:      move.l  d4,(a4)+
| 3: read-modify-write (addq to memory) faulting on the read: long frame
        lea     1f(pc),a2
        addq.w  #1,0x20008
        move.l  0x4030,d3
1:
| 4: plain read fault: long frame
        lea     1f(pc),a2
        move.l  0x2000c,d3
        move.l  0x4040,d3
1:
| 5: movem write into the BERR area, fault on the 2nd of 3 writes (RAM ends at $10000): long frame
        lea     1f(pc),a2
        lea     0xfffc,a0
        movem.l d0-d2,(a0)
        move.l  0x4050,d3
1:      move.l  0xfffc,(a4)+
| 6: push then a faulting write from a postincrement source (read ok, write faults), next reads $4060
        lea     1f(pc),a2
        lea     0x3000,a1
        move.l  d2,(a1)
        move.l  (a1)+,0x20010
        move.l  0x4060,d3
1:      move.l  a1,(a4)+
| 7: clr to the BERR area (write only)
        lea     1f(pc),a2
        clr.w   0x20014
        move.l  0x4070,d3
1:
        move.l  d7,(a4)+
        move.l  #0x600dc0de,0x3300
2:      bra.s   2b
berr:   addq.l  #1,d7
        move.w  6(sp),(a4)+             | format/vector
        move.w  10(sp),(a4)+            | SSW
        move.l  16(sp),(a4)+            | fault address
        move.l  24(sp),(a4)+            | DOB
        move.l  2(sp),(a4)+             | PC
        move.w  (sp),(a4)+              | SR
        movea.l a6,sp
        jmp     (a2)
