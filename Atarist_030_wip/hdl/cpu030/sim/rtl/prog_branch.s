| F62 branch/prefetch test: branches and jumps to odd-word (4n+2) and even-word targets,
| DBcc loop mode, exceptions, an address error, prefetch bus errors (unused and used),
| a write into the instruction stream ahead of the PC, and user mode. Results go to
| $5000.. (compare the WR log between CPU versions); DONE marker at $3300.
        .text
        .org 0
        .long   0x00008000
        .long   0x00fc0008
start:
        lea     0x5000,a4
        move.l  #berrh,0x08
        move.l  #aerrh,0x0c
        move.l  #illh,0x10
        move.l  #zdivh,0x14
        move.l  #trap0h,0x80
        move.l  #trap1h,0x84
        moveq   #0,d7
| 1. bra/bsr to odd-word and even-word targets
        bra.w   L2
        .balignw 4,0x4e71
        nop
L2:     addq.l  #1,d7
        bra.w   L3
        .balignw 4,0x4e71
L3:     addq.l  #2,d7
        bsr.w   sub_odd
        bsr.w   sub_even
        bsr.w   sub_near
        move.l  d7,(a4)+
| 2. jmp (an) and a jump table
        lea     J1,a0
        jmp     (a0)
        .balignw 4,0x4e71
        nop
J1:     addq.l  #4,d7
        moveq   #0,d6
        moveq   #3,d1
JT:     move.w  d1,d2
        add.w   d2,d2
        move.w  jtab(pc,d2.w),d2
        jmp     jtab(pc,d2.w)
jtab:   .word   jt0-jtab, jt1-jtab, jt2-jtab, jt3-jtab
jt3:    add.l   #0x3000,d6
        bra.s   jnext
        nop
jt2:    add.l   #0x200,d6
        bra.s   jnext
jt1:    add.l   #0x10,d6
        bra.s   jnext
        nop
jt0:    addq.l  #1,d6
jnext:  dbra    d1,JT
        move.l  d6,(a4)+
        move.l  d7,(a4)+
| 3. DBcc loop mode (odd-word aligned) and a longer loop
        moveq   #9,d0
        moveq   #0,d2
        bra.w   DL1
        .balignw 4,0x4e71
        nop
DL1:     add.l   d0,d2
        dbra    d0,DL1
        move.l  d2,(a4)+
        moveq   #9,d0
        moveq   #0,d3
DL2:     add.l   d0,d3
        rol.l   #1,d3
        eor.l   d0,d3
        dbra    d0,DL2
        move.l  d3,(a4)+
| 4. conditional branch chains
        moveq   #20,d0
        moveq   #0,d4
C1:     btst    #0,d0
        beq.s   C2
        addq.l  #3,d4
        bra.s   C3
C2:     subq.l  #1,d4
C3:     subq.l  #1,d0
        bne.s   C1
        move.l  d4,(a4)+
| 5. exceptions
        trap    #0
        move.l  d7,(a4)+
        illegal
        move.l  d7,(a4)+
        moveq   #0,d1
        divu    d1,d0
        move.l  d7,(a4)+
| 6. address error (jump to an odd address)
        move.l  sp,a5
        lea     AE1+1,a0
        jmp     (a0)
AE1:    move.l  d7,(a4)+
| 7. copy RAM routines: $6000 (call), $6200 (writes ahead of the PC), $FFF8, $FFFC (end of RAM)
        lea     r1s,a0
        lea     0x6000,a1
        moveq   #(r1e-r1s)/2-1,d0
1:      move.w  (a0)+,(a1)+
        dbra    d0,1b
        lea     r2s,a0
        lea     0x6200,a1
        moveq   #(r2e-r2s)/2-1,d0
2:      move.w  (a0)+,(a1)+
        dbra    d0,2b
        move.l  #0x70054e75,0xfff8      | moveq #5,d0; rts
        move.l  #0x70064e71,0xfffc      | moveq #6,d0; nop; (falls into $10000)
        jsr     0x6000
        move.l  d0,(a4)+                | 1
        move.w  #0x7002,0x6000          | moveq #2,d0
        jsr     0x6000
        move.l  d0,(a4)+                | 2
        jsr     0x6200
        move.l  d0,(a4)+                | 7 (the routine patched itself ahead of the PC)
| 8. prefetch bus error, word not used: no exception
        jsr     0xfff8
        move.l  d0,(a4)+                | 5
        move.l  d7,(a4)+
| 9. prefetch bus error, word used: bus error exception
        move.l  sp,a5
        lea     BE1,a6
        jmp     0xfffc
BE1:    move.l  d0,(a4)+                | 6
        move.l  d7,(a4)+
| 10. user mode
        lea     0x7000,a0
        move.l  a0,usp
        andi.w  #0xdfff,sr
        moveq   #4,d0
        moveq   #0,d5
U1:     addq.l  #7,d5
        bsr.s   sub_user
        dbra    d0,U1
        trap    #1
        move.l  d5,(a4)+
        move.w  sr,d0
        move.l  d0,(a4)+
        move.l  d7,(a4)+
        move.l  #0x600dc0de,0x3300
9:      bra.s   9b

sub_user:
        add.l   d5,d5
        rts
sub_near:
        add.l   #0x100,d7
        rts
        .balignw 4,0x4e71
        nop
sub_odd:
        add.l   #0x10,d7
        rts
        .balignw 4,0x4e71
sub_even:
        add.l   #0x20,d7
        rts

trap0h: addq.l  #8,d7
        rte
trap1h: or.w    #0x2000,(sp)
        rte
illh:   add.l   #0x1000,d7
        addq.l  #2,2(sp)
        rte
zdivh:  add.l   #0x2000,d7
        rte
aerrh:  add.l   #0x4000,d7
        move.w  6(sp),(a4)+
        move.l  a5,sp
        jmp     AE1
berrh:  add.l   #0x8000,d7
        move.w  6(sp),(a4)+
        move.l  2(sp),(a4)+
        move.w  10(sp),(a4)+
        move.l  a5,sp
        jmp     (a6)

r1s:    moveq   #1,d0
        rts
r1e:
r2s:    move.w  #0x7007,0x6214.w        | 6 bytes at $6200
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        moveq   #3,d0                   | at $6214
        rts
r2e:
