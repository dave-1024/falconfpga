| Warm-reset test: the first pass dirties the CPU state (VBR, CACR, SFC/DFC, MSP/USP,
| SR with T1 and M set, trace running), writes $3500 so tb030 pulls RESET+HALT low
| (WRST_DLY/WRST_LEN), and keeps running. After the reset the core must fetch SSP/PC
| from $0/$4 and start with SR $2700, VBR 0, CACR 0, ISP active.
| RSTI=1: the first pass executes RESET (RESET_OUT 512 clocks) and tb030 fires the warm
| reset while RESET_OUT is still active.
| Results at $5000: SR, VBR, CACR, SP, trace count, boots.
        .text
        .org 0
        .long   0x00008000
        .long   0x00fc0008
start:
        addq.l  #1,0x3008               | boot count
        cmpi.l  #0xc0de,0x3000
        beq     second
        move.l  #0xc0de,0x3000
        lea     0x2000,a0               | vector table at $2000: all -> rte, trace -> count
        lea     anyh(pc),a1
        move.w  #255,d0
1:      move.l  a1,(a0)+
        dbra    d0,1b
        lea     traceh(pc),a1
        move.l  a1,0x2024
        lea     0x2000,a0
        movec   a0,vbr
        moveq   #1,d0
        movec   d0,cacr
        moveq   #5,d0
        movec   d0,sfc
        movec   d0,dfc
        lea     0x7000,a1
        movec   a1,msp
        lea     0x6000,a1
        move.l  a1,usp
        move.w  #0x3700,sr              | M=1: now on MSP
        move.w  #1,0x3500               | trigger the warm reset
.if RSTI
        reset
.endif
        ori.w   #0x8000,sr              | T1 on
loop:   addq.l  #1,0x300c
        bra.s   loop
anyh:   rte
traceh: addq.l  #1,0x3004
        rte

second: lea     0x5000,a4
        move.w  sr,d0
        ext.l   d0
        andi.l  #0xffff,d0
        move.l  d0,(a4)+                | 00002700
        movec   vbr,d0
        move.l  d0,(a4)+                | 00000000
        movec   cacr,d0
        move.l  d0,(a4)+                | 00000000
        move.l  sp,(a4)+                | 00008000 (ISP from $0)
        move.l  0x3004,d0
        sne     d0
        andi.l  #1,d0
        move.l  d0,(a4)+                | 00000001: trace ran before the reset
        move.l  0x3008,(a4)+            | 00000002 boots
        move.w  #1,0x3300               | DONE
2:      bra.s   2b
