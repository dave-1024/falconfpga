| [PMMU2] MMU configuration exception (MC68030UM 8.1.10 p8-21/22, 9.7.1 p9-53, 9.7.2 p9-54):
| PMOVE of an invalid TC (E=1) or of a CRP/SRP with DT=0 loads the register and then takes vector 56 ($E0)
| as a post-instruction exception: format $2 frame with SR, the PC of the next instruction, $20E0 and the
| address of the PMOVE. The next instruction must not have run (d3 = 0 in the handler).
| The handler logs SR, PC, format/vector, address, d3 from $5000 on.
        .text
        .org 0
        .long   0x00008000
        .long   0x00fc0008
start:
        move.l  #mmucfg,0xe0
        lea     0x5000,a4
        lea     0x4000,a0
        moveq   #0,d3
        move.l  #0x80c0a000,(a0)        | E=1, 12+10 /= 32: invalid
pm1:    pmove   (a0),tc
nx1:    moveq   #1,d3
        pmove   tc,(a4)+                | E cleared: $00C0A000
        moveq   #0,d3
        clr.l   0x4010
        clr.l   0x4014
pm2:    pmove   0x4010,crp              | DT = 0
nx2:    moveq   #2,d3
        moveq   #0,d3
        move.l  #0x7fff0002,0x4010      | DT = 2: valid, no exception
        pmove   0x4010,srp
        move.l  #1,0x4018               | [PMMU2b] identity CRP (DT 1) for the valid-TC window
        clr.l   0x401c
        pmove   0x4018,crp
        move.l  #0x80c0aa00,(a0)        | valid TC
        pmove   (a0),tc
        clr.l   (a0)
        pmove   (a0),tc
        moveq   #0,d3
        clr.l   0x4010
pm3:    pmove   0x4010,srp              | DT = 0
nx3:    moveq   #3,d3
        move.w  d3,(a4)+                | 3: execution continued after the handler
        move.l  #0x600dc0de,0x3300
2:      bra.s   2b
mmucfg: move.w  (sp),(a4)+
        move.l  2(sp),(a4)+
        move.w  6(sp),(a4)+
        move.l  8(sp),(a4)+
        move.w  d3,(a4)+
        rte
