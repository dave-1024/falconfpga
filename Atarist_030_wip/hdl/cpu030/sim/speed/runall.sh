#!/bin/bash
# runall.sh <workdir> <outfile>
export WORKDIR=$1; H=$(cd "$(dirname "$0")" && pwd); cd $H
E0=$(./one.sh _empty "" 0 | awk '{print $2}')
grep -v '^#' tests.txt | grep . | while IFS='|' read n b K m note; do echo "$n|$b|$K|$m|$note"; done > /tmp/tl.$$
cat /tmp/tl.$$ | tr '\n' '\0' | xargs -0 -P8 -I{} bash -c 'IFS="|" read n b K m note <<< "{}"; h=$((K/2)); r1=$(./one.sh "$n" "$b" "$K" | awk "{print \$2}"); r2=$(./one.sh "${n}_h" "$b" "$h" | awk "{print \$2}"); r=NA; [[ $r1 =~ ^[0-9]+$ && $r2 =~ ^[0-9]+$ ]] && r=$((r1-r2)); echo "$n|$h|$m|$r|$note"' > /tmp/res.$$
python3 - "$E0" /tmp/res.$$ $2 <<'P'
import sys
e0=int(sys.argv[1]); out=[]
order=[l.split('|')[0] for l in open('tests.txt') if l.strip() and not l.startswith('#')]
d={}
for l in open(sys.argv[2]):
    n,K,m,r,note=l.rstrip('\n').split('|'); d[n]=(int(K),m,r,note)
for n in order:
    K,m,r,note=d[n]
    v='NA' if not r.lstrip('-').isdigit() else '%.2f'%(int(r)/K)
    out.append(f"{n}|{m}|{v}|{note}")
open(sys.argv[3],'w').write("empty=%d\n"%e0+"\n".join(out)+"\n"); print(open(sys.argv[3]).read())
P
