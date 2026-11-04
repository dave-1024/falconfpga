import random,sys,re
seed=int(sys.argv[1]); r=random.Random(seed); N=int(sys.argv[2]) if len(sys.argv)>2 else 300
ops2=['add','sub','and','or','cmp']
L=[]
def D(): return 'd%d'%r.randrange(0,6)
def A(): return 'a%d'%r.randrange(0,4)
def sz(): return r.choice(['.b','.w','.l'])
for i in range(N):
    k=r.randrange(27)
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
    elif k==15: L+= [f"move.l {D()},-(sp)", f"move.l {D()},-(sp)", f"addq.l #8,sp"]
    elif k==16: L+= [f"move.l {D()},-(sp)", f"move.w {D()},-(sp)", f"move.w (sp),{D()}", f"addq.w #6,sp" if r.random()<0.5 else "addq.l #6,sp"]
    elif k==17: L+= [f"subq.l #4,sp", f"move.l {D()},(sp)", f"adda.l d6,sp", f"suba.l d6,sp", f"move.l (sp)+,{D()}"]
    elif k==18: L+= [f"move.l {D()},-(sp)", "bsr sub2", f"move.l (sp),{D()}", "addq.l #4,sp"]
    elif k==19: a=A(); b=A(); L+= [f"adda.w d6,{a}", f"move.l 0({b},{a}.w),{D()}", f"suba.w d6,{a}"]
    elif k==20: a=A(); L+= ["addq.l #2,d6", f"move.w 0({a},d6.w),{D()}", f"move.l {D()},2({a},d6.l)", "subq.l #2,d6"]
    elif k==21: a=A(); b=A(); L+= [f"addq.l #4,{a}", f"lea 4({a}),{b}", f"move.l {D()},({b})"]
    elif k==22: a=A(); L+= [f"subq.l #8,{a}", f"movem.l d0-d1,({a})", f"addq.l #8,{a}", f"movem.l -8({a}),d2-d3"]
    elif k==23: a=A(); L+= [f"addq.l #4,{a}", f"move.l ({a})+,{D()}", f"move.l {D()},-({a})"]
    elif k==24: a=A(); L+= [f"subq.l #2,{a}", f"pea ({a})", f"move.l (sp)+,{D()}"]
    elif k==25: a=A(); L+= [f"tst.l {a}", f"cmp.l {a},{D()}", f"add.l {a},{D()}", f"move.l {D()},({a})"]
    elif k==26: L+= ["lea sub2,a4", "subq.l #2,a4", "addq.l #2,a4", f"move.l {D()},-(sp)", "jsr (a4)", "addq.l #4,sp"]
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
    elif l.endswith(' 1f'): body.append(l[:-2]+f'{900+lab}f')
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
{{umode}}{init}
"""+"\n".join("        "+b if not b.endswith(':') else b for b in body)+"""
        move.l #0x600dc0de,0x3300
9:      bra.s 9b
sub2:   move.l 4(sp),d7
        addq.l #1,d7
        move.l d7,4(sp)
        rts
hnd:    movem.l d0/a0,-(sp)
        moveq #5,d0
        addq.l #3,d0
        movea.l d0,a0
        adda.l d0,a0
        movem.l (sp)+,d0/a0
        rte
"""
um = "        lea 0x6800,a4\n        move.l a4,usp\n        andi.w #0xdfff,sr\n" if len(sys.argv)>4 and sys.argv[4]=='u' else ""
s=s.replace("{umode}",um)
open(sys.argv[3],'w').write(s)
