| [XH2] Bus error while stacking a TRAP frame: SSP $30004, the first long goes to $30000, the second to
| $2FFFC (tb030 BERR range $20000-$2FFFF). The bus error exception then stacks below and faults again
| (double bus fault, halt): the write addresses show the SP the core used at each step.
        .text
        .org 0
        .long   0x00008000
        .long   0x00fc0008
start:  move.l  #berr,0x08
        move.l  #0x20004,0x3f00
        move.l  #trap0,0x80
        move.w  #1,0x5000
        nop
        movea.l #0x20004,sp             | case 1: the first long ($20000) faults, the BERR frame goes below $20000
        trap    #0
        move.w  #5,0x5008
after1:
        movea.l #0x30004,sp             | case 2: the second long ($2FFFC) faults (then double fault)
        trap    #0
        move.w  #2,0x5002
        move.l  #0x600dc0de,0x3300
halt:   bra.s   halt
berr:   move.w  #3,0x5004
        move.l  sp,0x500c
        lea     12(sp),a0
        move.l  a0,0x5010
        cmpi.l  #0x20004,0x3f00
        bne.s   1f
        move.l  #0x30004,0x3f00
        move.l  #0x7f00,sp
        jmp     after1
1:      move.l  #0x600dc0de,0x3300
        bra.s   halt
trap0:  move.w  #4,0x5006
        rte
