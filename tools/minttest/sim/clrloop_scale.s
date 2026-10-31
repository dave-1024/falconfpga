| F92: MiNT clear loop ($15236..$15250) with a small table, caches off then I+D on (CACR $3111? use $2111 = ED|WA? keep $0101 = EI|ED)
        .text
        .globl _start
_start: lea     0x2000,%a0              | descriptor: 4(a0)=a4 array, 8(a0)=a5 array
        move.l  #0x3000,4(%a0)
        move.l  #0x3100,8(%a0)
        moveq   #2,%d6
loop0:  move.l  #0x40,%d2
        move.l  4(%a0),%a4
        clr.l   %d1
1:      clr.l   (%a4,%d1.l*4)
        movea.l 8(%a0),%a5
        clr.w   (%a5,%d1.l*2)
        addq.l  #1,%d1
        cmp.l   %d1,%d2
        beq     2f
        movea.l 4(%a0),%a4
        bra     1b
2:      move.l  #0x0101,%d0             | 2nd pass: I+D caches on
        movec   %d0,%cacr
        subq.l  #1,%d6
        bne     loop0
        move.w  #1,0x3300
3:      bra     3b
