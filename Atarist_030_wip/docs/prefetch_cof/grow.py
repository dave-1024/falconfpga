import difflib,collections,sys
def ld(p): return [(l.split()[2]+l.split()[3]+l.split()[4], int(l.split()[1])) for l in open(p) if l[0].isdigit()]
a=ld(sys.argv[1]); b=ld(sys.argv[2])
sm=difflib.SequenceMatcher(None,[x[0] for x in a],[x[0] for x in b],autojunk=False)
pairs=[(bl.a+k,bl.b+k) for bl in sm.get_matching_blocks() for k in range(bl.size)]
g=collections.Counter(); c=collections.Counter()
for (i0,j0),(i1,j1) in zip(pairs,pairs[1:]):
    d=(b[j1][1]-b[j0][1])-(a[i1][1]-a[i0][1])
    if d: g[b[j1][0]]+=d; c[b[j1][0]]+=1
print('total',sum(g.values()))
for k,v in g.most_common(12): print(k,v,c[k])
