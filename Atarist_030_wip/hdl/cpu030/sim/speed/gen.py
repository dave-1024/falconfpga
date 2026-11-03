import sys
def prog(body,K,outfile):
    blk=("\n".join([body.replace(';','\n').replace('1f','%df'%(100+i)).replace('1:','%d:'%(100+i)).replace('1b','%db'%(100+i)) for i in range(K)])) if K else ""
    s=f"""        .text
        .long 0x00007000
        .long 0x00fc0008
        jmp L
        .org 0x10000-8
L:      moveq #1,d7
        movec d7,cacr
        lea 0x2000,a0
        lea 0x2200,a1
        lea sub,a3
        moveq #3,d1
        moveq #4,d4
        moveq #7,d5
        move.l #0x12345,d0
        moveq #1,d7
        .balign 4
top:    move.w d7,0x3400
{blk}
        dbf d7,top
        move.w #0xffff,0x3400
        move.l #0x600dc0de,0x3300
s:      bra.s s
sub:    rts
"""
    open(outfile,'w').write(s)
if __name__=="__main__":
    prog(sys.argv[1],int(sys.argv[2]),sys.argv[3])
