| F60 CHK test: Dn (not A0) must be checked. a0 is set to a value whose low word
| is negative ($CDA4) and a5 etc. to junk, so the old bug traps on every CHK.
        .text
        .org 0
        .long   0x00008000
        .long   0x00fc0008
start:
        move.l  #chkh,0x18
        lea     0x5000,a4
        moveq   #0,d7
        movea.l #0x0002cda4,a0
        lea     desc1,a1
        moveq   #0,d1
        chk.w   (a1)+,d1                | 0<=5 no trap           -> 0
        move.l  d7,(a4)+
        move.l  a1,(a4)+                | desc1+2
        lea     desc1,a1
        moveq   #5,d1
        chk.w   (a1),d1                 | 5 no trap              -> 0
        move.l  d7,(a4)+
        moveq   #6,d1
        chk.w   (a1),d1                 | 6>5 trap               -> 1
        move.l  d7,(a4)+
        moveq   #-1,d1
        chk.w   #5,d1                   | -1 trap                -> 2
        move.l  d7,(a4)+
        move.l  #0xffff0002,d1
        moveq   #5,d2
        chk.w   d2,d1                   | low word 2 no trap     -> 2
        move.l  d7,(a4)+
        movea.l #0,a0
        moveq   #9,d1
        chk.w   2(a1),d1                | bound $1111, 9 no trap -> 2
        move.l  d7,(a4)+
        move.w  #0x2000,d1
        chk.w   2(a1),d1                | $2000>$1111 trap       -> 3
        move.l  d7,(a4)+
        move.l  #0x00012345,d3
        chk.l   #0x00020000,d3          | chk.l no trap          -> 3
        move.l  d7,(a4)+
        chk.l   #0x00012344,d3          | chk.l trap             -> 4
        move.l  d7,(a4)+
        movea.l #0x00000003,a0          | old bug: would check 3
        moveq   #7,d1
        chk.w   #5,d1                   | 7>5 trap               -> 5
        move.l  d7,(a4)+
        move.l  d1,(a4)+                | d1 unchanged = 7
        move.l  #0x600dc0de,0x3300
self:   bra.s   self
chkh:   addq.l  #1,d7
        rte
        .even
desc1:  .word   5, 0x1111, 0x2222
