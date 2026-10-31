K=6; tests=[]; L=[]
def T(desc,pre,prior,ea,exp,patch=False,dest='%d7'):
    tests.append((desc,pre,prior,ea,exp,patch,dest))
forms={'F1':('(0,%a0,{x})',0),'F2':('(8.w,%a0,{x})',2),'F3':('(0x0.l,%za0,{x})',0),
       'F4':('(T,%pc,{x})',0),'F5':('([0.w,%a2,{x}],0.w)',0),'F6':('([0.w,%a6],{x},0.w)',0)}
for X in ['d1','a1']:
  for sz in ['w','l']:
    for s in [1,2,4,8]:
      v=4*K//s
      if X=='d1':
        pri={'moveq':([],f'moveq #{v},%d1'),'move':([f'moveq #{v},%d3'],'move.l %d3,%d1'),
             'lsr':([f'moveq #{2*v},%d1'],'lsr.l #1,%d1'),'addq':([f'moveq #{v-1},%d1'],'addq.l #1,%d1'),
             'add':(['moveq #0,%d1',f'moveq #{v},%d3'],'add.l %d3,%d1'),'movew':([f'moveq #{v},%d3','moveq #-1,%d1' if sz=='w' else 'moveq #0,%d1'],'move.w %d3,%d1'),
             'load':([f'move.l #{v},(%a4)'],'move.l (%a4),%d1'),'lsl3':([f'moveq #{v//8 if v%8==0 else v},%d1'],'lsl.l #3,%d1' if v%8==0 else 'nop')}
      else:
        pri={'movea':([f'moveq #{v},%d3'],'movea.l %d3,%a1'),'lea':([f'moveq #{v},%d3','suba.l %a3,%a3'],'lea (%a3,%d3.l),%a1'),
             'addq':([f'move.l #{v-1},%a1'],'addq.l #1,%a1'),'load':([f'move.l #{v},(%a4)'],'move.l (%a4),%a1'),
             'adda':(['suba.l %a1,%a1',f'moveq #{v},%d3'],'adda.l %d3,%a1')}
      for pn,(pre,pr) in pri.items():
        for fn,(ea,off) in forms.items():
          x=f'%{X}.{sz}*{s}'
          T(f'{fn} {X}.{sz}*{s} {pn}',pre,pr,ea.format(x=x),K+off,fn=='F3')
          if fn=='F1' and X=='d1':
            T(f'{fn} {X}.{sz}*{s} {pn} dest=d1',pre,pr,ea.format(x=x),K+off,False,'%d1')
# base register written by the previous instruction
for fn,ea,base in [('F1','(0,%a0,%d1.l*4)','%a0'),('F2','(8.w,%a0,%d1.l*4)','%a0'),('F5','([0.w,%a2,%d1.l*4],0.w)','%a2'),('F6','([0.w,%a6],%d1.l*4,0.w)','%a6')]:
    src={'%a0':'%a5','%a2':'%a3','%a6':'%a4'}[base]
    pre=[f'moveq #{K},%d1']
    setp={'%a0':['lea T(%pc),%a3','move.l %a3,(%a4)'],'%a2':['lea P(%pc),%a3','move.l %a3,(%a4)'],'%a6':['lea Q(%pc),%a3','move.l %a3,(%a4)']}[base]
    T(f'{fn} base {base} loaded by prev insn',pre+setp,f'movea.l (%a4),{base}',ea,K+(2 if fn=='F2' else 0))
o=['| generated EA torture test','\t.text','\tpea sup(%pc)','\tmove.w #38,-(%sp)','\ttrap #14','\taddq.l #6,%sp',
 '\tlea out(%pc),%a5','\tpea (%a5)','\tmove.w #9,-(%sp)','\ttrap #1','\taddq.l #6,%sp','\tmove.w #7,-(%sp)','\ttrap #1','\taddq.l #2,%sp','\tclr.w -(%sp)','\ttrap #1',
 'sup:\tlea T(%pc),%a0','\tlea P(%pc),%a2','\tmove.l %a0,%d0','\tmoveq #63,%d2','fp:\tmove.l %d0,(%a2)+','\taddq.l #4,%d0','\tdbra %d2,fp',
 '\tlea Q(%pc),%a2','\tmove.l %a0,(%a2)',
 '\tlea fix(%pc),%a2','fx:\tmove.l (%a2)+,%d0','\tbeq fxd','\tlea base(%pc),%a3','\tmove.l %a0,(4,%a3,%d0.l)','\tbra fx','fxd:',
 '\tmovec %cacr,%d0','\tor.w #0x0808,%d0','\tmovec %d0,%cacr',
 '\tlea fl(%pc),%a3','\tmove.l %a3,flp-fl(%a3)','\tmoveq #0,%d6','\tmove.w #1,passn-fl(%a3)','pass:']
o.append('base:')
for i,(d,pre,pr,ea,exp,patch,dest) in enumerate(tests):
    o.append(f'| {i}: {d}')
    o+= ['\tlea T(%pc),%a0','\tlea P(%pc),%a2','\tlea Q(%pc),%a6','\tlea W(%pc),%a4','\tlea Q(%pc),%a5']+['\t'+p for p in pre]+['\t'+pr]
    lab=f'e{i}'
    o.append(f'{lab}:\tmove.l {ea},{dest}')
    if patch: L.append(lab)
    o+= [f'\tcmp.l #0x{0xA5000000+exp:08x},{dest}','\tbeq.w k%d'%i,f'\tmove.w #{i},%d0',f'\tmove.l {dest},%d2','\tbsr rec',f'k{i}:']
o+=['\tlea fl(%pc),%a3','\tsubq.w #1,passn-fl(%a3)','\tbpl.l pass']
o+=open('tail.s').read().splitlines()
o.append('fix:')
o+=[f'\t.long {l}-base' for l in L]+['\t.long 0']
o+=['\t.even','T:']+[f'\t.long 0x{0xA5000000+i:08x}' for i in range(64)]
o+=['P:\t.ds.l 64','Q:\t.long 0','W:\t.long 0','fl:\t.ds.l 32','flp:\t.long 0','passn:\t.word 0','\t.even','out:\t.ds.b 2048']
open('ea3.s','w').write('\n'.join(o)+'\n')
open('tests.txt','w').write('\n'.join(f'{i}: {t[0]}' for i,t in enumerate(tests))+'\n')
print(len(tests),len(L))
