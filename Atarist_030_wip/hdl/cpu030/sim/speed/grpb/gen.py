import random,sys
seed=int(sys.argv[1]); r=random.Random(seed); N=int(sys.argv[2]) if len(sys.argv)>2 else 300
ops2=['add','sub','and','or','cmp']
L=[]
def D(): return 'd%d'%r.randrange(0,6)
def A(): return 'a%d'%r.randrange(0,4)
def sz(): return r.choice(['.b','.w','.l'])
for i in range(N):
    k=r.randrange(15)
    if k==0: L.append(f"{r.choice(ops2)}{sz()} {D()},{D()}")
    elif k==1: s=r.choice(['.w','.l']); L.append(f"{r.choice(['add','sub','cmp'])}{s} {A()},{D()}")
    elif k==2: a=A(); L.append(f"{r.choice(['adda','suba'])}{r.choice(['.w','.l'])} d6,{a}"); L.append(f"move.l {D()},({a})"); L.append(f"move.l ({a}),{D()}")
    elif k==3: L.append(f"{r.choice(['addq','subq'])}{sz()} #{r.randrange(1,9)},{D()}")
    elif k==4: L.append(f"{r.choice(['addq','subq'])}{r.choice(['.w','.l'])} #{r.randrange(1,9)},{A()}")
    elif k==5: L.append(f"{r.choice(['clr','neg','negx','not','tst'])}{sz()} {D()}")
    elif k==6: L.append(f"eor{sz()} {D()},{D()}")
    elif k==7: # use An as address right after
        a=A(); L.append(f"move.l {a},d7"); L.append(f"and.l #0x1fc,d7"); L.append(f"add.l #0x2000,d7"); L.append(f"movea.l d7,{a}")
    elif k==8: a=A(); L.append(f"move.l {D()},({a})"); L.append(f"add.l ({a}),{D()}")
    elif k==9: a=A(); L.append(f"addq.l #4,{a}"); L.append(f"move.l {D()},-4({a})"); L.append(f"move.l -4({a}),{D()}")
    elif k==10: L.append(f"{r.choice(['add','sub'])}x{sz()} {D()},{D()}")
    elif k==11: L.append(f"s{r.choice(['eq','ne','cs','cc','mi','pl','vs','gt','le'])} {D()}")
    elif k==12: a=A(); L.append(f"subq.l #2,{a}"); L.append(f"move.w ({a})+,{D()}")
    elif k==13 and r.random()<0.5: L.append("trap #0")
    else: L.append(f"b{r.choice(['eq','ne','cs','mi','gt'])}.s 1f"); L.append(f"addq.l #1,{D()}"); L.append("1:")
# keep An in range: renormalise every 6 instr
out=[]; c=0
for l in L:
    out.append(l); c+=1
    if c%6==0:
        out.append(f"moveq #{r.randrange(0,64)*2},d6")
        for a in range(4): out+= [f"move.l a{a},d7",f"and.l #0x1fc,d7",f"add.l #0x2000,d7",f"movea.l d7,a{a}"]
        out.append("movem.l d0-d6/a0-a3,(a5)"); out.append("lea 44(a5),a5")
body=[]
lab=0
for l in out:
    if l=="1:": body.append(f"{900+lab}:"); lab+=1
    elif '1f' in l: body.append(l.replace('1f',f'{900+lab}f'))
    else: body.append(l)
init="\n".join(f"        move.l #0x{r.getrandbits(32):08x},d{i}" for i in range(6))+"\n        moveq #8,d6"
s=f"""        .text
        .long 0x00007000
        .long 0x00fc0008
        lea 0x2000,a0
        lea 0x2100,a1
        lea 0x2200,a2
        lea 0x2300,a3
        lea 0x5000,a5
        move.l #hnd,0x70
        move.l #hnd,0x78
        move.l #hnd,0x80
        move.w #0x2000,sr
{init}
"""+"\n".join("        "+b if not b.endswith(':') else b for b in body)+"""
        move.l #0x600dc0de,0x3300
9:      bra.s 9b
hnd:    movem.l d0/a0,-(sp)
        moveq #5,d0
        addq.l #3,d0
        movea.l d0,a0
        adda.l d0,a0
        movem.l (sp)+,d0/a0
        rte
"""
open(sys.argv[3],'w').write(s)
