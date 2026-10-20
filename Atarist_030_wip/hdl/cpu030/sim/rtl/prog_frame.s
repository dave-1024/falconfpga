| [FRAME] Bus-error frame contents (MC68030UM 8.1.2, 8.2, Figures 8-7/8-8): SSW FC/FB/RC/RB/DF and the stage C
| ($0C) / stage B ($0E) images, which must hold the words at PC+2 / PC+4 of the stacked PC.
| The code under test runs in RAM; tb030 makes reads of one RAM word bus-error (word write to $3504), so the
| handler can repair the fault and RTE re-runs the faulted prefetch or data read.
| Per case the handler stores: format/vector, SSW, $0C, $0E, PC (long); the case then stores its result register.
        .text
        .org 0
        .long   0x00008000
        .long   0x00fc0008
start:
        move.l  #berr,0x08
        lea     0x5000,a4
        moveq   #0,d7
| code images in RAM
        move.l  #0x4e71303c,0x6100      | 6100 nop;  6102 move.w #$1234,d0
        move.l  #0x12344e75,0x6104      | 6104 (ext, faults: stage C);  6106 rts
        move.l  #0x203c1122,0x6200      | 6200 move.l #$11223344,d0
        move.l  #0x33444e75,0x6204      | 6204 (2nd ext, faults: stage B);  6206 rts
        move.l  #0x36107212,0x6300      | 6300 move.w (a0),d3;  6302 moveq #$12,d1
        move.l  #0x74344e75,0x6304      | 6304 moveq #$34,d2;  6306 rts
        move.l  #0x36390000,0x6320      | 6320 move.w $6400,d3 (abs.l)
        move.l  #0x64007212,0x6324      | 6324 ;  6326 moveq #$12,d1
        move.w  #0x4e75,0x6328
        move.l  #0x32817212,0x6500      | 6500 move.w d1,(a1) (faults: write);  6502 moveq #$12,d1
        move.l  #0x74344e75,0x6504
        move.l  #0x4e717007,0x6600      | 6600 nop;  6602 moveq #7,d0 (opcode word faults)
        move.l  #0x4e754e71,0x6604
        move.w  #0xabcd,0x6400
        moveq   #0,d6                   | d6=0: the handler repairs and RTEs
| 1. stage C fault (ext word at $6104), PC = $6102 (4n+2): FC RC set; RTE re-runs the prefetch
        moveq   #0,d0
        move.w  #0x6104,0x3504
        jsr     0x6100
        move.l  d0,(a4)+
| 2. stage B fault (2nd ext word at $6204), PC = $6200: FB RB set, stage C = $1122
        moveq   #0,d0
        move.w  #0x6204,0x3504
        jsr     0x6200
        move.l  d0,(a4)+
| 3. data read fault, one-word instruction: stage C/B = the next two opcodes ($7212, $7434); RTE re-runs the read
        lea     0x6400,a0
        moveq   #0,d3
        move.w  #0x6400,0x3504
        jsr     0x6300
        move.l  d3,(a4)+
| 4. data read fault, three-word instruction (abs.l): stage C/B = $0000/$6400
        moveq   #0,d3
        move.w  #0x6400,0x3504
        jsr     0x6320
        move.l  d3,(a4)+
| 5. opcode word fault ($6602): RTE re-runs it
        moveq   #0,d0
        move.w  #0x6602,0x3504
        jsr     0x6600
        move.l  d0,(a4)+
| 6. data write fault ($20000 always faults): no re-run, the handler resumes at (a2)
        moveq   #1,d6
        lea     0x20000,a1
        lea     1f(pc),a2
        movea.l sp,a6
        jsr     0x6500
1:      move.l  d7,(a4)+
        move.l  #0x600dc0de,0x3300
2:      bra.s   2b

berr:   addq.l  #1,d7
        move.w  #0,0x3504               | repair: the word reads normally again
        move.w  6(sp),(a4)+             | format/vector
        move.w  10(sp),(a4)+            | SSW
        move.w  12(sp),(a4)+            | stage C
        move.w  14(sp),(a4)+            | stage B
        move.l  2(sp),(a4)+             | PC
        tst.l   d6
        bne.s   1f
        rte
1:      movea.l a6,sp
        jmp     (a2)
